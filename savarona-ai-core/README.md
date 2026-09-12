# Savarona AI Core

Savarona ekosistemindeki tum uygulamalar icin ortak AI operasyon katmaninin ilk guvenli cekirdegidir.

## Hedef

- Aile Takip, Villa Yonetim, HAL, Sera Otomasyonu ve gelecekteki projeleri tek merkezden izlemek.
- Hata/olaylari siniflandirmak ve OpenAI + Claude ile cift inceleme yapmak.
- Dusuk riskli iyilestirmeleri otomatiklestirmeye hazirlamak.
- Production, veritabani, hesap sahipligi ve butce gibi yuksek riskli islemleri insan onayina birakmak.
- Zamanlanmis saglik kontrolleri ve gunluk self-review dongusu calistirmak.

## Guvenlik modeli

1. READ_ONLY: saglik kontrolu, log analizi, kod inceleme, oneriler.
2. LOW_RISK: test, branch/PR hazirlama, geri alinabilir kucuk degisiklikler.
3. HIGH_RISK: production deploy, D1 migration/silme, hesap/izin, reklam butcesi. Murat onayi zorunlu.

AI kendi guvenlik politikasini veya onay sinirlarini degistiremez. Self-improvement yalnizca yeni bir oneriyi olusturur; guardrail katmanini atlayamaz.

## Ilk API

- `GET /health`
- `GET /projects`
- `POST /events`
- `POST /agent/analyze`
- `POST /agent/improve`

Yazma endpoint'leri `SAVARONA_ADMIN_TOKEN` ayarlandiysa `Authorization: Bearer ...` ister.

## Model ayarlari

API anahtarlari repoya yazilmaz. Cloudflare secret olarak tanimlanir:

- `OPENAI_API_KEY`
- `ANTHROPIC_API_KEY`
- `SAVARONA_ADMIN_TOKEN`

Model adlari environment variable ile verilir:

- `OPENAI_MODEL`
- `ANTHROPIC_MODEL`

Bu sayede Savarona belirli bir modele bagimli kalmaz; model degisse bile kimligi, hafizasi ve politika katmani ayni kalir.

## Sonraki asama

Bu bootstrap kodu once ayri bir `savarona-ai` reposuna tasinacak, D1/Queue/Workflow kaynaklari olusturulacak ve GitHub App ile PR uretme yetenegi eklenecek. Production'a dogrudan yazma yetkisi ilk surumde verilmeyecek.
