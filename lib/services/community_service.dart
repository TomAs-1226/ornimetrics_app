import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

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

  Future<void> logDiagnostics() async {
    try {
      final rootSnap = await FirebaseDatabase.instance.ref().get();
      final keys = rootSnap.children.map((c) => c.key).toList();
      // ignore: avoid_print
      print('[community_posts] root keys: $keys');
      final postsSnap = await FirebaseDatabase.instance.ref('community_posts').get();
      // ignore: avoid_print
      print('[community_posts] exists=${postsSnap.exists} children=${postsSnap.children.length} valueType=${postsSnap.value.runtimeType}');
    } catch (e) {
      // ignore: avoid_print
      print('[community_posts] diagnostics failed: $e');
    }
  }

  List<CommunityPost> _parsePosts(DataSnapshot snap) {
    final List<CommunityPost> posts = [];
    // Prefer children iteration (works for ordered queries).
    if (snap.children.isNotEmpty) {
      for (final child in snap.children) {
        final value = child.value;
        if (value is Map) {
          final normalized = Map<String, dynamic>.from(
            value.map((k, v) => MapEntry(k.toString(), v)),
          );
          posts.add(CommunityPost.fromRealtime(child.key ?? '', normalized));
        } else {
          // ignore: avoid_print
          print('community_posts parse skipped: key=${child.key}, type=${value.runtimeType}');
        }
      }
    } else if (snap.value is Map) {
      // Fallback to map iteration if children list is empty.
      final data = Map<dynamic, dynamic>.from(snap.value as Map);
      data.forEach((key, value) {
        if (value is Map) {
          final normalized = Map<String, dynamic>.from(
            value.map((k, v) => MapEntry(k.toString(), v)),
          );
          posts.add(CommunityPost.fromRealtime(key.toString(), normalized));
        } else {
          // ignore: avoid_print
          print('community_posts parse skipped: key=$key, type=${value.runtimeType}');
        }
      });
    } else if (snap.value is List) {
      final list = List<dynamic>.from(snap.value as List);
      for (int i = 0; i < list.length; i++) {
        final value = list[i];
        if (value is Map) {
          final normalized = Map<String, dynamic>.from(
            value.map((k, v) => MapEntry(k.toString(), v)),
          );
          posts.add(CommunityPost.fromRealtime(i.toString(), normalized));
        } else {
          // ignore: avoid_print
          print('community_posts parse skipped: index=$i, type=${value.runtimeType}');
        }
      }
    }
    return posts;
  }

  Future<List<CommunityPost>> fetchPosts() async {
    try {
      DataSnapshot snap;
      try {
        snap = await _ref.orderByChild('created_at').get();
      } on FirebaseException catch (e) {
        // If the index is missing, fall back to plain fetch and sort client-side.
        if (e.message != null && e.message!.contains('indexOn')) {
          snap = await _ref.get();
        } else {
          rethrow;
        }
      }

      List<CommunityPost> posts = _parsePosts(snap);

      // If ordered query returned no children but data exists, try a plain get.
      if (posts.isEmpty && snap.value != null) {
        try {
          final plain = await _ref.get();
          posts = _parsePosts(plain);
        } catch (_) {}
      }

      posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (posts.isNotEmpty) {
        final newest = posts.first.createdAt.toIso8601String();
        final oldest = posts.last.createdAt.toIso8601String();
        // ignore: avoid_print
        print('[community_posts] loaded ${posts.length} posts (newest: $newest, oldest: $oldest)');
      } else {
        // ignore: avoid_print
        print('[community_posts] loaded 0 posts');
      }

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

  Stream<List<CommunityPost>> watchCommunityPosts({int limit = 50}) {
    final query = _ref.orderByChild('created_at').limitToLast(limit);
    return query.onValue.asyncMap((event) async {
      final snap = event.snapshot;
      if (snap.children.length > 100) {
        return compute(_computeParsePosts, _SerializableSnapshot.fromSnapshot(snap));
      }
      final posts = _parsePosts(snap)..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return posts;
    });
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

class _SerializableSnapshot {
  _SerializableSnapshot(this.children);
  final List<Map<String, dynamic>> children;

  factory _SerializableSnapshot.fromSnapshot(DataSnapshot snap) {
    final List<Map<String, dynamic>> out = [];
    for (final child in snap.children) {
      if (child.value is Map) {
        final m = Map<String, dynamic>.from(
          (child.value as Map).map((k, v) => MapEntry(k.toString(), v)),
        );
        m['_id'] = child.key;
        out.add(m);
      }
    }
    return _SerializableSnapshot(out);
  }
}

List<CommunityPost> _computeParsePosts(_SerializableSnapshot serial) {
  final posts = <CommunityPost>[];
  for (final m in serial.children) {
    final id = (m['_id'] ?? '').toString();
    final copy = Map<String, dynamic>.from(m)..remove('_id');
    posts.add(CommunityPost.fromRealtime(id, copy));
  }
  posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return posts;
}