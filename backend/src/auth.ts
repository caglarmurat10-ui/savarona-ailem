import type { DevicePrincipal, Env } from './types';
import { sha256Hex } from './crypto';

export function bearer(request: Request): string | null {
  const h = request.headers.get('authorization') || '';
  const m = h.match(/^Bearer\s+(.+)$/i);
  return m?.[1]?.trim() || null;
}

export async function authenticate(request: Request, env: Env): Promise<DevicePrincipal | null> {
  const token = bearer(request);
  if (!token) return null;
  const hash = await sha256Hex(token);
  const row = await env.DB.prepare(`
    SELECT d.id AS device_id, d.family_id, d.member_id,
           m.display_name AS member_name, m.role
      FROM devices d
      JOIN members m ON m.id = d.member_id
     WHERE d.token_hash = ?1 AND d.revoked_at IS NULL
     LIMIT 1
  `).bind(hash).first<any>();
  if (!row) return null;
  return {
    deviceId: row.device_id,
    familyId: row.family_id,
    memberId: row.member_id,
    memberName: row.member_name,
    role: row.role,
  };
}
