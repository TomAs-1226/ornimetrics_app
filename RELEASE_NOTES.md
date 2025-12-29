# Ornimetrics App v2.1.0

**Your Personal Bird Watching & Feeder Monitoring Companion**

---

## Download

### Android
| Variant | Download | Description |
|---------|----------|-------------|
| Universal APK | [ornimetrics-v2.1.0.apk](https://github.com/TomAs-1226/ornimetrics_app/releases/download/v2.1.0/ornimetrics-v2.1.0.apk) | Works on all Android devices |
| ARM64 | [ornimetrics-v2.1.0-arm64-v8a.apk](https://github.com/TomAs-1226/ornimetrics_app/releases/download/v2.1.0/ornimetrics-v2.1.0-arm64-v8a.apk) | Most modern phones (smaller size) |
| ARM32 | [ornimetrics-v2.1.0-armeabi-v7a.apk](https://github.com/TomAs-1226/ornimetrics_app/releases/download/v2.1.0/ornimetrics-v2.1.0-armeabi-v7a.apk) | Older Android devices |

### iOS
> **Status: Work in Progress**
>
> The iOS version is currently under development for App Store release. We're working on obtaining the necessary Apple Developer certificates and provisioning profiles.
>
> **ETA:** Coming Soon
>
> If you're an iOS developer and want to build from source, see the [Building from Source](#building-from-source) section below.

---

## What's New in v2.1.0

### New Features
- **AI Species Identifier** - Identify birds from photos using AI integration
- **Field Observations** - Log bird sightings with location, weather, and notes
- **My Field Detections** - View all your saved observations with photos and data
- **Dynamic Island Timer** - Floating birdwatching session timer overlay
- **Data Export** - Export your data as CSV, JSON, or text reports
- **Photo Gallery** - View all feeder snapshots with species detection
- **Offline Caching** - Access your data even without internet

### Improvements
- Enhanced Terms of Service with comprehensive data policies
- Expanded AI Improvement Program with transparency details
- Better error handling for Firebase data operations
- QOL improvements throughout the app
- Improved haptic feedback system

### Bug Fixes
- Fixed field detections not saving properly
- Fixed timer display method errors
- Removed unused package dependencies
- Fixed various type casting issues

---

## Installation (Android)

### Option 1: Direct Download
1. Download the APK file from the links above
2. Open the downloaded file on your Android device
3. If prompted, enable "Install from unknown sources" in Settings
4. Follow the installation prompts

### Option 2: QR Code
*(Add QR code image linking to release)*

### Requirements
- Android 5.0 (API 21) or higher
- ~50 MB storage space
- Internet connection for cloud features
- Location permissions (optional, for field observations)
- Camera permissions (optional, for AI species identification)

---

## Building from Source

### Prerequisites
- Flutter SDK 3.0+
- Android Studio / Xcode
- Firebase project configured

### Android
```bash
git clone https://github.com/TomAs-1226/ornimetrics_app.git
cd ornimetrics_app
flutter pub get
flutter build apk --release
```

### iOS (macOS required)
```bash
git clone https://github.com/TomAs-1226/ornimetrics_app.git
cd ornimetrics_app
flutter pub get
cd ios && pod install && cd ..
flutter build ios --release
# Open ios/Runner.xcworkspace in Xcode to archive
```

---

## Permissions

| Permission | Purpose | Required |
|------------|---------|----------|
| Internet | Sync data, AI features | Yes |
| Camera | AI species identification | Optional |
| Location | Field observation logging | Optional |
| Storage | Export data files | Optional |

---

## Known Issues

- iOS App Store release pending Apple Developer enrollment
- Some AI features require API key configuration
- Widget may not update immediately on some Android devices

---

## Feedback & Support

- **Issues:** [GitHub Issues](https://github.com/TomAs-1226/ornimetrics_app/issues)
- **Feature Requests:** Open an issue with the `enhancement` label

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Acknowledgments

- Bird detection powered by AI
- Weather data integration
- Firebase for real-time data sync
- Flutter community

---

*Happy Birdwatching!*
