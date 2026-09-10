import { DurableObject } from 'cloudflare:workers';
import type { Env } from './types';

type PresenceRecord = {
  deviceId: string;
  memberId: string;
  lastSeenAt: number;
  dueAt: number;
};

export class FamilyLive extends DurableObject<Env> {
  private readonly env: Env;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.env = env;
  }

  private async broadcast(message: string): Promise<number> {
    let delivered = 0;
    for (const ws of this.ctx.getWebSockets()) {
      try { ws.send(message); delivered++; } catch { /* connection cleanup is automatic */ }
    }
    return delivered;
  }

  private async armPresenceAlarm(payload: any): Promise<void> {
    if (!payload || !['location', 'heartbeat'].includes(payload.type)) return;
    const deviceId = typeof payload.device_id === 'string' ? payload.device_id : '';
    const memberId = typeof payload.member_id === 'string' ? payload.member_id : '';
    const lastSeenAt = Number(payload.received_at ?? payload.ts ?? Date.now());
    if (!deviceId || !memberId || !Number.isFinite(lastSeenAt)) return;

    const offlineSeconds = Math.max(60, Number(this.env.OFFLINE_SECONDS || '180'));
    const dueAt = lastSeenAt + offlineSeconds * 1000;
    const record: PresenceRecord = { deviceId, memberId, lastSeenAt, dueAt };
    await this.ctx.storage.put(`presence:${deviceId}`, record);

    const currentAlarm = await this.ctx.storage.getAlarm();
    if (currentAlarm == null || dueAt < currentAlarm) {
      await this.ctx.storage.setAlarm(dueAt);
    }
  }

  private async scheduleNextAlarm(): Promise<void> {
    const entries = await this.ctx.storage.list<PresenceRecord>({ prefix: 'presence:' });
    let next: number | null = null;
    for (const record of entries.values()) {
      if (!Number.isFinite(record.dueAt)) continue;
      if (next == null || record.dueAt < next) next = record.dueAt;
    }
    if (next == null) {
      await this.ctx.storage.deleteAlarm();
    } else {
      await this.ctx.storage.setAlarm(Math.max(next, Date.now() + 1000));
    }
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname.endsWith('/connect')) {
      if (request.headers.get('Upgrade') !== 'websocket') {
        return new Response('Expected websocket', { status: 426 });
      }
      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);
      this.ctx.acceptWebSocket(server);
      server.serializeAttachment({
        memberId: request.headers.get('x-member-id') || '',
        deviceId: request.headers.get('x-device-id') || '',
        connectedAt: Date.now(),
      });
      server.send(JSON.stringify({ type: 'connected', ts: Date.now() }));
      return new Response(null, { status: 101, webSocket: client });
    }

    if (url.pathname.endsWith('/publish') && request.method === 'POST') {
      const message = await request.text();
      try { await this.armPresenceAlarm(JSON.parse(message)); } catch { /* malformed payload should not block broadcast */ }
      const delivered = await this.broadcast(message);
      return Response.json({ ok: true, delivered });
    }

    return new Response('Not found', { status: 404 });
  }

  async alarm(): Promise<void> {
    const offlineSeconds = Math.max(60, Number(this.env.OFFLINE_SECONDS || '180'));
    const now = Date.now();
    const entries = await this.ctx.storage.list<PresenceRecord>({ prefix: 'presence:' });

    for (const [key, record] of entries) {
      if (!Number.isFinite(record.dueAt) || record.dueAt > now) continue;

      const row = await this.env.DB.prepare(`SELECT d.id AS device_id,d.family_id,d.member_id,d.last_seen_at,d.stale_notified_at,m.display_name
        FROM devices d JOIN members m ON m.id=d.member_id
        WHERE d.id=?1 AND d.revoked_at IS NULL LIMIT 1`)
        .bind(record.deviceId).first<any>();

      if (!row) {
        await this.ctx.storage.delete(key);
        continue;
      }

      const lastSeenAt = Number(row.last_seen_at || 0);
      const authoritativeDue = lastSeenAt + offlineSeconds * 1000;
      if (lastSeenAt > record.lastSeenAt || authoritativeDue > now) {
        await this.ctx.storage.put(key, {
          deviceId: row.device_id,
          memberId: row.member_id,
          lastSeenAt,
          dueAt: authoritativeDue,
        } satisfies PresenceRecord);
        continue;
      }

      if (row.stale_notified_at == null) {
        const ts = Date.now();
        const claim = await this.env.DB.prepare(`UPDATE devices SET stale_notified_at=?1,app_state='stale'
          WHERE id=?2 AND stale_notified_at IS NULL AND last_seen_at<=?3`)
          .bind(ts, row.device_id, lastSeenAt).run();
        if ((claim.meta?.changes ?? 0) > 0) {
          await this.broadcast(JSON.stringify({
            type: 'device_stale',
            device_id: row.device_id,
            member_id: row.member_id,
            member_name: row.display_name,
            last_seen_at: lastSeenAt,
            ts,
          }));
        }
      }

      await this.ctx.storage.delete(key);
    }

    await this.scheduleNextAlarm();
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    if (typeof message !== 'string') return;
    if (message === 'ping') ws.send(JSON.stringify({ type: 'pong', ts: Date.now() }));
  }

  async webSocketClose(ws: WebSocket, code: number, reason: string): Promise<void> {
    ws.close(code, reason);
  }
}
