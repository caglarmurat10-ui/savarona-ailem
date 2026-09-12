# Savarona Agent Protocol v0.1

Her uygulama Savarona AI'ya asagidaki ortak sozlesmeyle baglanir.

## Zorunlu kimlik

Uygulama tarafinda bir agent manifest bulunur:

```json
{
  "protocol": "savarona-agent/0.1",
  "project_id": "villa",
  "name": "Villa Yonetim",
  "environment": "production",
  "version": "git-sha-or-semver",
  "capabilities": ["health", "errors"],
  "risk_profile": "critical"
}
```

## Endpointler

- `GET /agent/manifest` -> kimlik, surum, capabilities
- `GET /agent/health` -> servis ve bagimlilik sagligi
- `GET /agent/metrics` -> hassas veri icermeyen ozet metrikler
- `POST /agent/events` -> uygulamanin Savarona Core'a olay gondermesi (push modeli)

`/agent/health` minimum yaniti:

```json
{
  "status": "healthy",
  "version": "...",
  "checks": {
    "database": "healthy",
    "external_api": "healthy"
  }
}
```

## Guvenlik

- Endpointler secret/token dondurmez.
- Kisi konumu, saglik verisi, mesaj icerigi gibi hassas uygulama verileri merkezi agent loguna kopyalanmaz.
- Savarona yalnizca operasyonel hata kodu, sayac, surum, servis durumu ve guvenli log ozeti alir.
- Uygulama kendi veri erisim politikasini korur; AI bu siniri genisletemez.

## Degisiklik politikasi

- `READ_ONLY`: otomatik.
- `LOW_RISK`: branch + test + PR; geri alinabilirlik zorunlu.
- `HIGH_RISK`: Murat onayi olmadan uygulanmaz.

HIGH_RISK ornekleri: production deploy, D1 destructive migration, kullanici/veri silme, hesap sahipligi/izinleri, reklam butcesi, secret degisikligi.

## Self-improvement

Gunluk self-review yalnizca son 24 saatteki operasyonel olaylardan iyilestirme onerisi cikarir. Oneri su alanlari tasir:

- kanit
- kok neden veya hipotez
- minimum degisiklik
- risk seviyesi
- test plani
- rollback plani
- onay gereksinimi

Ajan kendi guardrail, audit log veya onay politikasini otomatik degistiremez.
