# Cloudflare production deployment

## 1. D1

```bash
cd backend
npm install
npx wrangler d1 create savarona-ailem
```

Put the returned `database_id` into `backend/wrangler.jsonc`.

## 2. Secrets

Generate three independent high-entropy values. Never commit them.

```bash
npx wrangler secret put ADMIN_BOOTSTRAP_SECRET
npx wrangler secret put SESSION_SIGNING_KEY
npx wrangler secret put PUSH_TOKEN_ENCRYPTION_KEY
```

`PUSH_TOKEN_ENCRYPTION_KEY` protects recoverable APNs/FCM registration tokens with AES-GCM. D1 stores both a SHA-256 hash for lookup/dedup and ciphertext for future delivery; plaintext push tokens are not stored.

## 3. Migrations + deploy

```bash
npm run db:remote
npm run check
npm run deploy
```

Verify:

```bash
curl https://YOUR-WORKER.workers.dev/health
```

Expected JSON contains `"ok":true`.

## 4. First owner

Build the mobile app with the production URL:

```bash
flutter run --dart-define=API_BASE_URL=https://YOUR-WORKER.workers.dev
```

Use **İlk aile sahibi olarak kur** once, with `ADMIN_BOOTSTRAP_SECRET`. Afterwards family members join via one-time invite codes.

## 5. Release rules

- Never put Wrangler secrets in GitHub, Flutter `--dart-define`, app assets, screenshots or logs.
- The device bearer token is returned once and stored with Flutter secure storage plus native Keystore/Keychain for the background tracker.
- Run all migrations before deploying code that depends on them.
- Keep D1 backup/retention policy appropriate for location history.
- Configure production data retention before onboarding real family members.
