import { randomToken, sha256Hex } from './crypto';
import { clientIp } from './rate_limit';
import type { DevicePrincipal, Env } from './types';

const reply = (value: unknown, status = 200) => Response.json(value, { status, headers: { 'cache-control': 'no-store' } });

export async function createFamily(request: Request, env: Env): Promise<Response> {
  // Public enrollment must fail closed if its abuse protection is unavailable.
  if (!env.RATE_LIMIT_BOOTSTRAP) return reply({ error: 'temporarily_unavailable' }, 503);
  try {
    if (!(await env.RATE_LIMIT_BOOTSTRAP.limit({ key: `signup:${clientIp(request)}` })).success) {
      return reply({ error: 'rate_limited' }, 429);
    }
  } catch { return reply({ error: 'temporarily_unavailable' }, 503); }
  const b = await request.json<Record<string, unknown>>().catch(() => null);
  const names = [b?.family_name, b?.owner_name, b?.device_name];
  if (names.some(v => typeof v !== 'string' || !v.trim() || v.trim().length > 80)) {
    return reply({ error: 'invalid_body' }, 400);
  }
  const [familyName, ownerName, deviceName] = names.map(v => String(v).trim());
  const familyId = crypto.randomUUID(), memberId = crypto.randomUUID(), deviceId = crypto.randomUUID();
  const token = randomToken(32), hash = await sha256Hex(token), ts = Date.now();
  const platform = b?.platform === 'ios' || b?.platform === 'android' ? b.platform : 'other';
  await env.DB.batch([
    env.DB.prepare('INSERT INTO families(id,name,created_at) VALUES(?1,?2,?3)').bind(familyId, familyName, ts),
    env.DB.prepare("INSERT INTO members(id,family_id,display_name,role,created_at) VALUES(?1,?2,?3,'owner',?4)").bind(memberId, familyId, ownerName, ts),
    env.DB.prepare('INSERT INTO devices(id,family_id,member_id,display_name,platform,token_hash,created_at) VALUES(?1,?2,?3,?4,?5,?6,?7)').bind(deviceId, familyId, memberId, deviceName, platform, hash, ts),
  ]);
  return reply({ ok: true, family_id: familyId, member_id: memberId, device_id: deviceId, device_token: token }, 201);
}

export async function deleteAccount(request: Request, env: Env, p: DevicePrincipal): Promise<Response> {
  const b = await request.json<{ confirmation?: string }>().catch(() => null);
  if (b?.confirmation !== 'DELETE_MY_ACCOUNT') return reply({ error: 'confirmation_required' }, 400);
  // Never accept a member/family ID from the client. Delete only the authenticated member.
  await env.DB.batch([
    env.DB.prepare('DELETE FROM events WHERE family_id=?1 AND (member_id=?2 OR device_id IN (SELECT id FROM devices WHERE member_id=?2))').bind(p.familyId, p.memberId),
    env.DB.prepare('DELETE FROM invites WHERE family_id=?1 AND created_by_member_id=?2').bind(p.familyId, p.memberId),
    // A departing owner leaves the other members and their data intact.
    env.DB.prepare(`UPDATE members SET role='owner' WHERE id=(
      SELECT id FROM members WHERE family_id=?1 AND id<>?2
      ORDER BY CASE role WHEN 'admin' THEN 0 ELSE 1 END,created_at,id LIMIT 1
    ) AND EXISTS(SELECT 1 FROM members WHERE id=?2 AND role='owner')`).bind(p.familyId, p.memberId),
    // Foreign keys cascade to devices, locations, push tokens and geofence presence.
    env.DB.prepare('DELETE FROM members WHERE id=?1 AND family_id=?2').bind(p.memberId, p.familyId),
    env.DB.prepare('DELETE FROM families WHERE id=?1 AND NOT EXISTS(SELECT 1 FROM members WHERE family_id=?1)').bind(p.familyId),
  ]);
  const live = env.FAMILY_LIVE.get(env.FAMILY_LIVE.idFromName(p.familyId));
  await live.fetch('https://do.internal/account-deleted', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ member_id: p.memberId }),
  });
  return reply({ ok: true });
}
