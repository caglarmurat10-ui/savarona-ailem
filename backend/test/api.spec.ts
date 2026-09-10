import { SELF, env } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { decryptSecret } from '../src/crypto';

const BASE = 'https://example.com';
const BOOTSTRAP_SECRET = 'test-bootstrap-secret';

function authHeaders(token: string) {
  return { authorization: `Bearer ${token}`, 'content-type': 'application/json' };
}

let owner: { family_id: string; member_id: string; device_id: string; device_token: string };
let child: { family_id: string; member_id: string; device_id: string; device_token: string };
let ownerSeq = 0;
const nextOwnerSeq = () => ++ownerSeq;

describe('family journey', () => {
  beforeAll(async () => {
    const res = await SELF.fetch(`${BASE}/v1/admin/bootstrap`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-bootstrap-secret': BOOTSTRAP_SECRET },
      body: JSON.stringify({ family_name: 'Test Ailesi', owner_name: 'Owner', device_name: 'Owner Phone', platform: 'android' }),
    });
    expect(res.status).toBe(201);
    owner = await res.json();
  });

  it('GET /health responds ok', async () => {
    const res = await SELF.fetch(`${BASE}/health`);
    expect(res.status).toBe(200);
    expect((await res.json<any>()).ok).toBe(true);
  });

  it('rejects bootstrap without the secret', async () => {
    const res = await SELF.fetch(`${BASE}/v1/admin/bootstrap`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ family_name: 'x', owner_name: 'y', device_name: 'z' }),
    });
    expect(res.status).toBe(403);
  });

  it('refuses a second bootstrap once one has completed', async () => {
    const res = await SELF.fetch(`${BASE}/v1/admin/bootstrap`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-bootstrap-secret': BOOTSTRAP_SECRET },
      body: JSON.stringify({ family_name: 'Another', owner_name: 'B', device_name: 'C' }),
    });
    expect(res.status).toBe(409);
  });

  it('member endpoints require a bearer token', async () => {
    const res = await SELF.fetch(`${BASE}/v1/family/snapshot`);
    expect(res.status).toBe(401);
  });

  it('lets a second device join with a valid invite, then rejects reuse', async () => {
    const inviteRes = await SELF.fetch(`${BASE}/v1/invites`, { method: 'POST', headers: authHeaders(owner.device_token) });
    expect(inviteRes.status).toBe(201);
    const { invite_code } = await inviteRes.json<any>();

    const joinRes = await SELF.fetch(`${BASE}/v1/join`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ invite_code, member_name: 'Child', device_name: 'Child Phone', platform: 'ios' }),
    });
    expect(joinRes.status).toBe(201);
    child = await joinRes.json();
    expect(child.family_id).toBe(owner.family_id);
    expect(child.member_id).not.toBe(owner.member_id);

    const reuse = await SELF.fetch(`${BASE}/v1/join`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ invite_code, member_name: 'X', device_name: 'Y', platform: 'ios' }),
    });
    expect(reuse.status).toBe(400);
  });

  it('accepts an increasing location sequence and rejects a replayed one', async () => {
    const payload = (sequence_no: number) => JSON.stringify({
      captured_at: Date.now(), lat: 36.2, lng: 29.6, accuracy_m: 5, speed_mps: 3, sequence_no,
    });
    const seq1 = nextOwnerSeq();
    const first = await SELF.fetch(`${BASE}/v1/location`, { method: 'POST', headers: authHeaders(owner.device_token), body: payload(seq1) });
    expect(first.status).toBe(200);

    const replay = await SELF.fetch(`${BASE}/v1/location`, { method: 'POST', headers: authHeaders(owner.device_token), body: payload(seq1) });
    expect(replay.status).toBe(409);
    expect((await replay.json<any>()).error).toBe('replay_rejected');
    const duplicateCount = await env.DB.prepare('SELECT COUNT(*) AS n FROM locations WHERE device_id=?1 AND sequence_no=?2').bind(owner.device_id, seq1).first<any>();
    expect(Number(duplicateCount.n)).toBe(1);

    const older = await SELF.fetch(`${BASE}/v1/location`, { method: 'POST', headers: authHeaders(owner.device_token), body: payload(0) });
    expect(older.status).toBe(409);

    const seq2 = nextOwnerSeq();
    const next = await SELF.fetch(`${BASE}/v1/location`, { method: 'POST', headers: authHeaders(owner.device_token), body: payload(seq2) });
    expect(next.status).toBe(200);
  });

  it('rejects a location payload with no sequence number, on the child device', async () => {
    const res = await SELF.fetch(`${BASE}/v1/location`, {
      method: 'POST',
      headers: authHeaders(child.device_token),
      body: JSON.stringify({ captured_at: Date.now(), lat: 1, lng: 1 }),
    });
    expect(res.status).toBe(409);
    expect((await res.json<any>()).error).toBe('sequence_required');
  });

  it('reflects the last known location in the snapshot and history', async () => {
    const snap = await SELF.fetch(`${BASE}/v1/family/snapshot`, { headers: authHeaders(owner.device_token) });
    const snapData = await snap.json<any>();
    const ownerRow = snapData.members.find((m: any) => m.member_id === owner.member_id);
    expect(ownerRow.lat).toBeCloseTo(36.2);

    const hist = await SELF.fetch(`${BASE}/v1/history?member_id=${owner.member_id}`, { headers: authHeaders(owner.device_token) });
    expect(hist.status).toBe(200);
    expect((await hist.json<any>()).points.length).toBeGreaterThanOrEqual(2);

    const missing = await SELF.fetch(`${BASE}/v1/history?member_id=does-not-exist`, { headers: authHeaders(owner.device_token) });
    expect(missing.status).toBe(404);
  });

  it('creates a critical SOS event with the latest known location', async () => {
    const res = await SELF.fetch(`${BASE}/v1/sos`, { method: 'POST', headers: authHeaders(owner.device_token) });
    expect(res.status).toBe(201);
    const { event_id } = await res.json<any>();
    const row = await env.DB.prepare('SELECT type,severity FROM events WHERE id=?1').bind(event_id).first<any>();
    expect(row.type).toBe('sos');
    expect(row.severity).toBe('critical');
  });

  it('stores push tokens hashed for lookup and encrypted for delivery', async () => {
    const rawToken = 'super-secret-fcm-token';
    const res = await SELF.fetch(`${BASE}/v1/push-token`, {
      method: 'POST', headers: authHeaders(owner.device_token),
      body: JSON.stringify({ platform: 'fcm', token: rawToken }),
    });
    expect(res.status).toBe(201);
    const row = await env.DB.prepare('SELECT token_hash,token_ciphertext,token_iv FROM push_tokens WHERE device_id=?1 AND revoked_at IS NULL')
      .bind(owner.device_id).first<any>();
    expect(row.token_hash).not.toBe(rawToken);
    expect(row.token_hash).toMatch(/^[0-9a-f]{64}$/);
    expect(row.token_ciphertext).not.toContain(rawToken);
    const clear = await decryptSecret('test-push-token-encryption-key-0123456789', row.token_ciphertext, row.token_iv);
    expect(clear).toBe(rawToken);
  });

  it('emits a geofence_enter event only on the transition into the fence', async () => {
    const createRes = await SELF.fetch(`${BASE}/v1/geofences`, {
      method: 'POST', headers: authHeaders(owner.device_token),
      body: JSON.stringify({ name: 'Ev', lat: 50, lng: 50, radius_m: 200 }),
    });
    expect(createRes.status).toBe(201);
    const { geofence_id } = await createRes.json<any>();

    await SELF.fetch(`${BASE}/v1/location`, {
      method: 'POST', headers: authHeaders(owner.device_token),
      body: JSON.stringify({ captured_at: Date.now(), lat: 40, lng: 40, sequence_no: nextOwnerSeq() }),
    });
    await SELF.fetch(`${BASE}/v1/location`, {
      method: 'POST', headers: authHeaders(owner.device_token),
      body: JSON.stringify({ captured_at: Date.now(), lat: 50.0001, lng: 50.0001, sequence_no: nextOwnerSeq() }),
    });
    await SELF.fetch(`${BASE}/v1/location`, {
      method: 'POST', headers: authHeaders(owner.device_token),
      body: JSON.stringify({ captured_at: Date.now(), lat: 50.0002, lng: 50.0002, sequence_no: nextOwnerSeq() }),
    });

    const events = await env.DB.prepare("SELECT type FROM events WHERE type='geofence_enter'").all<any>();
    expect(events.results?.length).toBe(1);

    const list = await SELF.fetch(`${BASE}/v1/geofences`, { headers: authHeaders(owner.device_token) });
    expect((await list.json<any>()).geofences.length).toBe(1);

    const del = await SELF.fetch(`${BASE}/v1/geofences/${geofence_id}`, { method: 'DELETE', headers: authHeaders(owner.device_token) });
    expect(del.status).toBe(200);
  });

  it('issues a short-lived signed live ticket that never contains the raw device token', async () => {
    const res = await SELF.fetch(`${BASE}/v1/live-ticket`, { method: 'POST', headers: authHeaders(owner.device_token) });
    expect(res.status).toBe(200);
    const { ticket, expires_at } = await res.json<any>();
    expect(ticket.split('.').length).toBe(3);
    expect(expires_at).toBeGreaterThan(Date.now());
    expect(ticket).not.toContain(owner.device_token);

    const noTicket = await SELF.fetch(`${BASE}/v1/live`, { headers: { Upgrade: 'websocket' } });
    expect(noTicket.status).toBe(401);
  });

  it('eventually rejects a rapid burst of join attempts from the same caller', async () => {
    const attempts = Array.from({ length: 25 }, (_, i) =>
      SELF.fetch(`${BASE}/v1/join`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ invite_code: `BADCODE${i}`, member_name: 'X', device_name: 'Y', platform: 'ios' }),
      }),
    );
    const results = await Promise.all(attempts);
    const statuses = results.map((r) => r.status);
    expect(statuses).toContain(400);
    expect(statuses).toContain(429);
  });
});
