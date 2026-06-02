#!/bin/bash
# =============================================================================
# Ornimetrics - Flutter Update & Android Emulator Setup Script
# Run this on your LOCAL machine (not in a sandbox)
# =============================================================================

set -e

echo "============================================"
echo "  Ornimetrics - Update & Setup Script"
echo "============================================"
echo ""

# ─── 1. Update Flutter SDK to Latest Stable ─────────────────────────────────
echo ">>> Step 1: Updating Flutter SDK to latest stable..."
flutter channel stable
flutter upgrade
echo ""
echo ">>> Flutter version after upgrade:"
flutter --version
echo ""

# ─── 2. Run Flutter Doctor ───────────────────────────────────────────────────
echo ">>> Step 2: Running flutter doctor..."
flutter doctor -v
echo ""

# ─── 3. Get Dependencies ────────────────────────────────────────────────────
echo ">>> Step 3: Getting pub dependencies..."
cd "$(dirname "$0")/.."
flutter pub get
echo ""

# ─── 4. Check for Outdated Packages ─────────────────────────────────────────
echo ">>> Step 4: Checking for outdated packages..."
flutter pub outdated || true
echo ""

# ─── 5. Clean & Rebuild ─────────────────────────────────────────────────────
echo ">>> Step 5: Cleaning build cache..."
flutter clean
flutter pub get
echo ""

# ─── 6. Android SDK Setup ───────────────────────────────────────────────────
echo ">>> Step 6: Installing Android SDK components for API 36..."
SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
if [ ! -f "$SDKMANAGER" ]; then
    SDKMANAGER="$ANDROID_HOME/tools/bin/sdkmanager"
fi

if [ -f "$SDKMANAGER" ]; then
    echo "y" | "$SDKMANAGER" "platforms;android-36"
    echo "y" | "$SDKMANAGER" "build-tools;36.0.0"
    echo "y" | "$SDKMANAGER" "system-images;android-36;google_apis;x86_64"
    echo "y" | "$SDKMANAGER" "emulator"
    echo "y" | "$SDKMANAGER" "platform-tools"
    echo ""
    echo ">>> Android SDK components installed."
else
    echo "WARNING: sdkmanager not found at expected path."
    echo "Please install Android SDK command-line tools via Android Studio:"
    echo "  Android Studio → Settings → SDK Manager → SDK Tools → Android SDK Command-line Tools"
    echo ""
    echo "Then run these commands manually:"
    echo "  sdkmanager 'platforms;android-36'"
    echo "  sdkmanager 'build-tools;36.0.0'"
    echo "  sdkmanager 'system-images;android-36;google_apis;x86_64'"
fi
echo ""

# ─── 7. Create Android Emulator ─────────────────────────────────────────────
echo ">>> Step 7: Creating Android emulator (Pixel 7, API 36)..."
AVDMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager"
if [ ! -f "$AVDMANAGER" ]; then
    AVDMANAGER="$ANDROID_HOME/tools/bin/avdmanager"
fi

EMULATOR_NAME="Ornimetrics_Pixel7_API35"

if [ -f "$AVDMANAGER" ]; then
    # Delete existing AVD if it exists
    "$AVDMANAGER" delete avd -n "$EMULATOR_NAME" 2>/dev/null || true

    # Create new AVD
    echo "no" | "$AVDMANAGER" create avd \
        -n "$EMULATOR_NAME" \
        -k "system-images;android-36;google_apis;x86_64" \
        -d "pixel_7" \
        --force

    echo ""
    echo ">>> Emulator '$EMULATOR_NAME' created successfully!"
    echo ""
    echo ">>> To launch the emulator, run:"
    echo "    $ANDROID_HOME/emulator/emulator -avd $EMULATOR_NAME"
    echo ""
    echo ">>> Or from Android Studio: Tools → Device Manager → Start"
else
    echo "WARNING: avdmanager not found."
    echo "Create the emulator manually in Android Studio:"
    echo "  Tools → Device Manager → Create Virtual Device"
    echo "  Choose: Pixel 7 → Android 15 (API 36) → x86_64 image"
fi
echo ""

# ─── 8. Build APK to Verify ─────────────────────────────────────────────────
echo ">>> Step 8: Building debug APK to verify everything works..."
flutter build apk --debug
echo ""

echo "============================================"
echo "  Setup Complete!"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Start the emulator:  flutter emulators --launch $EMULATOR_NAME"
echo "  2. Run the app:         flutter run"
echo "  3. Record screen clips for video (see video_capture_guide.md)"
echo ""
