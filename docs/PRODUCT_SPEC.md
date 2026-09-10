# Savarona Ailem — Product Spec v0.1

## Ana ekran

Her aile üyesi için:
- ad/avatar
- canlı konum
- hız (km/sa)
- yön
- pil
- son güncelleme
- hareket durumu
- bağlantı durumu: canlı / gecikmeli / çevrimdışı / izin sorunu

## Canlı harita

- Tüm üyeler aynı haritada
- Tek üyeye odaklanma
- Harita marker'ında hız rozeti
- Son rota çizgisi
- Son konum yaşı için renk yerine metinsel durum da bulunmalı

## Takip davranışı

Önerilen adaptif profil:
- Araç: hedef 3–5 saniye, distance filter 10–20 m
- Yürüme: 8–15 saniye, distance filter 10 m
- Sabit: 30–120 saniye heartbeat / significant change

Bu değerler işletim sisteminin enerji ve background politikalarına bağlıdır; iOS'ta kesin aralık garanti edilmez.

## Takip kesilmesi

Cihaz 90 saniye boyunca heartbeat/location yollamazsa UI `GECİKMELİ`, 180 saniye sonra `ÇEVRİMDIŞI` gösterir. Bu eşikler sunucu ayarı olmalıdır.

## SOS

- Büyük kırmızı buton
- Yanlış basmayı azaltmak için 2 saniye basılı tut
- Son konum, doğruluk, hız, pil ve timestamp ile event üret
- Aktif aile cihazlarına realtime yayınla
- Push entegrasyonu v0.2

## Geofence

- Ev, iş, okul, villa gibi bölgeler
- Circle radius 50–5000 m
- Giriş / çıkış eventleri
- OS geofence API'leri ve sunucu doğrulaması birlikte kullanılmalı

## Gizlilik ve güvenlik

- Konum paylaşımı açık rıza ile başlar
- Kullanıcıya takip aktif durumu görünür
- Tokenlar secure storage/keychain'de
- Raw device token DB'de tutulmaz; SHA-256 hash tutulur
- WebSocket için uzun ömürlü device token URL'ye konmaz; 60 saniyelik imzalı live ticket kullanılır
- Rate limit ve replay koruması v0.2'de eklenmeli
