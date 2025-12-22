import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../firebase_options.dart';

class CommunityStorageService {
  CommunityStorageService._(this._storage);

  final FirebaseStorage _storage;

  static CommunityStorageService? _instance;

  factory CommunityStorageService() {
    if (_instance != null) return _instance!;

    final overrideBucket = dotenv.env['COMMUNITY_STORAGE_BUCKET'];
    final defaultBucket = DefaultFirebaseOptions.currentPlatform.storageBucket;
    final chosenBucket = (overrideBucket != null && overrideBucket.isNotEmpty) ? overrideBucket : defaultBucket;

    _instance = CommunityStorageService._(
      FirebaseStorage.instanceFor(bucket: chosenBucket),
    );
    return _instance!;
  }

  Future<String> uploadCommunityPhoto({required File file, required String uid}) async {
    final filename = file.path.split('/').last;
    final ref = _storage.ref().child('community_posts/$uid/${DateTime.now().millisecondsSinceEpoch}_$filename');
    final task = await ref.putFile(file);
    return task.ref.getDownloadURL();
  }
}
