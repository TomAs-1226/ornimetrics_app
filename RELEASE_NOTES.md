# Ornimetrics App v2.1.0 - Official Release

## Your Complete Bird Watching & Feeder Monitoring Companion

**Release Date:** December 2024
**Version:** 2.1.0
**Build:** 1
**Platforms:** Android (iOS coming soon)

---

## Table of Contents

1. [Introduction](#introduction)
2. [Downloads](#downloads)
3. [System Requirements](#system-requirements)
4. [Complete Feature List](#complete-feature-list)
5. [Detailed Feature Guide](#detailed-feature-guide)
6. [Installation Guide](#installation-guide)
7. [Getting Started](#getting-started)
8. [Privacy & Data](#privacy--data)
9. [Building from Source](#building-from-source)
10. [Known Issues](#known-issues)
11. [Roadmap](#roadmap)
12. [Support & Feedback](#support--feedback)
13. [Credits & Acknowledgments](#credits--acknowledgments)
14. [License](#license)
15. [Changelog](#changelog)

---

## Introduction

Welcome to **Ornimetrics** - the ultimate companion app for bird enthusiasts, backyard birders, and wildlife researchers. Whether you're monitoring your bird feeder, conducting field observations, or simply enjoying the beauty of avian wildlife, Ornimetrics provides you with powerful tools to track, identify, and analyze bird activity.

Ornimetrics seamlessly integrates with smart bird feeder systems to provide real-time detection data, while also offering comprehensive manual logging tools for field observations. With AI-powered species identification, detailed analytics, weather integration, and community features, Ornimetrics transforms your birdwatching hobby into a data-rich experience.

### Why Ornimetrics?

- **Real-Time Monitoring** - Connect to your smart bird feeder and receive live detection updates
- **AI-Powered Identification** - Identify bird species from photos using advanced AI
- **Comprehensive Logging** - Record field observations with location, weather, and behavioral notes
- **Beautiful Analytics** - Visualize your sightings with charts, trends, and statistics
- **Offline Capable** - Access your data even without an internet connection
- **Privacy Focused** - Your data stays yours, with transparent data handling policies
- **Community Features** - Share sightings and connect with fellow birders

---

## Downloads

### Android

| Download | Architecture | Size | Description |
|----------|--------------|------|-------------|
| [ornimetrics-v2.1.0.apk](https://github.com/TomAs-1226/ornimetrics_app/releases/download/v2.1.0/ornimetrics-v2.1.0.apk) | Universal | ~50MB | Works on all Android devices |
| [ornimetrics-v2.1.0-arm64-v8a.apk](https://github.com/TomAs-1226/ornimetrics_app/releases/download/v2.1.0/ornimetrics-v2.1.0-arm64-v8a.apk) | ARM64 | ~35MB | Modern phones (2018+), smaller download |
| [ornimetrics-v2.1.0-armeabi-v7a.apk](https://github.com/TomAs-1226/ornimetrics_app/releases/download/v2.1.0/ornimetrics-v2.1.0-armeabi-v7a.apk) | ARM32 | ~35MB | Older Android devices |
| [ornimetrics-v2.1.0-x86_64.apk](https://github.com/TomAs-1226/ornimetrics_app/releases/download/v2.1.0/ornimetrics-v2.1.0-x86_64.apk) | x86_64 | ~35MB | Chromebooks, emulators |

> **Which APK should I download?**
> - If unsure, download the **Universal APK** - it works on all devices
> - For a smaller download on modern phones, use the **ARM64** version
> - For older phones (pre-2018), use the **ARM32** version

### iOS

| Status | Details |
|--------|---------|
| **Work in Progress** | iOS and App Store release is currently under development. We are in the process of enrolling in the Apple Developer Program to obtain the necessary certificates and provisioning profiles for App Store distribution. |

**Estimated Timeline:** Q1 2025

**For iOS Developers:** You can build from source using Xcode. See the [Building from Source](#building-from-source) section.

---

## System Requirements

### Android

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| Android Version | 5.0 (Lollipop, API 21) | 10.0+ (API 29+) |
| RAM | 2 GB | 4 GB+ |
| Storage | 100 MB | 500 MB+ |
| Screen | 4.5" | 5.5"+ |
| Internet | Required for sync | Broadband/WiFi |
| GPS | Optional | Recommended |
| Camera | Optional | Recommended |

### iOS (When Available)

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| iOS Version | 13.0 | 16.0+ |
| Device | iPhone 6s+ | iPhone 11+ |
| Storage | 150 MB | 500 MB+ |

---

## Complete Feature List

### Core Features

| Feature | Description | Status |
|---------|-------------|--------|
| Real-Time Bird Detection | Live feed from smart bird feeders | Stable |
| Species Analytics | Charts and statistics for detected species | Stable |
| Photo Gallery | Browse captured feeder images | Stable |
| Detection History | Complete log of all detections | Stable |
| Field Observations | Manual bird sighting logging | Stable |
| AI Species Identifier | Photo-based bird identification | Stable |
| Birdwatching Timer | Track observation session duration | Stable |
| Data Export | CSV, JSON, and text exports | Stable |
| Offline Mode | Access data without internet | Stable |
| Dark/Light Themes | Customizable appearance | Stable |
| Weather Integration | Current conditions and forecasts | Stable |
| Location Services | GPS-based sighting locations | Stable |
| Community Features | Share posts and sightings | Stable |
| Push Notifications | Alerts for rare species and activity | Stable |
| Home Screen Widget | Quick stats at a glance | Stable |
| Multi-Database Support | Production and development environments | Stable |

### Tools & Utilities

| Tool | Description |
|------|-------------|
| AI Species Identifier | Upload or capture a photo to identify bird species using AI |
| Birdwatching Session Timer | Track how long you've been observing with a floating Dynamic Island-style timer |
| Field Detection Logger | Record manual sightings with full metadata |
| Data Exporter | Export your data in multiple formats |
| My Field Detections | View and manage all your saved observations |
| ChatGPT Integration | Ask questions about birds and get AI-powered answers |

### Analytics & Insights

| Feature | Description |
|---------|-------------|
| Species Distribution Pie Chart | Visual breakdown of detected species |
| Detection Trends | Historical activity patterns |
| Daily/Weekly/Monthly Stats | Time-based analytics |
| Top Species Rankings | Most frequently detected birds |
| Activity Heat Maps | Peak activity times |
| Seasonal Patterns | Migration and seasonal trends |

---

## Detailed Feature Guide

### 1. Dashboard & Home Screen

The main dashboard provides an at-a-glance view of your bird monitoring activity:

- **Detection Counter** - Total birds detected across all sources
- **Species Count** - Number of unique species identified
- **Recent Activity** - Latest detections with timestamps
- **Quick Actions** - Fast access to common features
- **Weather Widget** - Current conditions at your location
- **Trend Indicators** - Activity compared to previous periods

The dashboard automatically refreshes to show real-time data from your connected feeders.

### 2. Real-Time Bird Detection

Ornimetrics connects to smart bird feeder systems to provide live detection data:

- **Live Feed** - See birds as they're detected in real-time
- **Species Identification** - Automatic species classification with confidence scores
- **Photo Capture** - Automatic snapshots of visiting birds
- **Timestamp Logging** - Precise visit times recorded
- **Confidence Scores** - AI certainty levels for each identification
- **Multiple Feeder Support** - Monitor multiple feeders simultaneously

**Supported Integrations:**
- Firebase Realtime Database connections
- Custom API endpoints
- Local network feeders

### 3. Photo Gallery

Browse and manage all captured bird photos:

- **Grid View** - Thumbnail gallery of all photos
- **Full-Screen Viewer** - Detailed photo viewing with zoom
- **Species Tags** - Photos tagged with detected species
- **Date Filtering** - Browse photos by date range
- **Favorites** - Mark and filter favorite captures
- **Share** - Share photos directly to social media
- **Download** - Save photos to your device

Photos are automatically synced from your connected feeders and stored securely in the cloud.

### 4. AI Species Identifier

Don't know what bird you're looking at? Let AI help:

**How It Works:**
1. Tap the AI Identifier tool
2. Take a new photo or select from gallery
3. AI analyzes the image
4. Receive species identification with confidence score
5. View detailed species information

**Features:**
- Multiple AI provider support (ChatGPT, custom endpoints)
- Confidence percentage display
- Scientific name lookup
- Similar species suggestions
- Quick save to field observations
- Offline queue for later processing

### 5. Field Observations

Comprehensive manual logging for birdwatchers:

**Data Captured:**
- Species name and scientific name
- Date and time of observation
- GPS coordinates (automatic or manual)
- Weather conditions (automatic)
- Number of individuals
- Behavior notes (feeding, nesting, singing, etc.)
- Habitat description
- Photo attachments
- Audio recordings (coming soon)
- Custom notes

**Features:**
- Quick-log mode for rapid entries
- Template system for common sightings
- Offline saving with sync when connected
- Per-user data storage (login required)
- Cloud backup and sync

### 6. My Field Detections

View and manage all your saved field observations:

- **Card View** - Beautiful cards showing each observation
- **Photo Display** - Attached photos prominently shown
- **Data Chips** - Quick view of location, weather, AI analysis
- **Detail Sheet** - Full observation details on tap
- **Refresh** - Pull to refresh from cloud
- **User-Specific** - Only shows your observations (login required)
- **Chronological Sorting** - Most recent observations first

### 7. Birdwatching Session Timer

Track your observation sessions with a beautiful floating timer:

**Dynamic Island Timer:**
- Floating pill-shaped timer at top of screen
- Shows elapsed time in HH:MM:SS format
- Pulsing green indicator when active
- Tap to open timer controls
- Persists across app navigation
- Minimalist design that doesn't obstruct content

**Timer Controls:**
- Start/Pause toggle
- Reset function
- Session history (coming soon)
- Export session logs

### 8. Data Export

Export your bird data for analysis or backup:

**Export Formats:**
- **CSV** - Spreadsheet-compatible format for Excel, Google Sheets
- **JSON** - Structured data for developers and analysis tools
- **Text Report** - Human-readable summary document

**Data Included:**
- All detected species
- Detection counts and percentages
- Timestamps and locations
- Weather data
- User observations
- Photo references

**Export Options:**
- Save to device downloads folder
- Share to other apps
- Email as attachment

### 9. Weather Integration

Automatic weather data for your observations:

**Current Conditions:**
- Temperature (Fahrenheit/Celsius)
- Humidity percentage
- Wind speed and direction
- Precipitation
- Cloud cover
- UV index
- Visibility

**Forecasts:**
- Hourly forecast
- 7-day forecast
- Severe weather alerts

**Integration:**
- Automatic location detection
- Manual location override
- Cached for offline access
- Attached to field observations automatically

### 10. Community Features

Connect with fellow bird enthusiasts:

**Community Center:**
- Public post feed
- Share sightings and photos
- Like and comment on posts
- User profiles
- Follow other birders

**Sharing:**
- Share detections to community
- Share to external social media
- Generate shareable links
- Export for citizen science platforms

### 11. Settings & Customization

Personalize your Ornimetrics experience:

**Appearance:**
- Light/Dark theme toggle
- Custom accent colors (seed color selection)
- Font size options
- Compact/expanded layouts

**Notifications:**
- Rare species alerts
- Daily summary
- Activity reminders
- Community updates

**Privacy:**
- Data collection preferences
- AI improvement program opt-in/out
- Location sharing controls
- Export personal data

**Advanced:**
- Database environment selection
- Cache management
- Debug logging
- Reset options

### 12. Offline Mode

Use Ornimetrics even without internet:

**Cached Data:**
- Recent detections
- Species statistics
- Photo thumbnails
- Weather data
- User preferences

**Offline Actions:**
- View cached data
- Log field observations (queued for sync)
- Browse photo gallery
- Use timer features
- View analytics

**Sync Behavior:**
- Automatic sync when connection restored
- Conflict resolution for duplicate entries
- Sync status indicators
- Manual sync option

### 13. Home Screen Widget

Quick stats without opening the app:

**Widget Features:**
- Total detection count
- Species count
- Top detected species
- Last detection time
- Tap to open app

**Customization:**
- Multiple size options
- Theme matching
- Refresh interval settings

### 14. Environment & Habitat Tracking

Detailed environment logging for observations:

- Habitat type selection
- Vegetation description
- Water features nearby
- Elevation data
- Microhabitat notes
- Human activity level
- Noise level assessment

---

## Installation Guide

### Android Installation

#### Method 1: Direct APK Install

1. **Download the APK**
   - Go to the [Releases](https://github.com/TomAs-1226/ornimetrics_app/releases) page
   - Download the appropriate APK for your device

2. **Enable Unknown Sources** (if prompted)
   - Go to Settings → Security
   - Enable "Install unknown apps" for your browser/file manager
   - Or tap "Settings" when prompted during install

3. **Install the APK**
   - Open the downloaded APK file
   - Tap "Install"
   - Wait for installation to complete

4. **Launch Ornimetrics**
   - Find the app in your app drawer
   - Tap to open and begin setup

#### Method 2: ADB Install (Advanced)

```bash
# Connect your device via USB with debugging enabled
adb install ornimetrics-v2.1.0.apk
```

### Updating the App

1. Download the new version APK
2. Install over the existing app (data will be preserved)
3. Or uninstall first for a clean install (data will be lost)

---

## Getting Started

### First Launch

1. **Welcome Screen** - Introduction to Ornimetrics
2. **Permissions** - Grant necessary permissions:
   - Location (for field observations)
   - Camera (for AI identification)
   - Storage (for exports)
3. **Account Setup** - Create account or sign in
4. **Preferences** - Set your preferences:
   - Theme selection
   - Notification preferences
   - Units (metric/imperial)
5. **Tutorial** - Optional walkthrough of features

### Quick Start Guide

1. **View Dashboard** - See your detection overview
2. **Check Photo Gallery** - Browse feeder snapshots
3. **Log an Observation** - Tap Tools → Field Detection
4. **Identify a Bird** - Use AI Species Identifier
5. **Start a Session** - Use the Birdwatching Timer
6. **Export Data** - Tools → Export Data

### Tips for Best Experience

- **Enable Location** - Better field observation data
- **Login** - Required for saving field detections
- **Good Lighting** - Better AI identification results
- **Regular Refresh** - Pull down to refresh data
- **Check Community** - Discover what others are seeing

---

## Privacy & Data

### Data Collection

Ornimetrics collects the following data:

| Data Type | Purpose | Storage |
|-----------|---------|---------|
| Detection Data | Analytics and display | Firebase Cloud |
| Field Observations | User logging | Firebase Cloud (per-user) |
| Photos | Gallery and identification | Firebase Storage |
| Location | Observation mapping | Local + optional cloud |
| Usage Analytics | App improvement | Anonymous, aggregated |

### AI Improvement Program

We offer an optional AI Improvement Program:

**If Opted In:**
- Anonymous detection data helps train AI models
- Improves species identification accuracy
- Contributes to ornithological research
- No personally identifiable information shared

**If Opted Out:**
- No data shared for AI training
- Full functionality retained
- Can change preference anytime

### Your Rights

- **Access** - Export all your data anytime
- **Delete** - Request data deletion
- **Portability** - Data in standard formats
- **Control** - Manage sharing preferences

### Security

- **Encryption** - Data encrypted in transit and at rest
- **Authentication** - Secure Firebase authentication
- **Per-User Isolation** - Users can only access their own data
- **Regular Audits** - Security reviews and updates

---

## Building from Source

### Prerequisites

| Requirement | Version | Notes |
|-------------|---------|-------|
| Flutter SDK | 3.0+ | Latest stable recommended |
| Dart | 3.0+ | Included with Flutter |
| Android Studio | Latest | For Android builds |
| Xcode | 14+ | For iOS builds (macOS only) |
| Git | Latest | For cloning repository |
| Firebase CLI | Latest | For Firebase configuration |

### Clone and Setup

```bash
# Clone the repository
git clone https://github.com/TomAs-1226/ornimetrics_app.git
cd ornimetrics_app

# Install dependencies
flutter pub get

# Verify setup
flutter doctor
```

### Android Build

```bash
# Debug build
flutter build apk --debug

# Release build (universal)
flutter build apk --release

# Release build (split by architecture)
flutter build apk --release --split-per-abi

# App Bundle for Play Store
flutter build appbundle --release
```

**Output Locations:**
- Debug: `build/app/outputs/flutter-apk/app-debug.apk`
- Release: `build/app/outputs/flutter-apk/app-release.apk`
- Split: `build/app/outputs/flutter-apk/app-*-release.apk`
- Bundle: `build/app/outputs/bundle/release/app-release.aab`

### iOS Build

```bash
# Install CocoaPods dependencies
cd ios && pod install && cd ..

# Debug build
flutter build ios --debug

# Release build
flutter build ios --release

# Build IPA
flutter build ipa --release
```

**For Distribution:**
1. Open `ios/Runner.xcworkspace` in Xcode
2. Select Product → Archive
3. In Organizer, click Distribute App
4. Choose distribution method

### Environment Configuration

Create a `.env` file in the project root:

```env
OPENAI_API_KEY=your_api_key_here
WEATHER_API_KEY=your_weather_api_key
```

### Firebase Setup

1. Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com)
2. Add Android and iOS apps
3. Download configuration files:
   - `google-services.json` → `android/app/`
   - `GoogleService-Info.plist` → `ios/Runner/`
4. Run `flutterfire configure` if using FlutterFire CLI

---

## Known Issues

### Current Issues

| Issue | Severity | Workaround | Status |
|-------|----------|------------|--------|
| iOS IPA export fails without Developer account | Low | Build from source in Xcode | In Progress |
| Widget may delay updates on some devices | Low | Open app to force refresh | Investigating |
| AI identification requires internet | Low | Use offline queue | By Design |
| Large exports may timeout | Low | Export in smaller batches | Investigating |

### Reporting Issues

Found a bug? Please report it:

1. Go to [GitHub Issues](https://github.com/TomAs-1226/ornimetrics_app/issues)
2. Click "New Issue"
3. Use the bug report template
4. Include:
   - Device model and Android version
   - Steps to reproduce
   - Expected vs actual behavior
   - Screenshots if applicable
   - Log output if available

---

## Roadmap

### Coming Soon (v2.2.0)

- [ ] Audio recording for bird calls
- [ ] Improved offline support
- [ ] Session history and statistics
- [ ] Enhanced widget customization
- [ ] Migration tracking features

### Future Plans (v3.0.0+)

- [ ] iOS App Store release
- [ ] Apple Watch companion app
- [ ] Wear OS companion app
- [ ] Desktop application (Windows, macOS, Linux)
- [ ] Citizen science platform integrations (eBird, iNaturalist)
- [ ] Advanced AI models for behavior detection
- [ ] Real-time species alerts
- [ ] Collaborative birding sessions
- [ ] Multi-language support
- [ ] Accessibility improvements

### Feature Requests

Have an idea? We'd love to hear it:

1. Go to [GitHub Issues](https://github.com/TomAs-1226/ornimetrics_app/issues)
2. Click "New Issue"
3. Select "Feature Request" template
4. Describe your idea in detail

---

## Support & Feedback

### Getting Help

| Resource | Link | Description |
|----------|------|-------------|
| GitHub Issues | [Issues](https://github.com/TomAs-1226/ornimetrics_app/issues) | Bug reports and feature requests |
| Discussions | [Discussions](https://github.com/TomAs-1226/ornimetrics_app/discussions) | Community Q&A |
| Wiki | [Wiki](https://github.com/TomAs-1226/ornimetrics_app/wiki) | Documentation and guides |

### Contributing

Contributions are welcome! Please read our contributing guidelines before submitting pull requests.

**Ways to Contribute:**
- Report bugs
- Suggest features
- Improve documentation
- Submit pull requests
- Help with translations
- Share with fellow birders

---

## Credits & Acknowledgments

### Development

- **Lead Developer** - Thomas Yu
- **AI Integration** - OpenAI API, ChatGPT
- **Backend** - Firebase (Realtime Database, Storage, Auth)

### Technologies

| Technology | Purpose |
|------------|---------|
| Flutter | Cross-platform UI framework |
| Dart | Programming language |
| Firebase | Backend services |
| OpenAI | AI species identification |
| Geolocator | Location services |
| Image Picker | Photo capture |

### Open Source Libraries

This app is built with the following open source packages:

- `firebase_core` - Firebase initialization
- `firebase_auth` - User authentication
- `firebase_database` - Realtime database
- `firebase_storage` - Cloud storage
- `flutter_dotenv` - Environment variables
- `geolocator` - GPS location
- `http` - Network requests
- `image_picker` - Camera and gallery
- `intl` - Internationalization
- `pie_chart` - Data visualization
- `shared_preferences` - Local storage
- `file_selector` - File operations

### Special Thanks

- The Flutter team for an amazing framework
- Firebase for robust backend services
- The birdwatching community for inspiration
- All beta testers and early adopters
- Open source contributors worldwide

---

## License

Ornimetrics is released under the MIT License.

See the [LICENSE](LICENSE) file for full details.

```
MIT License

Copyright (c) 2024 Thomas Yu

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## Changelog

### Version 2.1.0 (Current Release - December 2024)

**This is the first public release of Ornimetrics!**

#### New Features
- **AI Species Identifier** - Identify birds from photos using AI integration with support for multiple providers
- **Field Observations System** - Comprehensive manual bird sighting logging with location, weather, and behavioral notes
- **My Field Detections** - View all your saved observations with photos, data chips, and detailed views
- **Dynamic Island Timer** - Beautiful floating birdwatching session timer that persists across navigation
- **Data Export System** - Export your data as CSV, JSON, or text reports with file save dialogs
- **Photo Gallery** - Browse all feeder snapshots with species detection information
- **Offline Caching** - Access your data even without an internet connection
- **Home Screen Widget** - Quick stats widget for Android home screens
- **Community Center** - Share posts and connect with fellow birders
- **Notification System** - Alerts for rare species and activity summaries

#### Core Features (First Release)
- Real-time bird detection from smart feeders
- Species analytics with pie charts and trends
- Weather integration with automatic conditions logging
- Firebase cloud sync for all data
- User authentication with per-user data isolation
- Light and dark theme support with custom accent colors
- Haptic feedback throughout the app
- Comprehensive settings and preferences

#### Technical
- Built with Flutter 3.x and Dart 3.x
- Firebase Realtime Database for cloud storage
- Firebase Authentication for user management
- Firebase Storage for photo storage
- Geolocator for GPS positioning
- OpenAI integration for AI features

#### Known Issues
- iOS App Store release pending (Developer Program enrollment in progress)
- Some AI features require API key configuration
- Widget updates may be delayed on certain Android devices

---

### Version History

| Version | Date | Highlights |
|---------|------|------------|
| 2.1.0 | Dec 2024 | First public release with AI identification, field observations, exports |
| 2.0.0 | Nov 2024 | Major refactor, Firebase integration, community features |
| 1.x | 2024 | Internal development builds |

---

## Appendix

### File Checksums (SHA256)

Verify your download integrity:

```
SHA256 (ornimetrics-v2.1.0.apk) = [TO BE ADDED AFTER BUILD]
SHA256 (ornimetrics-v2.1.0-arm64-v8a.apk) = [TO BE ADDED AFTER BUILD]
SHA256 (ornimetrics-v2.1.0-armeabi-v7a.apk) = [TO BE ADDED AFTER BUILD]
SHA256 (ornimetrics-v2.1.0-x86_64.apk) = [TO BE ADDED AFTER BUILD]
```

### Permissions Explained

| Permission | Android Name | Why We Need It |
|------------|--------------|----------------|
| Internet | `android.permission.INTERNET` | Cloud sync, AI features, weather data |
| Location | `android.permission.ACCESS_FINE_LOCATION` | GPS coordinates for field observations |
| Camera | `android.permission.CAMERA` | Photo capture for AI identification |
| Storage | `android.permission.WRITE_EXTERNAL_STORAGE` | Save exported files |
| Network State | `android.permission.ACCESS_NETWORK_STATE` | Offline mode detection |

### API Rate Limits

| Service | Limit | Reset |
|---------|-------|-------|
| AI Identification | 50/day (free tier) | Daily |
| Weather API | 1000/day | Daily |
| Firebase | Generous free tier | N/A |

---

**Thank you for choosing Ornimetrics!**

*Happy Birdwatching!* 🐦

---

*Last updated: December 2024*
*Documentation version: 2.1.0*
