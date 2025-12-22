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

  List<CommunityPost> _parsePosts(DataSnapshot snap) {
    final List<CommunityPost> posts = [];
    // Prefer children iteration (works for ordered queries).
    if (snap.children.isNotEmpty) {
      for (final child in snap.children) {
        final value = child.value;
        if (value is Map) {
          posts.add(CommunityPost.fromRealtime(child.key ?? '', Map<dynamic, dynamic>.from(value)));
        }
      }
    } else if (snap.value is Map) {
      // Fallback to map iteration if children list is empty.
      final data = Map<dynamic, dynamic>.from(snap.value as Map);
      data.forEach((key, value) {
        if (value is Map) {
          posts.add(CommunityPost.fromRealtime(key.toString(), Map<dynamic, dynamic>.from(value)));
        }
      });
    } else if (snap.value is List) {
      final list = List<dynamic>.from(snap.value as List);
      for (int i = 0; i < list.length; i++) {
        final value = list[i];
        if (value is Map) {
          posts.add(CommunityPost.fromRealtime(i.toString(), Map<dynamic, dynamic>.from(value)));
        }
      }
    }
    return posts;
  }

  Future<List<CommunityPost>> fetchPosts() async {
    try {
      // Plain fetch avoids index errors; we'll sort client-side.
      final snap = await _ref.get();
      List<CommunityPost> posts = _parsePosts(snap);

      // Fallback if the snapshot has a map but no children iteration.
      if (posts.isEmpty && snap.value != null) {
        try {
          final plain = await _ref.orderByKey().get();
          posts = _parsePosts(plain);
        } catch (_) {}
      }

      posts.sort((a, b) {
        // If created_at is missing for any reason, fall back to key ordering.
        final cmp = b.createdAt.compareTo(a.createdAt);
        if (cmp != 0) return cmp;
        return b.id.compareTo(a.id);
      });

      // Keep only the newest 100 to cap UI churn.
      if (posts.length > 100) {
        posts = posts.take(100).toList();
      }

      return posts;
    } catch (e) {
      throw FirebaseException(
        plugin: 'firebase_database',
        code: 'community_fetch_failed',
        message: e.toString(),
      );
    }
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
