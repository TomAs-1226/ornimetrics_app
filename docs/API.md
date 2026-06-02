# Ornimetrics — App Integration Guide

This document is for whoever (human or AI) is building the **Ornimetrics mobile app**.
It describes how to talk to the feeder, what data is available, and a roadmap of
features worth building. The feeder runs all the AI on-device (Raspberry Pi 5 +
Hailo-8); the app is a client.

---

## 1. How to reach the feeder

The Pi runs three always-on systemd services:

| Service | What it does | Reachable via |
|---|---|---|
| `ornimetrics-detection` | vision pipeline + **HTTP API** + MJPEG stream | Wi-Fi/LAN, port **5000** |
| `ornimetrics-audio` | BirdNET (bird calls) → `audio_detections.json` | (read through the API) |
| `ornimetrics-ble` | **BLE** status peripheral for offline access | Bluetooth LE |

### Network (primary)
- The Pi has a **static IP: `192.168.0.86`** (set manually; recommend also adding a
  DHCP reservation on the router).
- Base URL: **`http://192.168.0.86:5000`**
- This works **without internet** as long as the phone is on the same LAN — internet
  dropping does not break local access. Discovery: the app can also try mDNS
  (`thomaspi.local`) or scan the subnet for port 5000.

### Bluetooth LE (fallback, no network at all)
- The Pi advertises a BLE peripheral named **`Ornimetrics`**.
- **Service UUID:** `a1b20001-1f8e-4b1a-9c1e-0a1b2c3d4e5f`
- **Status characteristic (read):** `a1b20002-1f8e-4b1a-9c1e-0a1b2c3d4e5f`
- Reading it returns a compact JSON of the current state (see §3, BLE shape).
- Use this when the phone has no Wi-Fi path to the Pi (e.g. internet down *and* not
  on the same LAN). It's read-only status, not the full API.

---

## 2. HTTP API

All JSON unless noted. No auth on the LAN (add a token if you expose it beyond the
home network).

### `GET /api/current`  ⭐ the main one
The live AI output in one call — poll this (every 1–2 s) to drive the app's main screen.
```json
{
  "species": "Northern_Cardinal_ID_852",   // raw class, null if no bird right now
  "species_display": "Northern Cardinal",   // clean name for display
  "species_confidence": 0.87,
  "individual": "#3",                        // gallery id, null if none
  "individual_name": "Spot",                 // custom name if set via /api/teach, else the id
  "welfare": { "distress_z": 2.1, "distressed": false },
  "audio": { "ts": "...", "detections": [ {"species": "Song Sparrow", "confidence": 0.61} ] },
  "total_detections": 4007,
  "backend": "Hailo",
  "has_hailo": true,
  "ts": 1780338806.29
}
```

### `GET /video_feed`
MJPEG stream (`multipart/x-mixed-replace`). Show it directly in an `<img>`/web view, or
decode frames natively. Boxes are drawn server-side with `species [#id] !DISTRESS?`.

### `GET /api/status`
Hardware/mode: `{ backend, detection_enabled, has_3d, has_hailo, has_individual_id, mode, uptime }`

### `GET /api/stats`
Counters: `{ fps, total_detections, total_enrollments, total_triggers, uptime_seconds }`

### `GET /api/individuals`
Recently seen individuals: a map of `id → { name, species, last_seen, can_dispense, reason }`.

### `GET /api/detections/recent`
Rolling list of recent detections (bbox, label, confidence, timestamp).

---

### History & intelligence (added — build the differentiator features on these)

These expose what the AI has *accumulated*, not just the current frame. As of the
latest build this history is **persisted to SQLite on the Pi** (`data/history.db`)
and reloaded on boot, so sightings, the species life-list, individual profiles,
welfare alerts and custom names **survive reboots** — counts are all-time, not
just since the last restart. (Audio history and the live re-ID embeddings are
still in-memory.) The app should still keep its own long-term copy for offline use
and richer history than the Pi's rolling caps.

> **Prefer the SSE stream (`GET /api/events`) over polling** for live updates —
> see "Realtime" below. Use the endpoints here for history/backfill and the
> stream for what's happening now.

#### `GET /api/summary`  ⭐ home/digest screen in one call
`{ species_count, individuals_count, total_sightings, welfare_alerts_24h,
   top_species:[{species,display,count}], uptime_seconds, ts }`

#### `GET /api/species/summary`  — the life-list
`{ species_count, species:[{species, display, count, first_seen, last_seen}] }`
(sorted by count). `display` is the clean name; `species` is the raw class.

#### `GET /api/sightings/recent?limit=50`  — activity feed
Most-recent-first visit log: `{ sightings:[{ts, species, display, confidence,
individual, distress_z, distressed}] }`. Visits are debounced (a bird lingering in
frame = one row), so this is visit-level, not per-frame.

#### `GET /api/individual/<id>`  — one bird's profile + health trend
URL-encode the `#` as `%23` (e.g. `/api/individual/%233`).
`{ id, name, species, display, count, first_seen, last_seen, last_distress_z,
   distress_trend:[{ts, z}] }`. The `distress_trend` is the per-bird **health
trend** over time.

#### `GET /api/welfare/alerts?limit=50`  — push-notification feed
Most-recent-first: `{ alerts:[{ts, species, display, individual, distress_z}] }`.
Each is a **screening flag for a human**, never a diagnosis.

#### `GET /api/audio/recent`  — birds heard over time
`{ heard:[{ts, species, confidence}] }` from the BirdNET mic path (most recent
first). Pair with the camera for the "heard vs. seen" feature.

#### `GET /api/snapshot`  — one current frame as JPEG
Returns `image/jpeg` (annotated). Use for thumbnails / notification images without
holding the MJPEG stream open.

#### `POST /api/teach`  — corrections & naming (the self-improving loop)
Body JSON, `kind` is one of:
- `{"kind":"name","individual":"#3","name":"Spot"}` — name a bird (applied live;
  shows up in `/api/current` `individual_name` and the profile immediately).
- `{"kind":"species","individual":"#3","species":"Blue Jay"}` — correct a species.
- `{"kind":"flag","individual":"#3","note":"looks hurt"}` — a user-reported note.

Returns `{ ok, stored, record }`. Every correction is appended to
`corrections.jsonl` on the Pi — this is the training fuel the model improves from.
A `name` is also written to SQLite so it survives a reboot.

---

### Realtime (push instead of poll)

#### `GET /api/events`  ⭐ Server-Sent Events
Open this once and receive events as they happen — no polling. Standard SSE, works
with the browser/React-Native `EventSource`:
```js
const es = new EventSource('http://192.168.0.86:5000/api/events');
es.onmessage = (e) => {
  const ev = JSON.parse(e.data);
  if (ev.type === 'sighting')      { /* update live view / activity feed */ }
  if (ev.type === 'welfare_alert') { /* fire a push notification */ }
};
```
Event types (every payload has a `type`):
| `type` | when | payload |
|---|---|---|
| `hello` | on connect | `{type, ts}` |
| `sighting` | a bird was identified | full sighting row (ts, species, display, confidence, individual, distress_z, distressed) |
| `welfare_alert` | a distress flag fired | `{type, ts, species, display, individual, distress_z}` |

Lines beginning with `:` are keepalive comments (sent ~every 15 s) — your SSE
client ignores them automatically. The stream sends `retry: 3000`, so a dropped
connection auto-reconnects after 3 s. This is the recommended way to drive the
live view, activity feed, and welfare push notifications.

---

### `POST /api/control/detection`
Toggle detection on/off (body `{ "enabled": true|false }`).

### `POST /api/control/reset_db`
Clear the individual/gallery database.

> If a response shape is unclear, just `curl http://192.168.0.86:5000/<endpoint>` — the
> handlers are thin `jsonify()`s of server state, so what you see is what you get.

---

## 3. Data model / field notes

- **`species`** — currently the raw class name (e.g. `Carolina_Chickadee_ID_811`).
  For display, strip the `_ID_<n>` suffix and replace underscores with spaces. (A
  cleaner display-name map can be added server-side if the app wants it.)
- **`individual`** — a per-species gallery id like `#3`. It's *appearance-based and
  approximate*; treat as a soft hint. Stable within a session; resets on service
  restart (persisting the gallery is a TODO).
- **`welfare.distress_z`** — anomaly score; higher = more unusual vs. healthy birds.
  `distressed` is `z > threshold`. **Over-fires on a new/cheap camera** until
  recalibrated — surface it gently ("possible issue, take a look"), never as a verdict.
- **`audio.detections`** — BirdNET species heard via the mic (independent of the camera).
- **BLE shape** (compact, ≤500 B): `{ sp, spc, id, hurt, snd, n, ai }`
  (species, conf, individual, distressed-bool, top audio species, total detections, hailo-on).

---

## 4. What the AI can do (so you know what to surface)

- **Detector:** finds `bird / squirrel / person / dog` (the gate).
- **Species:** 555 North-American species (NABirds model), ~87% on clean images.
- **Welfare:** flags birds that look injured/sick/dead (screening, not diagnosis).
- **Individual re-ID:** tells individuals apart from appearance (approximate).
- **Audio:** BirdNET identifies birds by call, on a separate mic path.

---

## 5. Feature roadmap (build these in the app)

Ordered roughly by value/effort. Everything here is supported by the data above.

**Core (ship first)**
1. **Live view** — `/video_feed` + an overlay reading `/api/current` (species, individual, distress).
2. **Activity feed** — timeline of detections (species, time, thumbnail) from `/api/detections/recent`.
3. **Species life-list** — running list of species seen, counts, first/last seen. (App keeps the history; the Pi only holds recent.)

**The differentiators (this is what makes Ornimetrics unique)**
4. **Welfare alerts** — push notification when `welfare.distressed` fires on a bird, with the photo and a "this is a screening flag — here's how to find a wildlife rehabber" flow. *Always* keep a human in the loop.
5. **Individual bird profiles** — a page per `individual`: visit history, photos, which species, a simple health trend (distress_z over time). This is the "you have *regulars*" feature nobody else has.
6. **"Teach the feeder"** — let the user confirm/correct a species or name an individual. These corrections are the fuel for the **self-improving loop** (fine-tuning on the user's own birds). Store them; they're the long-term moat.
7. **Heard vs. seen** — fuse `audio` + camera: "a Song Sparrow is singing nearby" even when none is on camera.

**Nice-to-have**
8. **Intruder alerts** — notify on `squirrel`/`person`/`dog` (and later, trap/dispenser control via a `/api/control/...` endpoint to add).
9. **Daily/weekly digest** — top species, busiest times, new individuals, any welfare flags.
10. **Offline status tile** — read the BLE characteristic when there's no network, show last-known state.
11. **Multi-feeder** — the app already speaks to one Pi by IP; generalize to a list of feeders.

---

## 6. Operational notes

- Restart a service: `sudo systemctl restart ornimetrics-detection` (or `-audio` / `-ble`).
- All three are `enabled` (start on boot).
- The detection service runs the vision pipeline; the species/welfare/re-ID heads run on
  CPU only when a bird is detected, so they don't slow the ~28 fps stream.
- Models + this pipeline are published at
  `https://huggingface.co/Ornimetrics/ornimetrics-edge`.
- Config lives in `config_3d_detection.json` / `ornimetrics_os_config.json`; the web app
  is `web_detection_server.py`; the BLE peripheral is `src/ble_status_service.py`.

---

## 7. TODO / known gaps for the app side

- ~~Add a clean display-name map for species~~ ✅ done — `display` / `species_display`
  fields are now returned everywhere.
- ~~Capture "teach"/correction data~~ ✅ done — `POST /api/teach` writes
  `corrections.jsonl`. **Still TODO:** ship that file back to the training box and
  actually retrain on it (closes the self-improving loop).
- ~~Persist history across restarts~~ ✅ done — sightings, species tally, individual
  profiles, welfare alerts and names are in SQLite (`data/history.db`) and reload on
  boot. **Still TODO:** persist the live re-ID **gallery embeddings** too (the
  appearance vectors are still in-memory, so a restart can re-number `#` ids).
- Add an endpoint for **trap/dispenser control** when that hardware is wired.
- Add a lightweight **auth token** before exposing the API outside the LAN.
