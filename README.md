# Ornimetrics App

Modernized feeder assistant with notifications, environment context, and a community center.

## Minimal setup
- Install Flutter SDK + Firebase CLI.
- Run `firebase login` once.
- For local development run the Firebase emulators (Auth/Firestore/Storage/RTDB) with `firebase emulators:start` in another terminal; the app defaults to emulator hosts in debug.
- Launch the app: `flutter run` (no Firebase console setup required for emulator mode).

### Optional: one-command Firebase bootstrap
After logging in, you can prime a real project (rules + indexes + storage) with:
```
./scripts/bootstrap_firebase.sh <your-project-id>
```
If you omit the project id the script will prompt once. It writes `firebase.json`, rules, and deploys the basics.

## Key areas
- **Feeder notifications:** Settings + simulation panel in Notification Center. Preferences persisted locally.
- **Environment:** Weather + humidity with mock provider by default; swap to real provider when API keys are ready.
- **Community Center:** Forum-style feed, Firebase Auth email/password, test mode sandbox, photo upload, weather/sensor tags, and mocked AI chat per post.

## How to test
- **Notifications:** Open Settings → Feeder notifications, toggle intervals, and tap simulate buttons for low food, clog, and cleaning due.
- **Weather:** Visit Environment tab; pull to refresh mock data. Swap provider in settings when a real API endpoint is configured.
- **Community:** In emulator mode (default), open Community tab, leave test mode on, post with/without photo, and pull to refresh. Toggle off test mode to exercise Firebase Auth; permission errors surface in UI.
- **AI chat:** Open any community post → “Ask AI about this post” to see mocked AI responses that include weather/sensor context. Global AI prompt available from the header sparkle icon.
