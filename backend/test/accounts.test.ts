import { SELF, env } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';

const base = 'https://example.com';
type Account = { family_id: string; member_id: string; device_id: string; device_token: string };
const headers = (a: Account) => ({ authorization: `Bearer ${a.device_token}`, 'content-type': 'application/json' });
async function create(name: string): Promise<Account> {
  const r = await SELF.fetch(`${base}/v1/families`, { method: 'POST',
    headers: { 'content-type': 'application/json', 'cf-connecting-ip': '192.0.2.42' },
    body: JSON.stringify({ family_name: name, owner_name: 'Test Owner', device_name: 'Test Phone', platform: 'ios' }) });
  expect(r.status).toBe(201);
  return r.json<Account>();
}
const remove = (a: Account, extra = {}) => SELF.fetch(`${base}/v1/account`, {
  method: 'DELETE', headers: headers(a), body: JSON.stringify({ confirmation: 'DELETE_MY_ACCOUNT', ...extra }) });

describe('public registration and account deletion', () => {
  it('isolates families, requires confirmation, deletes only the caller and invalidates access', async () => {
    const a = await create('First test family');
    const b = await create('Second test family');
    expect(a.family_id).not.toBe(b.family_id);
    const snapshot = await SELF.fetch(`${base}/v1/family/snapshot`, { headers: headers(a) });
    const data = await snapshot.json<{ members: { member_id: string }[] }>();
    expect(data.members.map(m => m.member_id)).toEqual([a.member_id]);
    const row = await env.DB.prepare('SELECT token_hash FROM devices WHERE id=?1').bind(a.device_id).first<{token_hash: string}>();
    expect(row?.token_hash).not.toBe(a.device_token);
    expect((await SELF.fetch(`${base}/v1/account`, { method: 'DELETE' })).status).toBe(401);
    expect((await SELF.fetch(`${base}/v1/account`, { method: 'DELETE', headers: headers(a), body: '{}' })).status).toBe(400);
    expect((await remove(a, { member_id: b.member_id, family_id: b.family_id })).status).toBe(200);
    expect(await env.DB.prepare('SELECT id FROM families WHERE id=?1').bind(a.family_id).first()).toBeNull();
    expect((await SELF.fetch(`${base}/v1/family/snapshot`, { headers: headers(a) })).status).toBe(401);
    expect((await SELF.fetch(`${base}/v1/family/snapshot`, { headers: headers(b) })).status).toBe(200);
    expect((await remove(b)).status).toBe(200);
  });

  it('preserves remaining members and promotes a successor when the owner deletes their account', async () => {
    const a = await create('Owner deletion test');
    const invitation = await SELF.fetch(`${base}/v1/invites`, { method: 'POST', headers: headers(a) });
    const { invite_code } = await invitation.json<{invite_code: string}>();
    const joined = await SELF.fetch(`${base}/v1/join`, { method: 'POST',
      headers: { 'content-type': 'application/json', 'cf-connecting-ip': '192.0.2.43' },
      body: JSON.stringify({ invite_code, member_name: 'Remaining member', device_name: 'Second phone', platform: 'ios' }) });
    expect(joined.status).toBe(201);
    const b = await joined.json<Account>();
    const location = await SELF.fetch(`${base}/v1/location`, { method: 'POST', headers: headers(a),
      body: JSON.stringify({ captured_at: Date.now(), lat: 0, lng: 0, sequence_no: 1 }) });
    expect(location.status).toBe(200);
    expect((await SELF.fetch(`${base}/v1/sos`, { method: 'POST', headers: headers(a) })).status).toBe(201);
    const ticketResponse = await SELF.fetch(`${base}/v1/live-ticket`, { method: 'POST', headers: headers(a) });
    const { ticket } = await ticketResponse.json<{ticket: string}>();
    expect((await remove(a)).status).toBe(200);
    for (const table of ['devices', 'locations', 'events', 'geofence_state']) {
      expect(await env.DB.prepare(`SELECT member_id FROM ${table} WHERE member_id=?1`).bind(a.member_id).first()).toBeNull();
    }
    expect(await env.DB.prepare('SELECT id FROM invites WHERE created_by_member_id=?1').bind(a.member_id).first()).toBeNull();
    const survivor = await env.DB.prepare('SELECT role FROM members WHERE id=?1').bind(b.member_id).first<{role: string}>();
    expect(survivor?.role).toBe('owner');
    expect((await SELF.fetch(`${base}/v1/live?ticket=${encodeURIComponent(ticket)}`, { headers: { Upgrade: 'websocket' } })).status).toBe(401);
    expect((await SELF.fetch(`${base}/v1/invites`, { method: 'POST', headers: headers(b) })).status).toBe(201);
    expect((await remove(b)).status).toBe(200);
  });

  it('rejects malformed registration and limits enrollment bursts', async () => {
    const statuses: number[] = [];
    for (let i = 0; i < 7; i++) {
      const r = await SELF.fetch(`${base}/v1/families`, { method: 'POST',
        headers: { 'content-type': 'application/json', 'cf-connecting-ip': '192.0.2.44' }, body: '{}' });
      statuses.push(r.status);
    }
    expect(statuses).toContain(400);
    expect(statuses).toContain(429);
  });
});
