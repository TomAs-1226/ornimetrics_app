import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/community_service.dart';

class CommunityCenterScreen extends StatefulWidget {
  const CommunityCenterScreen({super.key});

  @override
  State<CommunityCenterScreen> createState() => _CommunityCenterScreenState();
}

class _CommunityCenterScreenState extends State<CommunityCenterScreen> {
  late CommunityService _service;
  bool _testMode = true;
  bool _loading = false;
  String _status = '';
  List<CommunityPost> _posts = <CommunityPost>[];
  final _captionController = TextEditingController();
  File? _photo;

  @override
  void initState() {
    super.initState();
    _service = CommunityService(testMode: _testMode);
    _loadPrefs();
    _refresh();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool('pref_community_test') ?? true;
    setState(() => _testMode = saved);
    _service.testMode = saved;
  }

  Future<void> _refresh() async {
    try {
      final res = await _service.fetchPosts();
      setState(() => _posts = res);
    } catch (e) {
      setState(() => _status = e.toString());
    }
  }

  Future<void> _loginOrSignUp() async {
    final emailController = TextEditingController();
    final passController = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Community Login'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email')),
            TextField(
              controller: passController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              try {
                await _service.signIn(emailController.text, passController.text);
              } catch (_) {
                await _service.signUp(emailController.text, passController.text);
              }
              if (mounted) Navigator.pop(context);
              setState(() {});
            },
            child: const Text('Continue'),
          )
        ],
      ),
    );
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final res = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1200);
    if (res != null) setState(() => _photo = File(res.path));
  }

  Future<void> _createPost() async {
    final user = FirebaseAuth.instance.currentUser;
    if (!_testMode && user == null) {
      setState(() => _status = 'Please login first.');
      return;
    }
    setState(() {
      _loading = true;
      _status = '';
    });
    try {
      await _service.createPost(
        caption: _captionController.text.trim(),
        photo: _photo,
        author: (user?.email ?? 'test-user'),
      );
      _captionController.clear();
      _photo = null;
      await _refresh();
      setState(() => _status = 'Posted successfully');
    } catch (e) {
      setState(() => _status = 'Upload failed: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleTestMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pref_community_test', value);
    await _service.toggleTestMode(value);
    setState(() => _testMode = value);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Community Center', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('Share feeder stories + bird photos'),
                ],
              ),
              const Spacer(),
              IconButton(onPressed: _loginOrSignUp, icon: const Icon(Icons.login)),
            ],
          ),
          SwitchListTile(
            title: const Text('Community Test Mode'),
            subtitle: const Text('Keeps writes in memory / test collection so permissions are safe.'),
            value: _testMode,
            onChanged: _toggleTestMode,
          ),
          if (!_testMode)
            ListTile(
              leading: const Icon(Icons.verified_user),
              title: Text(user != null ? 'Signed in as ${user.email}' : 'Not signed in'),
              subtitle: const Text('Email/password auth via Firebase'),
            ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('New post', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _captionController,
                    decoration: const InputDecoration(labelText: 'Caption'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _pickPhoto,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: Text(_photo == null ? 'Add photo' : 'Change photo'),
                      ),
                      const SizedBox(width: 12),
                      if (_photo != null)
                        Chip(label: Text(_photo!.path.split('/').last), avatar: const Icon(Icons.check_circle, size: 18)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _loading ? null : _createPost,
                    icon: _loading
                        ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                    label: const Text('Post'),
                  ),
                  if (_status.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(_status, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                    )
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Recent posts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _posts.isEmpty
                ? Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _status.isNotEmpty ? _status : 'No posts yet. Test mode keeps data locally.',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  )
                : Column(
                    children: _posts
                        .map(
                          (p) => Card(
                            child: ListTile(
                              leading: p.imageUrl != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(p.imageUrl!, width: 56, height: 56, fit: BoxFit.cover),
                                    )
                                  : const Icon(Icons.photo_outlined),
                              title: Text(p.caption),
                              subtitle: Text('by ${p.author} • ${p.createdAt.toLocal()}'),
                            ),
                          ),
                        )
                        .toList(),
                  ),
          )
        ],
      ),
    );
  }
}
