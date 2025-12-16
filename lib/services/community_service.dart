import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class CommunityPost {
  final String id;
  final String author;
  final String caption;
  final String? imageUrl;
  final DateTime createdAt;

  CommunityPost({
    required this.id,
    required this.author,
    required this.caption,
    required this.createdAt,
    this.imageUrl,
  });
}

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
    return snap.docs.map((d) {
      final data = d.data();
      return CommunityPost(
        id: d.id,
        author: data['author']?.toString() ?? 'anon',
        caption: data['caption']?.toString() ?? '',
        imageUrl: data['image_url']?.toString(),
        createdAt: (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
    }).toList();
  }

  Future<void> createPost({required String caption, File? photo, required String author}) async {
    if (testMode) {
      _localPosts.add(CommunityPost(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        author: author,
        caption: caption,
        imageUrl: null,
        createdAt: DateTime.now(),
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
      'author': author,
      'caption': caption,
      'image_url': uploadedUrl,
      'created_at': FieldValue.serverTimestamp(),
    });
  }
}
