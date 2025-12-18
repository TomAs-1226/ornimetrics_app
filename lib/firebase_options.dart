// This file should be regenerated with `flutterfire configure` so that it
// exactly matches your google-services.json / GoogleService-Info.plist.
// Do NOT hand-edit production keys; placeholder values are included to ensure
// the app fails fast if you forget to configure Firebase properly.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

// Replace these placeholder strings by running `flutterfire configure`.
// If you keep the placeholders, _ensureFirebaseInitialized in main.dart will
// throw a descriptive error to avoid mysterious Auth failures.
const String _androidApiKey = 'REPLACE_ME_ANDROID_API_KEY';
const String _androidAppId = 'REPLACE_ME_ANDROID_APP_ID';
const String _webApiKey = 'REPLACE_ME_WEB_API_KEY';
const String _webAppId = 'REPLACE_ME_WEB_APP_ID';
const String _iosApiKey = 'REPLACE_ME_IOS_API_KEY';
const String _iosAppId = 'REPLACE_ME_IOS_APP_ID';
const String _macApiKey = 'REPLACE_ME_MACOS_API_KEY';
const String _macAppId = 'REPLACE_ME_MACOS_APP_ID';
const String _windowsApiKey = 'REPLACE_ME_WINDOWS_API_KEY';
const String _windowsAppId = 'REPLACE_ME_WINDOWS_APP_ID';
const String _projectId = 'REPLACE_ME_PROJECT_ID';
const String _storageBucket = 'REPLACE_ME_STORAGE_BUCKET';
const String _messagingSenderId = 'REPLACE_ME_SENDER_ID';
const String _databaseURL = 'https://REPLACE_ME_PROJECT_ID-default-rtdb.firebaseio.com';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return FirebaseOptions(
          apiKey: _androidApiKey,
          appId: _androidAppId,
          messagingSenderId: _messagingSenderId,
          projectId: _projectId,
          storageBucket: _storageBucket,
          databaseURL: _databaseURL,
        );
      case TargetPlatform.iOS:
        return FirebaseOptions(
          apiKey: _iosApiKey,
          appId: _iosAppId,
          messagingSenderId: _messagingSenderId,
          projectId: _projectId,
          storageBucket: _storageBucket,
          iosBundleId: 'com.example.ornimetricsApp',
          databaseURL: _databaseURL,
        );
      case TargetPlatform.macOS:
        return FirebaseOptions(
          apiKey: _macApiKey,
          appId: _macAppId,
          messagingSenderId: _messagingSenderId,
          projectId: _projectId,
          storageBucket: _storageBucket,
          iosBundleId: 'com.example.ornimetricsApp',
          databaseURL: _databaseURL,
        );
      case TargetPlatform.windows:
        return FirebaseOptions(
          apiKey: _windowsApiKey,
          appId: _windowsAppId,
          messagingSenderId: _messagingSenderId,
          projectId: _projectId,
          storageBucket: _storageBucket,
        );
      default:
        return FirebaseOptions(
          apiKey: _webApiKey,
          appId: _webAppId,
          messagingSenderId: _messagingSenderId,
          projectId: _projectId,
          storageBucket: _storageBucket,
          authDomain: '$_projectId.firebaseapp.com',
          measurementId: 'REPLACE_ME_MEASUREMENT_ID',
        );
    }
  }
}
