import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/community_models.dart';
import '../models/weather_models.dart';
import 'community_storage_service.dart';

class CommunityService {
  CommunityService({CommunityStorageService? storage}) : _storage = storage ?? CommunityStorageService();

  final CommunityStorageService _storage;
  CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('community_posts');

  Future<User?> signIn(String email, String password) async {
    final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
    return cred.user;
  }

  Future<User?> signUp(String email, String password) async {
    final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
    return cred.user;
  }

  Future<List<CommunityPost>> fetchPosts() async {
    final snap = await _collection.orderBy('created_at', descending: true).limit(50).get();
    return snap.docs.map((d) => CommunityPost.fromFirestore(d)).toList();
  }

  Future<void> createPost({
    required String caption,
    File? photo,
    required String author,
    required SensorSnapshot sensors,
    WeatherSnapshot? weather,
    String model = 'Ornimetrics O1 feeder',
  }) async {
    String? uploadedUrl;
    if (photo != null) {
      uploadedUrl = await _storage.uploadCommunityPhoto(file: photo, uid: FirebaseAuth.instance.currentUser?.uid ?? 'anonymous');
    }

    try {
      await _collection.add({
        ...CommunityPost(
          id: 'pending',
          author: author,
          caption: caption,
          imageUrl: uploadedUrl,
          createdAt: DateTime.now(),
          timeOfDayTag: _timeOfDayFor(DateTime.now()),
          sensors: sensors,
          model: model,
          weather: weather,
        ).toMap(),
      });
    } on FirebaseException catch (e) {
      throw FirebaseException(
        plugin: e.plugin,
        code: e.code,
        message: e.code == 'permission-denied'
            ? 'You are not allowed to post to the community bucket. Check Storage rules and bucket ID.'
            : e.message,
      );
    }
  }

  String _timeOfDayFor(DateTime dt) {
    final hour = dt.hour;
    if (hour < 6) return 'night';
    if (hour < 12) return 'morning';
    if (hour < 17) return 'afternoon';
    if (hour < 21) return 'evening';
    return 'night';
  }
}
