import { authenticate } from './auth';
import { encryptSecret, randomToken, sha256Hex, signTicket, verifyTicket } from './crypto';
import { FamilyLive } from './realtime';
import { clientIp, rateLimited } from './rate_limit';
import { listGeofences, createGeofence, updateGeofence, deleteGeofence, evaluateGeofences } from './geofence';
import type { Env, LocationPayload, DevicePrincipal } from './types';

export { FamilyLive };

const jsonHeaders = { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' };
const j = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: jsonHeaders });
const err = (code: string, status = 400, detail?: string) => j({ ok: false, error: code, detail }, status);
const now = () => Date.now();

async function body<T = any>(request: Request): Promise<T | null> {
  try { return await request.json<T>(); } catch { return null; }
}

function validLocation(p: any): p is LocationPayload {
  if (!p || typeof p !== 'object') return false;
  if (!Number.isFinite(p.captured_at) || p.captured_at < 1_600_000_000_000 || p.captured_at > Date.now() + 300_000) return false;
  if (!Number.isFinite(p.lat) || p.lat < -90 || p.lat > 90) return false;
  if (!Number.isFinite(p.lng) || p.lng < -180 || p.lng > 180) return false;
  if (p.accuracy_m != null && (!Number.isFinite(p.accuracy_m) || p.accuracy_m < 0 || p.accuracy_m > 100000)) return false;
  if (p.speed_mps != null && (!Number.isFinite(p.speed_mps) || p.speed_mps < 0 || p.speed_mps > 150)) return false;
  if (p.heading_deg != null && (!Number.isFinite(p.heading_deg) || p.heading_deg < 0 || p.heading_deg >= 360)) return false;
  if (p.battery_pct != null && (!Number.isInteger(p.battery_pct) || p.battery_pct < 0 || p.battery_pct > 100)) return false;
  return true;
}

async function publish(env: Env, familyId: string, payload: unknown): Promise<void> {
  const id = env.FAMILY_LIVE.idFromName(familyId);
  const stub = env.FAMILY_LIVE.get(id);
  await stub.fetch('https://do.internal/publish', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(payload),
  });
}

async function requireAuth(request: Request, env: Env): Promise<DevicePrincipal | Response> {
  const p = await authenticate(request, env);
  return p || err('unauthorized', 401);
}

async function bootstrap(request: Request, env: Env): Promise<Response> {
  if (await rateLimited(env, 'RATE_LIMIT_BOOTSTRAP', clientIp(request))) return err('rate_limited', 429);
  const secret = request.headers.get('x-bootstrap-secret');
  if (!secret || secret !== env.ADMIN_BOOTSTRAP_SECRET) return err('forbidden', 403);

  const b = await body<any>(request);
  if (!b?.family_name || !b?.owner_name || !b?.device_name) return err('invalid_body');
  const platform = ['android','ios','other'].includes(b.platform) ? b.platform : 'other';
  const done = await env.DB.prepare("SELECT value FROM app_meta WHERE key='bootstrap_completed'").first();

  if (done) {
    const owner = await env.DB.prepare(`SELECT id AS member_id,family_id FROM members WHERE role='owner' ORDER BY created_at ASC LIMIT 1`).first<any>();
    if (!owner?.member_id || !owner?.family_id) return err('owner_not_found', 409);

    const deviceId = crypto.randomUUID();
    const token = randomToken(32);
    const tokenHash = await sha256Hex(token);
    const ts = now();

    await env.DB.batch([
      env.DB.prepare(`UPDATE push_tokens SET revoked_at=?1
                      WHERE device_id IN (SELECT id FROM devices WHERE member_id=?2 AND revoked_at IS NULL)
                        AND revoked_at IS NULL`).bind(ts, owner.member_id),
      env.DB.prepare(`UPDATE devices SET revoked_at=?1,app_state='revoked'
                      WHERE member_id=?2 AND revoked_at IS NULL`).bind(ts, owner.member_id),
      env.DB.prepare(`INSERT INTO devices(id,family_id,member_id,display_name,platform,token_hash,created_at)
                      VALUES(?1,?2,?3,?4,?5,?6,?7)`)
        .bind(deviceId, owner.family_id, owner.member_id, String(b.device_name).slice(0,80), platform, tokenHash, ts),
    ]);

    return j({
      ok: true,
      recovered: true,
      family_id: owner.family_id,
      member_id: owner.member_id,
      device_id: deviceId,
      device_token: token,
    }, 201);
  }

  const familyId = crypto.randomUUID();
  const memberId = crypto.randomUUID();
  const deviceId = crypto.randomUUID();
  const token = randomToken(32);
  const tokenHash = await sha256Hex(token);
  const ts = now();

  await env.DB.batch([
    env.DB.prepare('INSERT INTO families(id,name,created_at) VALUES(?1,?2,?3)').bind(familyId, String(b.family_name).slice(0,80), ts),
    env.DB.prepare("INSERT INTO members(id,family_id,display_name,role,created_at) VALUES(?1,?2,?3,'owner',?4)").bind(memberId, familyId, String(b.owner_name).slice(0,80), ts),
    env.DB.prepare('INSERT INTO devices(id,family_id,member_id,display_name,platform,token_hash,created_at) VALUES(?1,?2,?3,?4,?5,?6,?7)').bind(deviceId, familyId, memberId, String(b.device_name).slice(0,80), platform, tokenHash, ts),
    env.DB.prepare("INSERT INTO app_meta(key,value,updated_at) VALUES('bootstrap_completed','1',?1)").bind(ts),
  ]);

  return j({ ok: true, family_id: familyId, member_id: memberId, device_id: deviceId, device_token: token }, 201);
}

async function createInvite(request: Request, env: Env, p: DevicePrincipal): Promise<Response> {
  if (await rateLimited(env, 'RATE_LIMIT_INVITE', p.deviceId)) return err('rate_limited', 429);
  if (p.role !== 'owner' && p.role !== 'admin') return err('forbidden', 403);
  const code = randomToken(7).replace(/[-_]/g, '').slice(0, 8).toUpperCase();
  const hash = await sha256Hex(code);
  const id = crypto.randomUUID();
  const ts = now();
  const expiresAt = ts + 24 * 60 * 60 * 1000;
  await env.DB.prepare(`INSERT INTO invites(id,family_id,code_hash,created_by_member_id,expires_at,created_at)
                        VALUES(?1,?2,?3,?4,?5,?6)`)
    .bind(id, p.familyId, hash, p.memberId, expiresAt, ts).run();
  return j({ ok: true, invite_code: code, expires_at: expiresAt }, 201);
}

async function joinFamily(request: Request, env: Env): Promise<Response> {
  if (await rateLimited(env, 'RATE_LIMIT_JOIN', clientIp(request))) return err('rate_limited', 429);
  const b = await body<any>(request);
  if (!b?.invite_code || !b?.member_name || !b?.device_name) return err('invalid_body');
  const codeHash = await sha256Hex(String(b.invite_code).trim().toUpperCase());
  const inv = await env.DB.prepare(`SELECT id,family_id,expires_at,used_at FROM invites WHERE code_hash=?1 LIMIT 1`).bind(codeHash).first<any>();
  if (!inv || inv.used_at || inv.expires_at < now()) return err('invite_invalid_or_expired', 400);

  const memberId = crypto.randomUUID();
  const deviceId = crypto.randomUUID();
  const token = randomToken(32);
  const tokenHash = await sha256Hex(token);
  const claimId = crypto.randomUUID();
  const ts = now();
  const platform = ['android','ios','other'].includes(b.platform) ? b.platform : 'other';

  try {
    await env.DB.batch([
      env.DB.prepare(`UPDATE invites SET used_at=?1,claim_id=?2
                      WHERE id=?3 AND used_at IS NULL AND expires_at>=?1`)
        .bind(ts, claimId, inv.id),
      env.DB.prepare("INSERT INTO members(id,family_id,display_name,role,created_at) VALUES(?1,(SELECT family_id FROM invites WHERE id=?2 AND claim_id=?3),?4,'member',?5)")
        .bind(memberId, inv.id, claimId, String(b.member_name).slice(0,80), ts),
      env.DB.prepare(`INSERT INTO devices(id,family_id,member_id,display_name,platform,token_hash,created_at)
                      VALUES(?1,(SELECT family_id FROM invites WHERE id=?2 AND claim_id=?3),?4,?5,?6,?7,?8)`)
        .bind(deviceId, inv.id, claimId, memberId, String(b.device_name).slice(0,80), platform, tokenHash, ts),
    ]);
  } catch (e) {
    const latest = await env.DB.prepare(`SELECT used_at,claim_id,expires_at FROM invites WHERE id=?1`).bind(inv.id).first<any>();
    if (latest?.used_at || (latest?.expires_at != null && Number(latest.expires_at) < now())) return err('invite_invalid_or_expired', 400);
    throw e;
  }

  await publish(env, inv.family_id, { type: 'member_joined', member_id: memberId, display_name: String(b.member_name).slice(0,80), ts });
  return j({ ok: true, family_id: inv.family_id, member_id: memberId, device_id: deviceId, device_token: token }, 201);
}

async function postLocation(request: Request, env: Env, p: DevicePrincipal): Promise<Response> {
  const b = await body<any>(request);
  if (!validLocation(b)) return err('invalid_location');
  const sequenceNo = Number(b.sequence_no);
  if (!Number.isInteger(sequenceNo) || sequenceNo < 1) return err('sequence_required', 409);
  const receivedAt = now();

  const results = await env.DB.batch([
    env.DB.prepare(`UPDATE devices
                    SET last_sequence_no=?1,last_seen_at=?2,battery_pct=COALESCE(?3,battery_pct),app_state='tracking',stale_notified_at=NULL
                    WHERE id=?4 AND last_sequence_no<?1`)
      .bind(sequenceNo, receivedAt, b.battery_pct ?? null, p.deviceId),
    env.DB.prepare(`INSERT INTO locations(family_id,member_id,device_id,captured_at,received_at,lat,lng,accuracy_m,altitude_m,speed_mps,heading_deg,battery_pct,activity,sequence_no)
      SELECT ?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14
       WHERE EXISTS(SELECT 1 FROM devices WHERE id=?3 AND last_sequence_no=?14)
         AND NOT EXISTS(SELECT 1 FROM locations WHERE device_id=?3 AND sequence_no=?14)`)
      .bind(p.familyId,p.memberId,p.deviceId,b.captured_at,receivedAt,b.lat,b.lng,b.accuracy_m ?? null,b.altitude_m ?? null,b.speed_mps ?? null,b.heading_deg ?? null,b.battery_pct ?? null,b.activity ?? null,sequenceNo),
  ]);
  const advanced = results[0]?.meta?.changes ?? 0;
  const inserted = results[1]?.meta?.changes ?? 0;
  if (advanced < 1 || inserted < 1) return err('replay_rejected', 409);

  const event = {
    type: 'location', member_id: p.memberId, member_name: p.memberName, device_id: p.deviceId,
    captured_at: b.captured_at, received_at: receivedAt, lat: b.lat, lng: b.lng,
    accuracy_m: b.accuracy_m ?? null, altitude_m: b.altitude_m ?? null,
    speed_mps: b.speed_mps ?? null, speed_kmh: b.speed_mps == null ? null : Math.round(b.speed_mps * 3.6 * 10) / 10,
    heading_deg: b.heading_deg ?? null, battery_pct: b.battery_pct ?? null, activity: b.activity ?? null,
  };
  await publish(env, p.familyId, event);
  await evaluateGeofences(env, p.familyId, p.memberId, p.memberName, b.lat, b.lng);
  return j({ ok: true, received_at: receivedAt });
}

async function heartbeat(request: Request, env: Env, p: DevicePrincipal): Promise<Response> {
  const b = await body<any>(request) || {};
  const battery = Number.isInteger(b.battery_pct) && b.battery_pct >= 0 && b.battery_pct <= 100 ? b.battery_pct : null;
  const permission = typeof b.permission_state === 'string' ? b.permission_state.slice(0,40) : null;
  const appState = typeof b.app_state === 'string' ? b.app_state.slice(0,40) : null;
  const ts = now();
  await env.DB.prepare(`UPDATE devices SET last_seen_at=?1,battery_pct=COALESCE(?2,battery_pct),permission_state=COALESCE(?3,permission_state),app_state=COALESCE(?4,app_state),stale_notified_at=NULL WHERE id=?5`)
    .bind(ts,battery,permission,appState,p.deviceId).run();
  await publish(env, p.familyId, { type:'heartbeat', member_id:p.memberId, device_id:p.deviceId, battery_pct:battery, permission_state:permission, app_state:appState, ts });
  return j({ ok:true, ts });
}

async function snapshot(env: Env, p: DevicePrincipal): Promise<Response> {
  const rows = await env.DB.prepare(`
    SELECT m.id AS member_id,m.display_name,m.role,
           d.id AS device_id,d.platform,d.display_name AS device_name,d.last_seen_at,d.battery_pct,d.permission_state,d.app_state,
           l.captured_at,l.received_at,l.lat,l.lng,l.accuracy_m,l.speed_mps,l.heading_deg,l.activity
      FROM members m
      LEFT JOIN devices d ON d.member_id=m.id AND d.revoked_at IS NULL
      LEFT JOIN locations l ON l.id=(SELECT l2.id FROM locations l2 WHERE l2.family_id=m.family_id AND l2.member_id=m.id ORDER BY l2.captured_at DESC LIMIT 1)
     WHERE m.family_id=?1
     ORDER BY m.created_at ASC
  `).bind(p.familyId).all<any>();
  return j({ ok:true, server_time:now(), members:rows.results || [] });
}

async function history(request: Request, env: Env, p: DevicePrincipal): Promise<Response> {
  const u = new URL(request.url);
  const memberId = u.searchParams.get('member_id') || p.memberId;
  const member = await env.DB.prepare('SELECT id FROM members WHERE id=?1 AND family_id=?2').bind(memberId,p.familyId).first();
  if (!member) return err('member_not_found',404);
  const from = Number(u.searchParams.get('from') || (now() - 24*60*60*1000));
  const to = Number(u.searchParams.get('to') || now());
  const limit = Math.max(1,Math.min(5000,Number(u.searchParams.get('limit') || 2000)));
  const rows = await env.DB.prepare(`SELECT captured_at,lat,lng,accuracy_m,speed_mps,heading_deg,battery_pct,activity FROM locations
    WHERE family_id=?1 AND member_id=?2 AND captured_at BETWEEN ?3 AND ?4 ORDER BY captured_at ASC LIMIT ?5`)
    .bind(p.familyId,memberId,from,to,limit).all();
  return j({ ok:true, member_id:memberId, from, to, points:rows.results || [] });
}

async function sos(request: Request, env: Env, p: DevicePrincipal): Promise<Response> {
  const latest = await env.DB.prepare(`SELECT captured_at,lat,lng,accuracy_m,speed_mps,battery_pct FROM locations WHERE family_id=?1 AND member_id=?2 ORDER BY captured_at DESC LIMIT 1`)
    .bind(p.familyId,p.memberId).first<any>();
  const id = crypto.randomUUID();
  const ts = now();
  const payload = { latest_location: latest || null };
  await env.DB.prepare(`INSERT INTO events(id,family_id,member_id,device_id,type,severity,payload_json,created_at) VALUES(?1,?2,?3,?4,'sos','critical',?5,?6)`)
    .bind(id,p.familyId,p.memberId,p.deviceId,JSON.stringify(payload),ts).run();
  const event = { type:'sos', event_id:id, member_id:p.memberId, member_name:p.memberName, device_id:p.deviceId, ts, ...payload };
  await publish(env,p.familyId,event);
  return j({ ok:true, event_id:id, ts },201);
}

async function registerPushToken(request: Request, env: Env, p: DevicePrincipal): Promise<Response> {
  const b = await body<any>(request);
  if (!b?.token || typeof b.token !== 'string' || !['fcm', 'apns'].includes(b.platform)) return err('invalid_body');
  const tokenHash = await sha256Hex(b.token);
  const encrypted = await encryptSecret(env.PUSH_TOKEN_ENCRYPTION_KEY, b.token);
  const ts = now();
  await env.DB.batch([
    env.DB.prepare(`UPDATE push_tokens SET revoked_at=?1 WHERE device_id=?2 AND revoked_at IS NULL`).bind(ts, p.deviceId),
    env.DB.prepare(
      `INSERT INTO push_tokens(id,device_id,family_id,platform,token_hash,token_ciphertext,token_iv,created_at) VALUES(?1,?2,?3,?4,?5,?6,?7,?8)`,
    ).bind(crypto.randomUUID(), p.deviceId, p.familyId, b.platform, tokenHash, encrypted.ciphertext, encrypted.iv, ts),
  ]);
  return j({ ok: true }, 201);
}

async function liveTicket(env: Env, p: DevicePrincipal): Promise<Response> {
  const iat = Math.floor(Date.now()/1000);
  const exp = iat + 60;
  const ticket = await signTicket(env.SESSION_SIGNING_KEY,{ sub:p.deviceId, family_id:p.familyId, member_id:p.memberId, iat, exp, nonce:randomToken(12) });
  return j({ ok:true, ticket, expires_at:exp*1000 });
}

async function liveConnect(request: Request, env: Env): Promise<Response> {
  const u = new URL(request.url);
  const ticket = u.searchParams.get('ticket');
  if (!ticket) return err('missing_ticket',401);
  const payload = await verifyTicket(env.SESSION_SIGNING_KEY,ticket);
  if (!payload?.family_id || !payload?.member_id || !payload?.sub) return err('invalid_ticket',401);
  const id = env.FAMILY_LIVE.idFromName(String(payload.family_id));
  const stub = env.FAMILY_LIVE.get(id);
  const headers = new Headers(request.headers);
  headers.set('x-member-id',String(payload.member_id));
  headers.set('x-device-id',String(payload.sub));
  return stub.fetch('https://do.internal/connect',{ headers });
}

async function route(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const path = url.pathname;
  if (path === '/health') return j({ ok:true, service:'savarona-ailem-api', ts:now() });
  if (request.method === 'POST' && path === '/v1/admin/bootstrap') return bootstrap(request,env);
  if (request.method === 'POST' && path === '/v1/join') return joinFamily(request,env);
  if (request.method === 'GET' && path === '/v1/live') return liveConnect(request,env);

  const a = await requireAuth(request,env);
  if (a instanceof Response) return a;
  if (request.method === 'POST' && path === '/v1/invites') return createInvite(request,env,a);
  if (request.method === 'POST' && path === '/v1/location') return postLocation(request,env,a);
  if (request.method === 'POST' && path === '/v1/heartbeat') return heartbeat(request,env,a);
  if (request.method === 'GET' && path === '/v1/family/snapshot') return snapshot(env,a);
  if (request.method === 'GET' && path === '/v1/history') return history(request,env,a);
  if (request.method === 'POST' && path === '/v1/sos') return sos(request,env,a);
  if (request.method === 'POST' && path === '/v1/live-ticket') return liveTicket(env,a);
  if (request.method === 'POST' && path === '/v1/push-token') return registerPushToken(request,env,a);
  if (request.method === 'GET' && path === '/v1/geofences') return listGeofences(env,a);
  if (request.method === 'POST' && path === '/v1/geofences') return createGeofence(request,env,a);
  const geofenceMatch = path.match(/^\/v1\/geofences\/([^/]+)$/);
  if (geofenceMatch) {
    const geofenceId = geofenceMatch[1];
    if (request.method === 'PATCH') return updateGeofence(request,env,a,geofenceId);
    if (request.method === 'DELETE') return deleteGeofence(env,a,geofenceId);
  }
  return err('not_found',404);
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try { return await route(request,env); }
    catch (e) {
      console.error('request_failed', e instanceof Error ? e.message : String(e));
      return err('internal_error',500);
    }
  },
  async scheduled(_controller: ScheduledController, env: Env): Promise<void> {
    const offlineSeconds = Math.max(60, Number(env.OFFLINE_SECONDS || '180'));
    const cutoff = now() - offlineSeconds*1000;
    const rows = await env.DB.prepare(`SELECT d.id AS device_id,d.family_id,d.member_id,m.display_name,d.last_seen_at
      FROM devices d JOIN members m ON m.id=d.member_id
      WHERE d.revoked_at IS NULL AND d.last_seen_at IS NOT NULL AND d.last_seen_at < ?1 AND d.stale_notified_at IS NULL`)
      .bind(cutoff).all<any>();
    for (const r of rows.results || []) {
      const ts = now();
      const claim = await env.DB.prepare(`UPDATE devices SET stale_notified_at=?1,app_state='stale'
        WHERE id=?2 AND stale_notified_at IS NULL AND last_seen_at<?3`)
        .bind(ts, r.device_id, cutoff).run();
      if ((claim.meta?.changes ?? 0) < 1) continue;
      await publish(env,r.family_id,{ type:'device_stale',device_id:r.device_id,member_id:r.member_id,member_name:r.display_name,last_seen_at:r.last_seen_at,ts });
    }
  }
};