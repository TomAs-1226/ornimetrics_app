# Ornimetrics feeder integration — rebuild notes

This change rebuilds the in-app feeder integration against the **real** on-device
API contract (`docs/API.md`, copied from the feeder repo's `APP_INTEGRATION.md`).
It is a Flutter app (not native Kotlin), so the work was done in Flutter; the
existing community, tools, weather and Firebase features were left untouched.

## Why this was needed

The previous feeder layer targeted endpoints the device **does not have**
(`/api/recent_detections`, `/api/training/*`, `/api/warnings`) and expected
nested `/api/status` shapes the server never returns. None of the real
endpoints — `/api/current`, `/api/summary`, the `/api/events` SSE stream,
`/api/teach`, `/api/welfare/alerts`, `/api/individual/<id>`, `/api/audio/recent`,
`/api/species/summary`, `/api/snapshot` — were used. So the differentiator
features and the realtime path were effectively unbuilt. Every endpoint below
was verified against the live feeder at `http://192.168.0.86:5000`.

## Data layer (rewritten)

- **`lib/models/feeder_models.dart`** — REST models replaced with the real
  contract: `CurrentState`, `WelfareInfo`, `AudioSnapshot`, `FeederStatus`,
  `FeederStatsCounters`, `FeederSummary`/`TopSpecies`, `SpeciesLifeEntry`,
  `Sighting`, `IndividualProfile`/`DistressPoint`, `WelfareAlert`, `AudioHeard`,
  `FeederIndividual`. Added `cleanSpeciesName()` to strip `_ID_<n>` suffixes.
  BLE / onboarding / Firebase / `PairedFeeder` models kept as-is.
- **`lib/services/feeder_api_service.dart`** — rewritten as the single source of
  live state (ValueNotifiers the UI binds to). Real endpoints, `POST /api/teach`
  (name / species / flag), `POST /api/control/detection` with body, snapshot URL,
  current-state poller, and bulk history refresh. Robust to `/api/individuals`
  arriving as either a list or an id→info map.
- **`lib/services/feeder_events_service.dart`** (new) — SSE client for
  `/api/events`. Parses `hello` / `sighting` / `welfare_alert`, honours `retry:`,
  ignores `:` keepalives, auto-reconnects, feeds sightings/alerts into the API
  service, and fires a welfare notification.

## Realtime & notifications

- The home hub opens the SSE stream when a feeder is connected and pauses it in
  the background (`WidgetsBindingObserver`), resuming on foreground.
- `welfare_alert` → `NotificationsService.showWelfareAlert()` (new public method,
  own Android channel). Wording is always "screening flag, not a diagnosis".

## UI (rebuilt feeder surface)

One shared Material 3 design system in **`lib/widgets/feeder_ui.dart`** (spacing
tokens, `FeederCard`, section headers, stat tiles, `AnimatedCount`,
`SpeciesAvatar`, skeleton loaders, empty/error/offline states, `Sparkline`,
welfare copy). Screens:

- **`feeder_tab_screen.dart`** — home hub: live "now" card (`/api/current` +
  snapshot thumb), digest stats, welfare banner, quick actions, top-species and
  a live SSE-driven activity preview.
- **`feeder_activity_screen.dart`** — activity feed (live via SSE) + species
  life-list, with the reusable `SightingTile`.
- **`feeder_individual_profile_screen.dart`** — per-bird profile, **health-trend
  sparkline** (distress_z over time), and **"teach the feeder"** (name / correct
  species / flag → `/api/teach`).
- **`feeder_individuals_screen.dart`** — "your regulars" list.
- **`feeder_welfare_screen.dart`** — welfare alerts + "find a rehabber" flow.
- **`feeder_audio_screen.dart`** — heard-vs-seen (BirdNET mic).
- **`feeder_stream_screen.dart`** — live MJPEG with an identification overlay
  from `/api/current`; "share frame" capture.
- `feeder_detections_screen.dart` removed (replaced by the activity screen).
- `main.dart` demo-feeder mock data updated to the new models (offline demo).

## Platform config (was missing — would have blocked the real device)

- **Android**: added `POST_NOTIFICATIONS` permission and a
  `network_security_config.xml` permitting cleartext HTTP (the feeder is a LAN
  device on `http://`). Without this, every API/stream call fails on API 28+.
- **iOS**: `NSAllowsLocalNetworking` + `NSLocalNetworkUsageDescription`.

## Verified

- `flutter analyze`: 0 errors; the new feeder files are warning-clean.
- All consumed endpoints checked against the live feeder, including an SSE sample
  (`hello` frame received).
