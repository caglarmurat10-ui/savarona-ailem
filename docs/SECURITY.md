# Security Model

## Threats

1. Device token çalınması
2. Aile dışı kullanıcının live room'a bağlanması
3. Location spoof/replay
4. Invite code brute force
5. SQL veri sızıntısı
6. Uygulama arka plan izninin kapatılması

## v0.1 önlemleri

- Device tokenlar 256-bit random ve yalnızca ilk oluşturulmada döner.
- D1'de device tokenın SHA-256 hash'i tutulur.
- Tüm family API'leri token üzerinden `family_id` ile scope edilir.
- Live WebSocket için 60 saniyelik HMAC imzalı ticket kullanılır.
- Invite kodu plaintext saklanmaz; SHA-256 hash saklanır ve tek kullanımlıdır.
- Location payload lat/lng/accuracy/speed aralıkları doğrulanır.
- Kullanıcı kontrolünü aşan gizli takip uygulanmaz.

## v0.2 zorunluları

- Cloudflare Rate Limiting / WAF kuralları
- Device attestation: Android Play Integrity + Apple App Attest
- Push: FCM + APNs
- Invite attempt throttling
- Per-device sequence number + replay rejection
- Optional end-to-end encrypted location envelope değerlendirmesi
- GDPR/KVKK retention policy ve kullanıcı veri silme akışı
