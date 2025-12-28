import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

FirebaseOptions _optionsForPlatform(String platform) {
  String? pick(String key) => dotenv.env['FIREBASE_${platform}_$key'] ?? dotenv.env['FIREBASE_$key'];

  final apiKey = pick('API_KEY');
  final appId = pick('APP_ID');
  final messagingSenderId = dotenv.env['FIREBASE_MESSAGING_SENDER_ID'];
  final projectId = dotenv.env['FIREBASE_PROJECT_ID'];
  final storageBucket = dotenv.env['FIREBASE_STORAGE_BUCKET'];
  final databaseURL = dotenv.env['FIREBASE_DATABASE_URL'];

  final missing = <String>[
    if (apiKey == null || apiKey.isEmpty) 'FIREBASE_${platform}_API_KEY',
    if (appId == null || appId.isEmpty) 'FIREBASE_${platform}_APP_ID',
    if (messagingSenderId == null || messagingSenderId.isEmpty) 'FIREBASE_MESSAGING_SENDER_ID',
    if (projectId == null || projectId.isEmpty) 'FIREBASE_PROJECT_ID',
    if (storageBucket == null || storageBucket.isEmpty) 'FIREBASE_STORAGE_BUCKET',
  ];

  if (missing.isNotEmpty) {
    throw StateError(
      'Missing Firebase environment variables (${missing.join(', ')}). '
      'Populate .env or run scripts/bootstrap_firebase.sh to generate firebase_options.dart.',
    );
  }

  return FirebaseOptions(
    apiKey: apiKey!,
    appId: appId!,
    messagingSenderId: messagingSenderId!,
    projectId: projectId!,
    storageBucket: storageBucket!,
    databaseURL: databaseURL,
  );
}

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _optionsForPlatform('ANDROID');
      case TargetPlatform.iOS:
        return _optionsForPlatform('IOS');
      case TargetPlatform.macOS:
        return _optionsForPlatform('MACOS');
      case TargetPlatform.windows:
        return _optionsForPlatform('WINDOWS');
      default:
        return _optionsForPlatform('WEB');
    }
  }
}
