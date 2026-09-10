# Claude / Codex Handoff — Savarona Ailem

Bu repoyu production seviyesine tamamla. Mevcut mimari kararları koru; güvenliği zayıflatma.

## Hedef platform

- Flutter stable 3.47+
- Android 12–16+
- iOS güncel desteklenen sürümler
- Cloudflare Workers + D1 + Durable Objects Hibernation WebSocket

## Değiştirme

- Uygulama adı: `Savarona Ailem`
- Backend API contract
- D1 family/device/location ayrımı
- Raw device tokenların DB'de saklanmaması
- Live WebSocket'te short-lived ticket yaklaşımı
- Kullanıcı onayı ve görünür background tracking

## Tamamlanacak işler

1. `flutter create` ile gerçek Android/iOS boilerplate üret.
2. Bu repodaki `mobile/lib` dosyalarını projeye uygula ve derleme hatalarını gider.
3. Android native background tracker:
   - foreground service type `location`
   - `ACCESS_FINE_LOCATION`
   - gerektiğinde `ACCESS_BACKGROUND_LOCATION`
   - sürekli görünür foreground notification
   - adaptive update interval
   - network yoksa bounded local queue
   - network gelince sırayı idempotent şekilde gönder
4. iOS native tracker:
   - `NSLocationWhenInUseUsageDescription`
   - `NSLocationAlwaysAndWhenInUseUsageDescription`
   - `UIBackgroundModes=location`
   - `allowsBackgroundLocationUpdates=true`
   - uygun `CLBackgroundActivitySession` / `CLServiceSession`
   - app relaunch sonrası izin mevcutsa session restore
   - OS davranışını aşmaya çalışma; terminated/force-quit durumlarını doğru raporla
5. Flutter UI:
   - login/bootstrap/join flow
   - family snapshot
   - live WebSocket reconnect/backoff
   - live map
   - member detail
   - route history
   - SOS long-press
   - permission health dashboard
6. Backend:
   - endpoint testleri
   - rate limit hook'ları
   - device sequence/replay protection
   - geofence CRUD + event generation
   - push token registration schema
7. CI:
   - lint/test
   - Worker dry-run
   - Flutter analyze/test
8. README'yi gerçek build/deploy komutlarıyla güncelle.

## Kabul kriterleri

- İki cihaz aynı family'ye katılabiliyor.
- Cihaz A location POST ettiğinde cihaz B live socket'te <2 sn içinde görüyor (normal ağda).
- Son konum D1'e kaydoluyor.
- History endpoint family dışı member id sızıntısı yapmıyor.
- SOS realtime event üretir.
- Device token loglara yazılmaz.
- WebSocket URL'de raw device token yoktur.
- Android background testinde foreground notification görünür.
- iOS background tracking kullanıcıya sistem göstergeleri/izinleriyle şeffaftır.
- Kullanıcı izin kapatırsa sistem bunu engellemeye çalışmaz; uygulama `permission_lost` / stale state üretir.
