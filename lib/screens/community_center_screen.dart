import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../models/community_models.dart';
import '../services/community_service.dart';
import '../services/ai_provider.dart';
import '../services/weather_provider.dart';
import '../models/weather_models.dart';
import 'community_post_detail.dart';

class CommunityCenterScreen extends StatefulWidget {
  const CommunityCenterScreen({super.key});

  @override
  State<CommunityCenterScreen> createState() => _CommunityCenterScreenState();
}

class _CommunityCenterScreenState extends State<CommunityCenterScreen> {
  late CommunityService _service;
  bool _testMode = true;
  bool _loading = false;
  bool _loadingPosts = true;
  String _status = '';
  List<CommunityPost> _posts = <CommunityPost>[];
  final _captionController = TextEditingController();
  File? _photo;
  WeatherSnapshot? _weather;
  bool _loadingWeather = false;
  final AiProvider _ai = RealAiProvider();
  String _aiModel = 'gpt-4o-mini';
  bool _tagFoodLow = false;
  bool _tagClogged = false;
  bool _tagCleaningDue = false;
  final WeatherProvider _weatherProvider = MockWeatherProvider();

  @override
  void initState() {
    super.initState();
    _service = CommunityService(testMode: _testMode);
    _loadPrefs();
    _refresh();
    _refreshWeather();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool('pref_community_test') ?? true;
    final model = prefs.getString('pref_ai_model') ?? 'gpt-4o-mini';
    setState(() => _testMode = saved);
    _service.testMode = saved;
    setState(() => _aiModel = model);
  }

  Future<void> _refresh() async {
    setState(() => _loadingPosts = true);
    try {
      final res = await _service.fetchPosts();
      setState(() => _posts = res);
    } catch (e) {
      setState(() => _status = e.toString());
    } finally {
      if (mounted) setState(() => _loadingPosts = false);
    }
  }

  Future<void> _refreshWeather() async {
    setState(() => _loadingWeather = true);
    try {
      final res = await _weatherProvider.fetchCurrent();
      setState(() => _weather = res);
    } catch (e) {
      setState(() => _status = 'Weather unavailable: $e');
    } finally {
      setState(() => _loadingWeather = false);
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
        sensors: SensorSnapshot(lowFood: _tagFoodLow, clogged: _tagClogged, cleaningDue: _tagCleaningDue),
        weather: _weather,
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

  Future<void> _askAiGeneral() async {
    final messages = <AiMessage>[AiMessage('user', 'Any tips for my feeder community?')];
    final reply = await _ai.send(
      messages,
      modelOverride: _aiModel,
      context: {
        'weather': _weather?.condition ?? 'n/a',
        'sensors': 'n/a',
      },
    );
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('AI says'),
        content: Text(reply.content),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return RefreshIndicator(
      onRefresh: () async {
        await _refresh();
        await _refreshWeather();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _header(),
          const SizedBox(height: 12),
          _metaRow(user),
          const SizedBox(height: 12),
          _composer(),
          const SizedBox(height: 16),
          Row(
            children: const [
              Icon(Icons.forum_outlined),
              SizedBox(width: 8),
              Text('Forum threads', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _loadingPosts
                ? _buildSkeletonFeed()
                : _posts.isEmpty
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
                        children: _posts.map(_buildPostTile).toList(),
                      ),
          )
        ],
      ),
    );
  }

  Widget _buildSkeletonFeed() {
    return Column(
      children: List.generate(
        3,
        (i) => Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(height: 12, width: 120, color: Colors.grey.shade300),
                          const SizedBox(height: 6),
                          Container(height: 10, width: 80, color: Colors.grey.shade200),
                        ],
                      ),
                    ),
                    Container(height: 24, width: 60, color: Colors.grey.shade200),
                  ],
                ),
                const SizedBox(height: 12),
                Container(height: 12, width: double.infinity, color: Colors.grey.shade200),
                const SizedBox(height: 8),
                Container(height: 12, width: double.infinity, color: Colors.grey.shade200),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary]),
      ),
      child: Row(
        children: [
          const Icon(Icons.hub_outlined, color: Colors.white, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Community Center', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                SizedBox(height: 4),
                Text('Forum vibes with weather-tagged posts + AI helper', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          IconButton(
            onPressed: _askAiGeneral,
            icon: const Icon(Icons.auto_awesome, color: Colors.white),
            tooltip: 'Ask AI',
          )
        ],
      ),
    );
  }

  Widget _metaRow(User? user) {
    return Column(
      children: [
        Card(
          child: SwitchListTile(
            title: const Text('Community Test Mode'),
            subtitle: const Text('Sandbox collection + emulator friendly'),
            value: _testMode,
            onChanged: _toggleTestMode,
            secondary: const Icon(Icons.science_outlined),
          ),
        ),
        if (!_testMode)
          Card(
            child: ListTile(
              leading: const Icon(Icons.verified_user),
              title: Text(user != null ? 'Signed in as ${user.email}' : 'Not signed in'),
              subtitle: const Text('Email/password auth via Firebase emulators by default'),
              trailing: OutlinedButton.icon(onPressed: _loginOrSignUp, icon: const Icon(Icons.login), label: const Text('Login')),
            ),
          ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.cloud_queue),
            title: const Text('Weather tag'),
            subtitle: Text(_weather != null
                ? '${_weather!.temperatureC.toStringAsFixed(1)}°C • ${_weather!.humidity.toStringAsFixed(0)}% • ${_weather!.condition}'
                : _loadingWeather
                    ? 'Loading weather...'
                    : 'Mock weather used until API key ready'),
            trailing: IconButton(onPressed: _refreshWeather, icon: const Icon(Icons.refresh)),
          ),
        ),
      ],
    );
  }

  Widget _composer() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.edit_outlined),
                SizedBox(width: 8),
                Text('Start a thread', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _captionController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'What did you notice?',
                hintText: 'Share behavior, questions, or a quick update',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _pickPhoto,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(_photo == null ? 'Add photo' : 'Change photo'),
                ),
                ActionChip(
                  avatar: Icon(_testMode ? Icons.safety_check : Icons.cloud_done, color: Theme.of(context).colorScheme.primary),
                  label: Text(_testMode ? 'Posting to sandbox' : 'Live collection'),
                  onPressed: () => _toggleTestMode(!_testMode),
                ),
                if (_photo != null)
                  Chip(label: Text(_photo!.path.split('/').last), avatar: const Icon(Icons.check_circle, size: 18)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              children: [
                FilterChip(
                  label: const Text('Food low'),
                  selected: _tagFoodLow,
                  onSelected: (v) => setState(() => _tagFoodLow = v),
                ),
                FilterChip(
                  label: const Text('Clogged'),
                  selected: _tagClogged,
                  onSelected: (v) => setState(() => _tagClogged = v),
                ),
                FilterChip(
                  label: const Text('Cleaning due'),
                  selected: _tagCleaningDue,
                  onSelected: (v) => setState(() => _tagCleaningDue = v),
                ),
                Chip(
                  avatar: const Icon(Icons.devices_other),
                  label: const Text('Model Ornimetrics O1'),
                )
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _createPost,
                icon: _loading
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
                label: Text(_loading ? 'Posting...' : 'Publish'),
              ),
            ),
            if (_status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(_status, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
              )
          ],
        ),
      ),
    );
  }

  Widget _buildPostTile(CommunityPost p) {
    final theme = Theme.of(context);
    return Hero(
      tag: p.id,
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CommunityPostDetail(post: p))),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(p.author.isNotEmpty ? p.author[0].toUpperCase() : '?'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.author, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(DateFormat('MMM d, hh:mm a').format(p.createdAt.toLocal()),
                              style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
                        ],
                      ),
                    ),
                    Chip(
                      label: Text(_testMode ? 'Sandbox' : 'Live'),
                      avatar: Icon(_testMode ? Icons.science_outlined : Icons.public, size: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  p.caption.isNotEmpty ? p.caption : '(No caption)',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (p.imageUrl != null) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(p.imageUrl!, height: 180, width: double.infinity, fit: BoxFit.cover),
                  )
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _tagChip(Icons.access_time, p.timeOfDayTag),
                    _tagChip(
                      Icons.cloud_queue,
                      p.weather != null
                          ? '${p.weather!.temperatureC.toStringAsFixed(1)}°C • ${p.weather!.humidity.toStringAsFixed(0)}% • ${p.weather!.condition}'
                          : 'Weather n/a',
                    ),
                    if (p.weather?.isRaining == true || p.weather?.isSnowing == true || p.weather?.isHailing == true)
                      _tagChip(Icons.umbrella, 'Wet weather'),
                    _tagChip(Icons.restaurant, p.sensors.lowFood ? 'Food low' : 'Food ok'),
                    _tagChip(Icons.block, p.sensors.clogged ? 'Clogged' : 'Clear'),
                    _tagChip(Icons.cleaning_services, p.sensors.cleaningDue ? 'Clean soon' : 'Fresh'),
                    _tagChip(Icons.devices_other, p.model),
                  ],
                ),
                const SizedBox(height: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Posted ${DateFormat('MMM d • h:mm a').format(p.createdAt.toLocal())}',
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        TextButton.icon(
                          onPressed: () => Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => CommunityPostDetail(post: p, aiModel: _aiModel))),
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: const Text('Open thread'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => CommunityPostDetail(post: p, aiModel: _aiModel))),
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('Ask AI'),
                        ),
                      ],
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tagChip(IconData icon, String label) {
    return Chip(
      avatar: Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
      label: Text(label),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      backgroundColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.6),
      labelStyle: const TextStyle(fontWeight: FontWeight.w600),
    );
  }
}
