# Ornimetrics - Video Capture Guide (2-Minute Competition Video)

## Recording Setup

### Emulator Screen Recording (ADB)
```bash
# Start recording (max 3 min per recording)
adb shell screenrecord /sdcard/clip_name.mp4

# Press Ctrl+C to stop, then pull the file:
adb pull /sdcard/clip_name.mp4 ./video_clips/
```

### Alternative: Android Studio built-in recorder
- Open Device Manager → Click the "..." menu on your emulator → Record Screen

### Recommended Settings
- Resolution: 1080x1920 (emulator default)
- Crop to app area only in your editor (remove emulator chrome)
- Record each clip separately for easy editing

---

## Clips to Capture (Ordered by Video Timeline)

### CLIP 1 — App Launch / Home Screen (0:00–0:10)
**Screen:** `feeder_tab_screen.dart` (Main Feeder Dashboard)
**What to record:**
- Cold-start the app from the emulator home screen
- Show the splash screen → main dashboard loading
- Let the dashboard fully render with feeder status, food level, etc.
**Duration needed:** ~5–8 seconds of clean footage
**Tip:** Make sure demo data is loaded so the screen looks populated

---

### CLIP 2 — Feeder Hardware Photo (0:10–0:25)
**NOT from emulator** — Use your real feeder photo(s)
**What to prepare:**
- 1 full photo of your feeder setup (clear, well-lit)
- 1 zoomed-in or second angle photo (optional)
- Add text labels/arrows in your video editor: "Camera", "Feeder", "Monitoring System"
**Duration on screen:** ~12–15 seconds with narration overlay

---

### CLIP 3 — Feature 1: Bird Detection & Activity Review (0:25–0:43)
**Screen:** `feeder_detections_screen.dart`
**What to record:**
- Navigate from dashboard to Detections screen
- Scroll through bird detection entries
- Tap on a detection to show detail (species, timestamp, confidence)
- Show the pie chart / analytics breakdown
**Duration needed:** ~15–18 seconds
**Narration:** "This feature lets users review bird sightings and detected activity. Instead of sorting through raw data, the app organizes observations into something useful."

---

### CLIP 4 — Feature 2: Environment & Weather Context (0:43–1:01)
**Screen:** `environment_screen.dart`
**What to record:**
- Navigate to the Environment screen
- Show live weather data (temperature, humidity, conditions)
- Show how weather is tied to observation data
- Let it refresh if there's a live-update animation
**Duration needed:** ~15–18 seconds
**Narration:** "The environment screen provides real-time weather context, so every observation is tied to conditions like temperature and humidity."

---

### CLIP 5 — Feature 3: Community Center (1:01–1:20)
**Screen:** `community_center_screen.dart` → `community_post_detail.dart`
**What to record:**
- Open the Community Center feed
- Scroll through posts (show photos, weather tags)
- Tap into a post to show detail view
- Show the AI Ecology Insights feature (if visible)
**Duration needed:** ~15–18 seconds
**Narration:** "The community center lets users share observations and get AI-powered ecology insights about what they're seeing."

---

### CLIP 6 — Software + Hardware Connection (1:20–1:40)
**Screen:** `feeder_tab_screen.dart` (Dashboard) or `feeder_stream_screen.dart`
**What to record:**
- Show the dashboard with feeder connection status
- Show real-time food level monitoring
- If possible, show the live stream screen or Bluetooth connection UI
- Demonstrate how app reflects feeder state
**Duration needed:** ~15–20 seconds
**Narration:** "What makes Ornimetrics unique is that it's not just a mobile app or a device — it's a connected system combining app development, monitoring hardware, and AI analysis."

---

### CLIP 7 — Quick Feature Montage (within 1:20–1:40 or near end)
**Screens:** Multiple quick cuts
**What to record (2–3 seconds each):**
- Notification Center (`notification_center_screen.dart`) — show alert settings
- Individual Bird Tracking (`feeder_individuals_screen.dart`) — scroll the list
- Feeder Setup / Onboarding (`feeder_setup_screen.dart` or `onboarding_screen.dart`) — show one screen
**Duration needed:** ~5–8 seconds total (fast montage)
**Narration:** "Other features include activity history, organized logs, and a clean interface for reviewing data."

---

### CLIP 8 — Strong Closing (1:40–2:00)
**Screen:** Best-looking screen — probably the Dashboard or Community Center
**What to record:**
- Smoothly scroll or interact with your most polished screen
- End on a clean, static view of the app
**Duration needed:** ~15–20 seconds
**Narration:** "I built Ornimetrics to make bird observation more interactive, informative, and accessible through technology. Thank you for watching."

---

## Recording Checklist

Before recording each clip:
- [ ] Emulator is running at 1080x1920
- [ ] App has demo/sample data loaded (detections, community posts, weather)
- [ ] Dark mode OFF (light mode is easier to see in video)
- [ ] Status bar shows reasonable time (set emulator time if needed)
- [ ] No notification popups or overlays
- [ ] WiFi/signal icons look normal

### ADB Quick Commands
```bash
# List connected devices/emulators
adb devices

# Start screen recording
adb shell screenrecord --size 1080x1920 /sdcard/clip1_home.mp4

# Stop recording: Ctrl+C

# Pull all clips
adb pull /sdcard/ ./video_clips/

# Take a screenshot instead
adb shell screencap /sdcard/screenshot.png
adb pull /sdcard/screenshot.png ./screenshots/

# Set emulator time (optional, for clean status bar)
adb shell date -s "2026-04-05 14:00:00"
```

## Feature Selection Rationale

Based on your video script's selection criteria:

| Feature | Why It Made the Cut |
|---------|-------------------|
| Bird Detections | Most important — core value proposition |
| Environment/Weather | Visually impressive — live data, clean UI |
| Community Center | Makes the project unique — social + AI insights |
| Dashboard + Feeder Connection | Ties software and hardware together |

Features in montage only (too technical for deep dive):
- Notification settings, individual bird tracking, setup/onboarding
