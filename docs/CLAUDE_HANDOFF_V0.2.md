# Savarona Ailem v0.2 – Engineering Handoff

This revision supersedes the v0.1 handoff for release work.

## Architecture invariants
- Flutter is the shared UI/application layer; native Android/iOS code owns durable background-location execution.
- Device bearer tokens must remain in Android Keystore-backed encrypted storage / iOS Keychain. Do not persist bearer tokens in plaintext preferences.
- Location uploads use a monotonically increasing `sequence_no`. Sequence advancement and location insertion must remain atomic in D1.
- Family invites are one-time and must remain race-safe.
- WebSocket auth uses short-lived signed live tickets, never the long-lived device token in the URL.
- Heartbeats and GPS timestamps are distinct. A heartbeat must never make stale coordinates/speed look current.
- Push tokens are stored as hash + AES-GCM ciphertext/IV. `PUSH_TOKEN_ENCRYPTION_KEY` is a secret, never repository content.
- A stale-device notification/event is emitted once per offline episode and resets after fresh location/heartbeat data.
- User consent and OS controls are mandatory. Never add stealth tracking, hidden permission escalation, or force-stop bypass behavior.

## Build
Run from repository root on a machine with Flutter installed:

```bash
python3 tools/bootstrap_mobile.py
cd mobile
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --dart-define=API_BASE_URL=https://example.invalid
```

CI performs Android APK compile and an iOS `--no-codesign` compile from a freshly generated Flutter shell.

## Backend release gates

```bash
cd backend
npm install
npm run typecheck
npm test
npx wrangler deploy --dry-run
```

Apply D1 migrations before production deploy. Production secrets include `ADMIN_BOOTSTRAP_SECRET`, `SESSION_SIGNING_KEY`, and `PUSH_TOKEN_ENCRYPTION_KEY`.

## Real-device release gates
Use `docs/DEVICE_TEST_PLAN.md` on at least one Android device and one iPhone. A source/CI build is not a substitute for the background-location, permission-loss, network-loss, reboot/relaunch, and live-latency tests.
