import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';

import '../models/community_models.dart';
import '../models/weather_models.dart';
import '../services/ai_provider.dart';
import '../services/community_service.dart';
import '../services/weather_provider.dart';
import 'community_post_detail.dart';

class CommunityCenterScreen extends StatefulWidget {
  const CommunityCenterScreen({
    super.key,
    required this.weatherProvider,
    required this.latitude,
    required this.longitude,
    this.locationStatus,
    this.onRequestLocation,
  });

  final WeatherProvider weatherProvider;
  final double? latitude;
  final double? longitude;
  final String? locationStatus;
  final VoidCallback? onRequestLocation;

  @override
  State<CommunityCenterScreen> createState() => _CommunityCenterScreenState();
}

class _CommunityCenterScreenState extends State<CommunityCenterScreen> {
  static const List<Map<String, String>> _aiModels = [
    {'value': 'gpt-4o-mini', 'label': 'GPT-4o Mini'},
    {'value': 'gpt-4o', 'label': 'GPT-4o'},
    {'value': 'gpt-5.1', 'label': 'GPT-5.1'},
    {'value': 'gpt-5.2', 'label': 'GPT-5.2'},
  ];

  final CommunityService _service = CommunityService();
  final AiProvider _ai = RealAiProvider();
  final _captionController = TextEditingController();
  final LocalAuthentication _localAuth = LocalAuthentication();

  List<CommunityPost> _posts = <CommunityPost>[];
  WeatherSnapshot? _weather;
  File? _photo;

  bool _loading = false;
  bool _loadingPosts = true;
  bool _loadingWeather = false;
  bool _biometricAvailable = false;
  String _status = '';
  String _aiModel = 'gpt-4o-mini';
  bool _tagFoodLow = false;
  bool _tagClogged = false;
  bool _tagCleaningDue = false;
  bool _showAdvancedTrends = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _refresh();
    _refreshWeather();
    _initBiometricSupport();
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final model = prefs.getString('pref_ai_model') ?? 'gpt-4o-mini';
    if (mounted) {
      setState(() {
        _aiModel = _aiModels.any((m) => m['value'] == model) ? model : _aiModels.first['value']!;
      });
    }
  }

  Future<void> _initBiometricSupport() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      if (mounted) {
        setState(() => _biometricAvailable = canCheck && isSupported);
      }
    } catch (_) {
      if (mounted) setState(() => _biometricAvailable = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => _loadingPosts = true);
    try {
      final res = await _service.fetchPosts();
      setState(() {
        _posts = res;
        _status = '';
      });
    } catch (e) {
      setState(() => _status = e.toString());
    } finally {
      if (mounted) setState(() => _loadingPosts = false);
    }
  }

  bool _isValidEmail(String value) {
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return emailRegex.hasMatch(value.trim());
  }

  bool _isStrongPassword(String value) {
    return value.length >= 12 &&
        RegExp(r'[A-Z]').hasMatch(value) &&
        RegExp(r'[a-z]').hasMatch(value) &&
        RegExp(r'[0-9]').hasMatch(value) &&
        RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(value);
  }

  Future<bool> _authenticateBiometricIfAvailable({bool requireEnrollment = false}) async {
    if (!_biometricAvailable) return !requireEnrollment;
    try {
      final didAuth = await _localAuth.authenticate(
        localizedReason: 'Confirm it’s you before posting to the community.',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: false),
      );
      return didAuth;
    } catch (_) {
      return !requireEnrollment;
    }
  }

  Future<void> _refreshWeather() async {
    setState(() => _loadingWeather = true);
    if (widget.latitude == null || widget.longitude == null) {
      setState(() {
        _status = widget.locationStatus ?? 'Location required to attach weather to posts.';
        _loadingWeather = false;
      });
      return;
    }
    try {
      final res = await widget.weatherProvider.fetchCurrent(
        latitude: widget.latitude!,
        longitude: widget.longitude!,
      );
      setState(() {
        _weather = res;
        _status = '';
      });
    } catch (e) {
      setState(() => _status = 'Weather unavailable: $e');
    } finally {
      if (mounted) setState(() => _loadingWeather = false);
    }
  }

  Future<void> _ensureAuthenticated() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await _authenticateBiometricIfAvailable(requireEnrollment: true);
      return;
    }

    final emailController = TextEditingController();
    final passController = TextEditingController();
    String? error;

    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Community login'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email')),
              TextField(
                controller: passController,
                decoration: const InputDecoration(labelText: 'Password (12+ chars, mix of cases, number, symbol)'),
                obscureText: true,
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ]
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(
              onPressed: () async {
                final email = emailController.text.trim();
                final pass = passController.text;
                if (!_isValidEmail(email)) {
                  setLocal(() => error = 'Enter a valid email.');
                  return;
                }
                if (!_isStrongPassword(pass)) {
                  setLocal(() => error = 'Use a strong password (length 12+, upper/lower/digit/symbol).');
                  return;
                }
                try {
                  await _service.signIn(email, pass);
                  setLocal(() => error = null);
                  if (mounted) Navigator.pop(context);
                  setState(() {});
                } on FirebaseAuthException catch (e) {
                  setLocal(() => error = e.message ?? 'Login failed.');
                }
              },
              child: const Text('Log in'),
            ),
            ElevatedButton(
              onPressed: () async {
                final email = emailController.text.trim();
                final pass = passController.text;
                if (!_isValidEmail(email)) {
                  setLocal(() => error = 'Enter a valid email.');
                  return;
                }
                if (!_isStrongPassword(pass)) {
                  setLocal(() => error = 'Use a strong password (length 12+, upper/lower/digit/symbol).');
                  return;
                }
                try {
                  await _service.signUp(email, pass);
                  setLocal(() => error = null);
                  if (mounted) Navigator.pop(context);
                  setState(() {});
                } on FirebaseAuthException catch (e) {
                  setLocal(() => error = e.message ?? 'Signup failed.');
                }
              },
              child: const Text('Sign up'),
            ),
          ],
        ),
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
    if (user == null) {
      await _ensureAuthenticated();
    }

    final refreshedUser = FirebaseAuth.instance.currentUser;
    if (refreshedUser == null) {
      setState(() => _status = 'Please login to post.');
      return;
    }

    // Quick biometric gate for already-authenticated users.
    final biometricOk = await _authenticateBiometricIfAvailable(requireEnrollment: false);
    if (!biometricOk) {
      setState(() => _status = 'Biometric check cancelled.');
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
        author: refreshedUser.email ?? 'community member',
        sensors: SensorSnapshot(lowFood: _tagFoodLow, clogged: _tagClogged, cleaningDue: _tagCleaningDue),
        weather: _weather,
      );
      _captionController.clear();
      _photo = null;
      await _refresh();
      setState(() => _status = 'Posted successfully');
    } on FirebaseException catch (e) {
      final msg = e.message ?? 'Upload failed.';
      setState(() => _status = msg);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      setState(() => _status = 'Upload failed: $e');
    } finally {
      setState(() => _loading = false);
    }
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
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeInOutCubicEmphasized,
            switchOutCurve: Curves.easeInOutCubic,
            child: _loadingPosts
                ? _buildSkeletonFeed()
                : _posts.isEmpty
                    ? Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            _status.isNotEmpty ? _status : 'No posts yet. Sign in and start the first thread.',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      )
                    : Column(
                        children: _posts
                            .map((p) => AnimatedSize(
                                  duration: const Duration(milliseconds: 180),
                                  curve: Curves.easeInOut,
                                  child: _buildPostTile(p),
                                ))
                            .toList(),
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
          child: ListTile(
            leading: const Icon(Icons.verified_user),
            title: Text(user != null ? 'Signed in as ${user.email}' : 'Not signed in'),
            subtitle: const Text('Secure email/password auth via Firebase'),
            trailing: user == null
                ? OutlinedButton.icon(
                    onPressed: _ensureAuthenticated, icon: const Icon(Icons.login), label: const Text('Login'))
                : TextButton.icon(
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
                      if (mounted) setState(() => _status = 'Signed out');
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                  ),
          ),
        ),
        if (_biometricAvailable)
          Card(
            child: ListTile(
              leading: const Icon(Icons.fingerprint),
              title: const Text('Biometric quick check'),
              subtitle: const Text('Fingerprint/Face ID to confirm posting access'),
              trailing: IconButton(
                icon: const Icon(Icons.verified_user_outlined),
                onPressed: () async {
                  final ok = await _authenticateBiometricIfAvailable(requireEnrollment: true);
                  setState(() => _status = ok ? 'Biometric verified' : 'Biometric cancelled');
                },
              ),
            ),
          ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.auto_awesome),
            title: const Text('AI model'),
            subtitle: Text(_aiModels
                    .firstWhere((m) => m['value'] == _aiModel, orElse: () => {'label': _aiModel})['label'] ??
                _aiModel),
            trailing: DropdownButton<String>(
              value: _aiModels.any((m) => m['value'] == _aiModel) ? _aiModel : _aiModels.first['value'],
              items: _aiModels
                  .map((m) => DropdownMenuItem<String>(
                        value: m['value'],
                        child: Text(m['label'] ?? m['value']!),
                      ))
                  .toList(),
              onChanged: (val) async {
                if (val == null) return;
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('pref_ai_model', val);
                setState(() => _aiModel = val);
              },
            ),
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
                    : (widget.locationStatus ?? 'Grant location to tag posts with real conditions')),
            trailing: IconButton(onPressed: _refreshWeather, icon: const Icon(Icons.refresh)),
          ),
        ),
        if (widget.latitude == null || widget.longitude == null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.my_location),
              title: const Text('Location needed'),
              subtitle: Text(widget.locationStatus ?? 'Request access to tag posts with real weather.'),
              trailing: widget.onRequestLocation != null
                  ? ElevatedButton(onPressed: widget.onRequestLocation, child: const Text('Grant access'))
                  : null,
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
