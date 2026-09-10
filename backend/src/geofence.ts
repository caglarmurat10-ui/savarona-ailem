import type { DevicePrincipal, Env } from './types';

const jsonHeaders = { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' };
const j = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: jsonHeaders });
const err = (code: string, status = 400, detail?: string) => j({ ok: false, error: code, detail }, status);
const now = () => Date.now();

async function body<T = any>(request: Request): Promise<T | null> {
  try { return await request.json<T>(); } catch { return null; }
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

function isFiniteNum(v: unknown): v is number {
  return typeof v === 'number' && Number.isFinite(v);
}

function validGeofenceInput(b: any): b is { name: string; lat: number; lng: number; radius_m: number } {
  if (!b || typeof b !== 'object') return false;
  if (typeof b.name !== 'string' || !b.name.trim() || b.name.length > 80) return false;
  if (!isFiniteNum(b.lat) || b.lat < -90 || b.lat > 90) return false;
  if (!isFiniteNum(b.lng) || b.lng < -180 || b.lng > 180) return false;
  if (!isFiniteNum(b.radius_m) || b.radius_m < 50 || b.radius_m > 5000) return false;
  return true;
}

function requireOwnerOrAdmin(p: DevicePrincipal): Response | null {
  if (p.role !== 'owner' && p.role !== 'admin') return err('forbidden', 403);
  return null;
}

export async function listGeofences(env: Env, p: DevicePrincipal): Promise<Response> {
  const rows = await env.DB.prepare(
    `SELECT id,name,lat,lng,radius_m,enabled,created_at FROM geofences WHERE family_id=?1 ORDER BY created_at ASC`,
  ).bind(p.familyId).all<any>();
  return j({ ok: true, geofences: rows.results || [] });
}

export async function createGeofence(request: Request, env: Env, p: DevicePrincipal): Promise<Response> {
  const forbidden = requireOwnerOrAdmin(p);
  if (forbidden) return forbidden;
  const b = await body<any>(request);
  if (!validGeofenceInput(b)) return err('invalid_body');
  const id = crypto.randomUUID();
  const ts = now();
  await env.DB.prepare(
    `INSERT INTO geofences(id,family_id,name,lat,lng,radius_m,enabled,created_at) VALUES(?1,?2,?3,?4,?5,?6,1,?7)`,
  ).bind(id, p.familyId, b.name.trim().slice(0, 80), b.lat, b.lng, b.radius_m, ts).run();
  return j({ ok: true, geofence_id: id }, 201);
}

export async function updateGeofence(request: Request, env: Env, p: DevicePrincipal, geofenceId: string): Promise<Response> {
  const forbidden = requireOwnerOrAdmin(p);
  if (forbidden) return forbidden;
  const existing = await env.DB.prepare(`SELECT id FROM geofences WHERE id=?1 AND family_id=?2`).bind(geofenceId, p.familyId).first();
  if (!existing) return err('geofence_not_found', 404);
  const b = await body<any>(request) || {};

  const sets: string[] = [];
  const values: unknown[] = [];
  let n = 1;
  if (b.name !== undefined) {
    if (typeof b.name !== 'string' || !b.name.trim() || b.name.length > 80) return err('invalid_body');
    sets.push(`name=?${n++}`); values.push(b.name.trim().slice(0, 80));
  }
  if (b.lat !== undefined || b.lng !== undefined || b.radius_m !== undefined) {
    const current = await env.DB.prepare(`SELECT lat,lng,radius_m FROM geofences WHERE id=?1`).bind(geofenceId).first<any>();
    const lat = b.lat !== undefined ? b.lat : current.lat;
    const lng = b.lng !== undefined ? b.lng : current.lng;
    const radius = b.radius_m !== undefined ? b.radius_m : current.radius_m;
    if (!isFiniteNum(lat) || lat < -90 || lat > 90) return err('invalid_body');
    if (!isFiniteNum(lng) || lng < -180 || lng > 180) return err('invalid_body');
    if (!isFiniteNum(radius) || radius < 50 || radius > 5000) return err('invalid_body');
    sets.push(`lat=?${n++}`); values.push(lat);
    sets.push(`lng=?${n++}`); values.push(lng);
    sets.push(`radius_m=?${n++}`); values.push(radius);
  }
  if (b.enabled !== undefined) {
    sets.push(`enabled=?${n++}`); values.push(b.enabled ? 1 : 0);
  }
  if (sets.length === 0) return err('invalid_body');

  values.push(geofenceId, p.familyId);
  await env.DB.prepare(`UPDATE geofences SET ${sets.join(',')} WHERE id=?${n++} AND family_id=?${n++}`).bind(...values).run();
  return j({ ok: true });
}

export async function deleteGeofence(env: Env, p: DevicePrincipal, geofenceId: string): Promise<Response> {
  const forbidden = requireOwnerOrAdmin(p);
  if (forbidden) return forbidden;
  const result = await env.DB.prepare(`DELETE FROM geofences WHERE id=?1 AND family_id=?2`).bind(geofenceId, p.familyId).run();
  if ((result.meta?.changes ?? 0) < 1) return err('geofence_not_found', 404);
  return j({ ok: true });
}

function haversineMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6_371_000;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

export async function evaluateGeofences(
  env: Env,
  familyId: string,
  memberId: string,
  memberName: string,
  lat: number,
  lng: number,
): Promise<void> {
  const fences = await env.DB.prepare(
    `SELECT id,name,lat,lng,radius_m FROM geofences WHERE family_id=?1 AND enabled=1`,
  ).bind(familyId).all<any>();
  const list = fences.results || [];
  if (list.length === 0) return;

  const states = await env.DB.prepare(
    `SELECT geofence_id,inside FROM geofence_state WHERE member_id=?1`,
  ).bind(memberId).all<any>();
  const stateByFence = new Map<string, boolean>();
  for (const row of states.results || []) stateByFence.set(row.geofence_id, row.inside === 1);

  const ts = now();
  for (const fence of list) {
    const distance = haversineMeters(lat, lng, fence.lat, fence.lng);
    const nowInside = distance <= fence.radius_m;
    const wasInside = stateByFence.get(fence.id) ?? false;
    if (nowInside === wasInside) continue;

    const type = nowInside ? 'geofence_enter' : 'geofence_exit';
    const eventId = crypto.randomUUID();
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO geofence_state(geofence_id,member_id,inside,updated_at) VALUES(?1,?2,?3,?4)
         ON CONFLICT(geofence_id,member_id) DO UPDATE SET inside=excluded.inside, updated_at=excluded.updated_at`,
      ).bind(fence.id, memberId, nowInside ? 1 : 0, ts),
      env.DB.prepare(
        `INSERT INTO events(id,family_id,member_id,type,severity,payload_json,created_at) VALUES(?1,?2,?3,?4,'info',?5,?6)`,
      ).bind(eventId, familyId, memberId, type, JSON.stringify({ geofence_id: fence.id, geofence_name: fence.name, lat, lng }), ts),
    ]);
    await publish(env, familyId, {
      type,
      event_id: eventId,
      member_id: memberId,
      member_name: memberName,
      geofence_id: fence.id,
      geofence_name: fence.name,
      ts,
    });
  }
}
