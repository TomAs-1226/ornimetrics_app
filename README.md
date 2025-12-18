# Ornimetrics App

Modernized feeder assistant with notifications, environment context, and a community center.

## Minimal setup
- Install Flutter SDK + Firebase CLI.
- (Optional for deploy) Run `firebase login` once.
- Launch the app: `flutter run` (uses the cloud Firebase project defined in `lib/firebase_options.dart`).
- A stub `android/app/google-services.json` is checked in for convenience; the bootstrap script regenerates it for a real project when you're ready.

### Optional: one-command Firebase bootstrap
After logging in, you can prime a real project (rules + indexes + storage) with:
```
./scripts/bootstrap_firebase.sh <your-project-id>
```
If you omit the project id the script will prompt once. It writes `firebase.json`, rules, emulator config, and deploys basics. If `flutterfire` CLI is available it auto-generates `lib/firebase_options.dart`; otherwise the existing file is reused.

## Production readiness
- Run `flutterfire configure` to regenerate **lib/firebase_options.dart** and replace the stubbed `android/app/google-services.json` and `GoogleService-Info.plist` with the real files for your Firebase project. Keep Firebase keys out of `.env` to avoid desync.
- Deploy the RTDB/Firestore/Storage rules in `database.rules.json`, `firestore.rules`, and `storage.rules` to keep community login and media secure. Enable Email/Password Auth in Firebase for the Community Center.
- For community uploads, optionally set `COMMUNITY_STORAGE_BUCKET` in `.env` if you want a dedicated bucket; otherwise the Firebase project’s default bucket is used. Weather still uses `WEATHER_API_KEY` / `WEATHER_ENDPOINT` in `.env`.
- Location permissions are requested on launch to tag photos and the gallery with accurate current + historical weather. Ensure your Firebase project allows HTTPS calls to the configured weather provider.

### Community Center Firebase
1. Create (or reuse) a Firebase project and enable **Email/Password** auth.
2. Create a production Cloud Firestore database and Storage bucket. Keep the default `community_posts` collection and apply the indexes in `firestore.indexes.json`.
3. Run `./scripts/bootstrap_firebase.sh <projectId>` to regenerate `lib/firebase_options.dart`, RTDB URL, rules, and platform configs.
4. Rebuild the mobile/web apps so the new configs are baked into the binaries. Credentials are stored by Firebase Auth; the app never persists raw passwords locally.

### Weather + location
- Sign up for WeatherAPI.com (or another compatible endpoint) and place the key + base endpoint in `.env`.
- The app requests GPS permission and forwards latitude/longitude to the weather provider for both live and historical lookups (used in the gallery and Community posts). Historical weather is derived from each photo’s timestamp and your coordinates.

## Key areas
- **Feeder notifications:** Settings panel in Notification Center. Preferences persisted locally, progress food bar, weather/heavy-use triggers, and production-oriented maintenance rules.
- **Environment:** Weather + humidity fetched from your configured provider using device GPS. Weather data also feeds maintenance rules.
- **Community Center:** Forum-style feed with Firebase Auth email/password, photo upload, weather/sensor tags, and Ecology Insights AI chat per post with richer metadata badges. All traffic targets production Firebase collections.

## How to test
- **Notifications:** Open Settings → Feeder notifications, adjust thresholds/intervals, and connect a real food-level signal; reset cooldowns from the maintenance card.
- **Food progress:** Watch the food card update when telemetry arrives from your production device.
- **Weather:** Visit Environment tab; pull to refresh live data from the configured provider. Location permission must be granted.
- **Community:** Open Community tab, sign in with Firebase Auth, post with/without photo, and pull to refresh. Forum cards show time-of-day, weather, humidity, and sensor tags sourced from your location and provider.
- **AI chat:** Open any community post → “Ask AI about this post” to see Ecology Insights responses with weather/sensor context. Global AI prompt available from the header sparkle icon; disclaimer shown in detail view.
