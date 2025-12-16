import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/community_models.dart';
import '../models/weather_models.dart';

class CommunityService {
  CommunityService({this.testMode = true});

  bool testMode;

  final List<CommunityPost> _localPosts = <CommunityPost>[];

  CollectionReference<Map<String, dynamic>> get _collection => FirebaseFirestore.instance
      .collection(testMode ? 'community_posts_test' : 'community_posts');

  Future<User?> signIn(String email, String password) async {
    final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
    return cred.user;
  }

  Future<User?> signUp(String email, String password) async {
    final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
    return cred.user;
  }

  Future<void> toggleTestMode(bool enabled) async {
    testMode = enabled;
  }

  Future<List<CommunityPost>> fetchPosts() async {
    if (testMode) {
      return List<CommunityPost>.from(_localPosts.reversed);
    }
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
    if (testMode) {
      _localPosts.add(CommunityPost(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        author: author,
        caption: caption,
        imageUrl: null,
        createdAt: DateTime.now(),
        timeOfDayTag: _timeOfDayFor(DateTime.now()),
        sensors: sensors,
        model: model,
        weather: weather,
      ));
      return;
    }

    String? uploadedUrl;
    if (photo != null) {
      final ref = FirebaseStorage.instance
          .ref()
          .child((testMode ? 'community_posts_test' : 'community_posts'))
          .child('${DateTime.now().millisecondsSinceEpoch}_${photo.path.split('/').last}');
      final task = await ref.putFile(photo);
      uploadedUrl = await task.ref.getDownloadURL();
    }

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
