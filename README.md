# Ornimetrics App

Modernized feeder assistant with notifications, environment context, and a community center.

## Minimal setup
- Install Flutter SDK + Firebase CLI.
- (Optional for deploy) Run `firebase login` once.
- For local development, start the emulators (Auth/Firestore/Storage/RTDB/UI) with `firebase emulators:start` in another terminal; the app defaults to emulator hosts in debug and runs fully without console setup.
- Launch the app: `flutter run` (emulator/test mode works immediately).

### Optional: one-command Firebase bootstrap
After logging in, you can prime a real project (rules + indexes + storage) with:
```
./scripts/bootstrap_firebase.sh <your-project-id>
```
If you omit the project id the script will prompt once. It writes `firebase.json`, rules, emulator config, and deploys basics. If `flutterfire` CLI is available it auto-generates `lib/firebase_options.dart`; otherwise the existing file is reused.

## Key areas
- **Feeder notifications:** Settings + simulation panel in Notification Center. Preferences persisted locally, progress food bar, weather/heavy-use triggers, and debug-only test bench.
- **Environment:** Weather + humidity with mock provider by default; swap to real provider when API keys are ready. Weather data also feeds maintenance rules.
- **Community Center:** Forum-style feed, Firebase Auth email/password, test mode sandbox, photo upload, weather/sensor tags, and mocked AI chat per post with richer metadata badges.

## How to test
- **Notifications:** Open Settings → Feeder notifications, adjust thresholds/intervals, and (in debug) use the test bench to trigger low food, clog, cleaning due, heavy use, weather events, and food draining progress. Reset cooldowns from the maintenance card.
- **Food progress:** Watch the food card update and show progress notifications as the mock drain runs; low thresholds should emit alerts.
- **Weather:** Visit Environment tab; pull to refresh mock data (includes rain/snow flags). Swap provider in settings when a real API endpoint is configured.
- **Community:** In emulator mode (default), open Community tab, keep test mode on, post with/without photo, and pull to refresh. Toggle off test mode to exercise Firebase Auth; permission errors surface in UI. Forum cards show time-of-day, weather, humidity, and sensor tags.
- **AI chat:** Open any community post → “Ask AI about this post” to see mocked AI responses with weather/sensor context. Global AI prompt available from the header sparkle icon; disclaimer shown in detail view.
