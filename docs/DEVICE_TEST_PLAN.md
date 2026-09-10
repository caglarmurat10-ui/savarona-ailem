# Real-device acceptance plan

Use at least one Android device and one iPhone, both on cellular data for part of the test.

## A. Enrollment and consent

1. Owner bootstraps the family.
2. Owner creates a one-time invite.
3. Second phone joins; invite reuse must fail.
4. On both phones tap **Konum paylaşımını başlat / düzelt** and grant the OS location permission requested by the app.
5. Health screen must show the actual OS state; background-capable operation should show **Her zaman**.

## B. Live tracking

1. Put both phones on the map simultaneously.
2. Walk 100–200 m: marker, heading and speed should update.
3. Drive safely with a passenger operating the test phone: speed should update while moving.
4. Stop for >60 s: old speed must not continue to be displayed as current speed.
5. Target live delivery latency under normal connectivity: typically a few seconds while moving; exact cadence is OS/network controlled.

## C. Background behavior

1. Lock the Android screen for 10 min. Persistent foreground-service notification must remain visible where Android permits notifications.
2. Lock the iPhone for 10 min. Confirm fresh locations continue under the granted iOS authorization/background mode.
3. Reboot Android. A previously user-enabled session should restore after boot only when the required location permissions are still present.
4. Relaunch iOS after normal process termination. A previously enabled/authorized session should restore.

## D. Permission loss

1. While sharing, remove location permission from system settings.
2. Family view must stop treating old speed as live.
3. The device should report `permission_lost` when the OS still allows the process to communicate, then become stale if no more heartbeat is possible.
4. Re-enable permission, return to the app, and verify tracking resumes after the user-enabled session is restored.

## E. Network loss / queue

1. Enable airplane mode for 2–5 min while moving a short safe route.
2. Re-enable network.
3. Queued samples must drain in sequence without duplicate `(device_id, sequence_no)` records.
4. WebSocket must reconnect after connectivity returns.

## F. SOS

1. Hold SOS for 2 seconds.
2. Confirm only one SOS event is created and contains the sender's latest known location.

## G. Pass criteria

Release only after Android APK and iOS no-codesign CI builds are green and sections A–F pass on real devices. Do not claim the app is impossible for the device owner/OS to stop; that is intentionally not part of the design.
