# Savarona Ailem v0.2 – Verification record

Date: 2026-09-10

## Passed in this engineering session

- Backend TypeScript: `npm run typecheck` — PASS.
- D1 schema: migrations `0001_init.sql`, `0002_hardening.sql`, `0003_resilience.sql` applied in order to a clean SQLite-compatible database — PASS.
- Location replay invariant: a successful sequence inserts once; replay of the same `(device_id, sequence_no)` produces no second row — PASS in SQL invariant simulation.
- One-time invite claim invariant: first conditional claim wins; second claim cannot replace `claim_id` — PASS in SQL invariant simulation.
- Swift native source parser: `LocationTracker`, queue, status store, Keychain store and plugin parse together with `swiftc -frontend -parse` — PASS.
- Bootstrap utility: Python compile check — PASS.
- Repository whitespace validation: `git diff --check` — PASS.
- Credential logging scan: no direct device-token logging patterns found in backend/mobile source — PASS.

## Intentionally delegated to clean CI

The uploaded source archive contained a Windows-installed `backend/node_modules`. This Linux execution environment therefore cannot execute the copied native `workerd` / Rollup binaries. Full Vitest and Wrangler dry-run must run after a clean `npm install`; the backend GitHub Actions workflow does exactly that.

This execution environment also does not contain the Flutter SDK/Android SDK/Xcode. The mobile workflow is pinned to Flutter 3.47.2 and performs:

- Flutter shell generation and native merge,
- `flutter analyze`,
- `flutter test`,
- Android debug APK compile,
- iOS debug no-codesign compile on macOS.

## Release gate still requiring physical devices

Production release remains blocked until `docs/DEVICE_TEST_PLAN.md` passes on at least one Android phone and one iPhone. Background execution, OS permission transitions, reboot/relaunch restoration and real cellular live latency cannot be honestly validated by source/CI alone.
