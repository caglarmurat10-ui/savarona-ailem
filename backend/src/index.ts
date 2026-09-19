import { authenticate } from './auth';
import { createFamily, deleteAccount } from './accounts';
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

const htmlHeaders = { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'public, max-age=3600' };
function publicPage(title: string, body: string): Response {
  return new Response(`<!doctype html><html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title><style>body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;max-width:820px;margin:40px auto;padding:0 20px;line-height:1.6;color:#17202a}h1,h2{line-height:1.25}small{color:#5d6d7e}a{color:#0b63ce}</style></head><body>${body}</body></html>`, { headers: htmlHeaders });
}
function privacyPage(): Response { return publicPage('Savarona Ailem - Gizlilik Politikası', `<h1>Savarona Ailem Gizlilik Politikası</h1><small>Son güncelleme: 16 Eylül 2026</small><p>Savarona Ailem, aile üyelerinin açık rızaya dayalı konum paylaşımı için tasarlanmıştır. Uygulama gizli takip yapmaz; konum paylaşımı cihaz sahibinin işletim sistemi izni ve uygulama içindeki tercihi ile çalışır.</p><h2>Toplanan veriler</h2><p>Uygulama; görünen ad, hassas konum ve konumla ilişkili zaman/doğruluk/hız/yön bilgileri, cihaz ve uygulama tanımlayıcıları, pil yüzdesi, izin/uygulama durumu, aile davetleri, geofence adları ve olayları ile SOS olaylarını işleyebilir. Bildirim için gerekli push tokenları güvenli biçimde saklanır.</p><h2>Kullanım amacı</h2><p>Veriler yalnızca aile içi canlı konum paylaşımı, konum geçmişi, geofence, SOS, bağlantı/takip sağlık durumu ve bildirim gibi temel uygulama işlevlerini sağlamak için kullanılır. Reklam hedefleme veya üçüncü taraflar arası takip yapılmaz ve kişisel veriler satılmaz.</p><h2>Paylaşım ve güvenlik</h2><p>Konum ve ilgili aile verileri yalnızca aynı aile grubundaki yetkili cihazlara sunulur. Hizmet Cloudflare altyapısı üzerinde çalışır. Cihaz erişim anahtarları güvenli depolamada tutulur; sunucuda gerekli kimlik doğrulama değerleri hash/şifreleme ile korunur.</p><h2>Kontrol ve silme</h2><p>Kullanıcı konum iznini veya paylaşımı cihazından durdurabilir. Hesabınızı uygulamanın ana ekranındaki Hesabım > Hesabımı sil menüsünden kalıcı olarak silebilirsiniz. Bu işlem cihaz erişimlerinizi, konum geçmişinizi ve size ait olayları siler. Diğer aile üyelerinin verileri korunur; son üye ayrıldığında aile grubu da silinir. Ek veri erişimi veya destek talebi için <a href="/support">Destek</a> sayfasını kullanın.</p><p>Bu politika uygulamanın işlevleri değiştikçe güncellenebilir.</p>`); }
function supportPage(): Response { return publicPage('Savarona Ailem - Destek', `<h1>Savarona Ailem Destek</h1><p>Savarona Ailem; aile içi canlı konum, konum geçmişi, geofence ve SOS özellikleri sunar.</p><h2>Kurulum</h2><p>Başlangıç ekranından Yeni aile oluştur ile kendi özel grubunuzu oluşturun veya Davet ile katıl ile mevcut gruba katılın. Yönetici anahtarı veya parola gerekmez. Oturum bu cihazda saklanır. Uygulamayı silmek hesabınızı silmez.</p><p>Konum paylaşımının çalışması için iPhone Ayarlar &gt; Gizlilik ve Güvenlik &gt; Konum Servisleri bölümünde Savarona Ailem için gerekli konum iznini verin. Arka planda canlı takip için uygulamanın istediği "Her Zaman" konum iznini onaylayın.</p><h2>Sorun giderme</h2><p>Uygulamada bir üye gecikmeli veya çevrimdışı görünüyorsa internet bağlantısını, konum iznini ve uygulamanın arka planda çalışmasına izin verildiğini kontrol edin.</p><h2>Gizlilik ve veri talepleri</h2><p>Gizlilik ayrıntıları için <a href="/privacy">Gizlilik Politikası</a> sayfasına bakın. Destek veya veri silme talebi için <a href="mailto:caglarmurat10@gmail.com">caglarmurat10@gmail.com</a> adresinden iletişime geçebilirsiniz.</p>`); }
function installPage(): Response {
  const ailemManifest = 'https://github.com/caglarmurat10-ui/ailem/releases/latest/download/manifest.plist';
  const villaManifest = 'https://github.com/caglarmurat10-ui/villa/releases/latest/download/manifest.plist';
  const ailemInstall = `itms-services://?action=download-manifest&url=${encodeURIComponent(ailemManifest)}`;
  const villaInstall = `itms-services://?action=download-manifest&url=${encodeURIComponent(villaManifest)}`;
  return publicPage('Savarona - Özel iPhone Kurulumu', `<h1>Savarona özel iPhone kurulumu</h1><p>Bu paketler App Store dışı Ad Hoc dağıtımdır ve yalnız Apple Developer hesabımıza kayıtlı iPhone/iPad cihazlarına kurulabilir.</p><p><a style="display:block;padding:16px 18px;margin:16px 0;background:#0f766e;color:white;text-decoration:none;border-radius:14px;font-weight:700;text-align:center" href="${ailemInstall}">Savarona Ailem'i Kur</a><a style="display:block;padding:16px 18px;margin:16px 0;background:#1d4ed8;color:white;text-decoration:none;border-radius:14px;font-weight:700;text-align:center" href="${villaInstall}">Villa Yönetim'i Kur</a></p><p><strong>Not:</strong> Bu sayfayı iPhone/iPad üzerinde Safari ile açın. Yeni cihazlarda önce cihazın UDID'si Apple Developer hesabımıza kaydedilmelidir.</p>`);
}



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
    // Kurtarma YALNIZ bootstrap ile kurulan aileye uygulanir. Onceden "global olarak en eski
    // owner" seciliyordu; self-service aile olusturma (POST /v1/families) eklendikten sonra bu,
    // baska bir kullanicinin ailesini secip o kullanicinin cihazlarini iptal edebilir ve admin'e
    // yabanci bir aileye erisim verebilirdi. Bootstrap uyesi app_meta'da sabitlenir.
    const pinned = await env.DB.prepare("SELECT value FROM app_meta WHERE key='bootstrap_member_id'").first<any>();
    const owner = pinned?.value
      ? await env.DB.prepare(`SELECT id AS member_id,family_id FROM members WHERE id=?1`).bind(pinned.value).first<any>()
      // Bu anahtar yazilmadan once bootstrap edilmis kurulumlar icin geriye donuk uyum: o
      // donemde self-service aile yoktu, dolayisiyla en eski owner bootstrap sahibidir.
      : await env.DB.prepare(`SELECT id AS member_id,family_id FROM members WHERE role='owner' ORDER BY created_at ASC LIMIT 1`).first<any>();
    if (!owner?.member_id || !owner?.family_id) return err('owner_not_found', 409);
    // Bir kez cozulduginde sabitle - sonraki kurtarmalar artik siralamaya bagli kalmaz.
    if (!pinned?.value) {
      await env.DB.prepare("INSERT OR REPLACE INTO app_meta(key,value,updated_at) VALUES('bootstrap_member_id',?1,?2)")
        .bind(owner.member_id, now()).run();
    }

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
    // Kurtarmanin hangi aileye ait oldugunu sabitler (bkz. yukaridaki kurtarma dali).
    env.DB.prepare("INSERT OR REPLACE INTO app_meta(key,value,updated_at) VALUES('bootstrap_member_id',?1,?2)").bind(memberId, ts),
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

async function joinReusableReviewDemo(env: Env, b: any, familyId: string): Promise<Response> {
  const family = await env.DB.prepare('SELECT id FROM families WHERE id=?1').bind(familyId).first<any>();
  if (!family?.id) return err('review_demo_unavailable', 503);
  const memberId = crypto.randomUUID();
  const deviceId = crypto.randomUUID();
  const token = randomToken(32);
  const tokenHash = await sha256Hex(token);
  const ts = now();
  const platform = ['android','ios','other'].includes(b.platform) ? b.platform : 'other';
  await env.DB.batch([
    env.DB.prepare("INSERT INTO members(id,family_id,display_name,role,created_at) VALUES(?1,?2,?3,'admin',?4)")
      .bind(memberId, familyId, String(b.member_name).slice(0,80), ts),
    env.DB.prepare(`INSERT INTO devices(id,family_id,member_id,display_name,platform,token_hash,created_at)
                    VALUES(?1,?2,?3,?4,?5,?6,?7)`)
      .bind(deviceId, familyId, memberId, String(b.device_name).slice(0,80), platform, tokenHash, ts),
  ]);
  await publish(env, familyId, { type: 'member_joined', member_id: memberId, display_name: String(b.member_name).slice(0,80), ts });
  return j({ ok: true, family_id: familyId, member_id: memberId, device_id: deviceId, device_token: token, app_review_demo: true }, 201);
}

async function joinFamily(request: Request, env: Env): Promise<Response> {
  if (await rateLimited(env, 'RATE_LIMIT_JOIN', clientIp(request))) return err('rate_limited', 429);
  const b = await body<any>(request);
  if (!b?.invite_code || !b?.member_name || !b?.device_name) return err('invalid_body');
  const codeHash = await sha256Hex(String(b.invite_code).trim().toUpperCase());
  const reviewCode = await env.DB.prepare("SELECT value FROM app_meta WHERE key='app_review_code_hash'").first<any>();
  if (reviewCode?.value === codeHash) {
    const reviewFamily = await env.DB.prepare("SELECT value FROM app_meta WHERE key='app_review_family_id'").first<any>();
    if (!reviewFamily?.value) return err('review_demo_unavailable', 503);
    return joinReusableReviewDemo(env, b, String(reviewFamily.value));
  }
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

function currentAccount(p: DevicePrincipal): Response {
  return j({ ok: true, member_id: p.memberId, family_id: p.familyId, role: p.role });
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
  if (path === '/privacy') return privacyPage();
  if (path === '/support') return supportPage();
  if (path === '/install') return installPage();
  if (path === '/health') return j({ ok:true, service:'savarona-ailem-api', ts:now() });
  if (request.method === 'POST' && path === '/v1/admin/bootstrap') return bootstrap(request,env);
  if (request.method === 'POST' && path === '/v1/join') return joinFamily(request,env);
  if (request.method === 'POST' && path === '/v1/families') return createFamily(request,env);
  if (request.method === 'GET' && path === '/v1/live') return liveConnect(request,env);

  const a = await requireAuth(request,env);
  if (a instanceof Response) return a;
  if (request.method === 'GET' && path === '/v1/me') return currentAccount(a);
  if (request.method === 'DELETE' && path === '/v1/account') return deleteAccount(request,env,a);
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
