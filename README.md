# Savarona Ailem v0.2

Android + iOS için açık rızaya dayalı, gerçek zamanlı aile konum paylaşımı.

## Özellikler

- Canlı aile haritası
- Anlık konum, güncel hız, yön, GPS doğruluğu, pil ve son görülme
- Android foreground location service + reboot restore
- iOS Core Location background session + relaunch restore
- Hareket durumuna göre adaptif GPS profili
- Sınırlı yerel offline kuyruk ve `sequence_no` ile idempotent teslim
- Rota geçmişi
- SOS (2 saniye basılı tutma)
- Geofence CRUD + giriş/çıkış olayları
- Takip/izin sağlık ekranı
- `permission_lost` ve tek-epizot stale alarmı
- Kısa ömürlü imzalı WebSocket ticket + ping/pong watchdog
- Android Keystore / iOS Keychain ile native background token koruması
- Cloudflare Worker + D1 + Durable Objects

> Uygulama işletim sistemi izinlerini aşmaz ve gizli takip yapmaz. Cihaz sahibi konum paylaşımını durdurabilir veya izinleri kapatabilir. Sistem bunu aile ekranında görünür hale getirir; force-stop/telefon kapatma gibi OS kontrollerini bypass etmeye çalışmaz.

## Mimari

```text
Flutter Android / iOS
        |
        | HTTPS: location + heartbeat
        v
Cloudflare Worker ---- D1
        |               |- families / members / devices
        |               |- location history
        |               |- events / geofences
        |               `- encrypted push-token inventory
        |
        `---- Durable Object / WebSocket ---- diğer aile telefonları
```

## Repo

- `backend/`: Worker, D1 migrationları, Durable Object, entegrasyon testleri
- `mobile/lib/`: Flutter UI ve istemci servisleri
- `mobile/native/`: Android/iOS arka plan tracker kaynakları
- `tools/bootstrap_mobile.py`: Flutter platform shell üretimi + native merge
- `docs/CLOUDFLARE_DEPLOY.md`: production kurulum
- `docs/DEVICE_TEST_PLAN.md`: gerçek cihaz kabul testi

## Backend

```bash
cd backend
npm install
npm run typecheck
npm test
npm run check
```

Production için:

```bash
npx wrangler d1 create savarona-ailem
npx wrangler secret put ADMIN_BOOTSTRAP_SECRET
npx wrangler secret put SESSION_SIGNING_KEY
npx wrangler secret put PUSH_TOKEN_ENCRYPTION_KEY
npm run db:remote
npm run deploy
```

D1 `database_id` değeri deploy öncesinde `backend/wrangler.jsonc` içindeki placeholder yerine yazılmalıdır. Ayrıntı: `docs/CLOUDFLARE_DEPLOY.md`.

### Güvenlik / dayanıklılık

- Device bearer token D1'de yalnızca SHA-256 hash olarak tutulur.
- Native background tracker aynı tokenı Android Keystore / iOS Keychain üzerinden kullanır.
- Push registration tokenları D1'de lookup için hash, gerçek gönderim için `PUSH_TOKEN_ENCRYPTION_KEY` ile AES-GCM ciphertext olarak saklanır.
- Location `sequence_no` ilerlemesi ve location insert aynı D1 batch'indedir; başarısız insert sequence'i tek başına tüketmez.
- `(device_id, sequence_no)` için unique index vardır.
- Davet kodu tek kullanımlıdır ve `claim_id` ile yarışa dayanıklı claim edilir.
- Stale alarmı her 2 dakikalık cron'da tekrar spam edilmez; heartbeat/location gelince stale epizodu resetlenir.

## Mobil shell oluşturma

Flutter SDK bulunan makinede repo kökünden:

```bash
python tools/bootstrap_mobile.py
cd mobile
flutter pub get
flutter analyze
flutter test
```

Script temiz bir Flutter Android+iOS shell oluşturur ve `mobile/native/*` kaynaklarını otomatik birleştirir. Elle `MainActivity`, `AppDelegate`, manifest veya Info.plist kopyalamak gerekmez.

Çalıştırma:

```bash
flutter run --dart-define=API_BASE_URL=https://YOUR-WORKER.workers.dev
```

## CI

- `backend.yml`: temiz `npm install` → typecheck → Vitest/D1/DO entegrasyon testleri → Wrangler dry-run.
- `mobile.yml` Android job: shell bootstrap → analyze → unit test → debug APK build → artifact upload.
- `mobile.yml` iOS job: macOS üzerinde shell bootstrap → no-codesign iOS compile.
- Workflow'lar `main` ve `master` branch'lerinde çalışır.

## Bu sürümde (v0.2)

Claude'un `88d2f54` tabanı üzerine şu üretim düzeltmeleri eklendi:

- Atomik location sequence + D1 persist
- Yarışa dayanıklı tek-kullanımlık invite claim
- Tek stale olayı / offline epizodu
- Push token AES-GCM koruması
- Android Keystore ve iOS Keychain native credential storage
- Android/iOS 30 sn heartbeat ve permission-loss raporu
- Android reboot restore (kullanıcı paylaşımı daha önce açtıysa ve izinler uygunsa)
- OS izin durumu uygulamaya dönüldüğünde yeniden senkronizasyon
- WebSocket ping/pong watchdog
- Heartbeat zamanı ile gerçek GPS zamanı ayrımı; eski hız artık “anlık” görünmez
- Flutter UI'dan gerçek native tracking start/stop akışı
- Otomatik Android+iOS shell merge ve CI compile/build

## Release kapısı

CI yeşil olmadan ve `docs/DEVICE_TEST_PLAN.md` Android + iPhone üzerinde geçmeden production release yapılmamalıdır. OS ve ağ, güncelleme aralığını etkileyebilir; “kesin 2 saniye her koşulda” garantisi verilmez.
