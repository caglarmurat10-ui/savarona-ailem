import { DurableObject } from 'cloudflare:workers';
import type { Env } from './types';

export class FamilyLive extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
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
      let delivered = 0;
      for (const ws of this.ctx.getWebSockets()) {
        try { ws.send(message); delivered++; } catch { /* connection cleanup is automatic */ }
      }
      return Response.json({ ok: true, delivered });
    }

    return new Response('Not found', { status: 404 });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    if (typeof message !== 'string') return;
    if (message === 'ping') ws.send(JSON.stringify({ type: 'pong', ts: Date.now() }));
  }

  async webSocketClose(ws: WebSocket, code: number, reason: string): Promise<void> {
    ws.close(code, reason);
  }
}
