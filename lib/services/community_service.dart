import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../firebase_options.dart';
import '../models/community_models.dart';
import '../models/weather_models.dart';
import 'community_storage_service.dart';

class CommunityService {
  CommunityService({CommunityStorageService? storage}) : _storage = storage ?? CommunityStorageService();

  final CommunityStorageService _storage;
  DatabaseReference get _ref => _db.ref('community_posts');
  FirebaseDatabase get _db => FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: DefaultFirebaseOptions.currentPlatform.databaseURL,
      );

  Future<User?> signIn(String email, String password) async {
    final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
    return cred.user;
  }

  Future<User?> signUp(String email, String password) async {
    final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
    return cred.user;
  }

  Future<List<CommunityPost>> fetchPosts() async {
    DataSnapshot snap;
    try {
      snap = await _ref.orderByChild('created_at').limitToLast(50).get();
    } catch (_) {
      // Fallback if the index is missing or ordering fails; still return recent items.
      snap = await _ref.limitToLast(50).get();
    }
    if (snap.value == null) return [];

    final List<CommunityPost> posts = [];
    if (snap.value is Map) {
      final data = Map<dynamic, dynamic>.from(snap.value as Map);
      data.forEach((key, value) {
        if (value is Map) {
          posts.add(CommunityPost.fromRealtime(key.toString(), Map<dynamic, dynamic>.from(value)));
        }
      });
    } else if (snap.value is List) {
      final list = List<dynamic>.from(snap.value as List);
      for (final value in list) {
        if (value is Map) {
          posts.add(CommunityPost.fromRealtime(posts.length.toString(), Map<dynamic, dynamic>.from(value)));
        }
      }
    }

    posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return posts;
  }

  Future<void> createPost({
    required String caption,
    File? photo,
    required String author,
    required SensorSnapshot sensors,
    WeatherSnapshot? weather,
    String model = 'Ornimetrics O1 feeder',
  }) async {
    final sanitizedCaption = caption.trim();
    if (sanitizedCaption.isEmpty && photo == null) {
      throw FirebaseException(
        plugin: 'community_service',
        code: 'invalid-argument',
        message: 'Add a caption or photo before posting.',
      );
    }

    await FirebaseAuth.instance.currentUser?.reload();
    String? uploadedUrl;
    if (photo != null) {
      uploadedUrl = await _storage.uploadCommunityPhoto(file: photo, uid: FirebaseAuth.instance.currentUser?.uid ?? 'anonymous');
    }

    try {
      final payload = CommunityPost(
        id: 'pending',
        author: author.trim().isEmpty ? 'community member' : author.trim(),
        caption: sanitizedCaption,
        imageUrl: uploadedUrl,
        createdAt: DateTime.now(),
        timeOfDayTag: _timeOfDayFor(DateTime.now()),
        sensors: sensors,
        model: model,
        weather: weather,
      ).toMap()
        ..removeWhere((key, value) => value == null);

      final newRef = _ref.push();
      await newRef.set(payload);
    } on FirebaseException catch (e) {
      throw FirebaseException(
        plugin: e.plugin == 'cloud_firestore' ? 'firebase_database' : e.plugin,
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
