import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/community_models.dart';
import '../models/weather_models.dart';
import '../services/ai_provider.dart';
import '../services/community_service.dart';
import '../services/weather_provider.dart';
import 'community_post_detail.dart';

/// ✅ YOU MUST add this observer to MaterialApp.navigatorObservers (see note below).
final RouteObserver<PageRoute<dynamic>> communityRouteObserver = RouteObserver<PageRoute<dynamic>>();

/// Tracks whether ANY community page is currently visible (top of stack) anywhere in the app.
/// Timer only runs when visible count == 0.
class _CommunityVisibility {
  static final ValueNotifier<int> visibleCount = ValueNotifier<int>(0);
  static final Map<Object, bool> _ownerVisible = <Object, bool>{};

  static void setVisible(Object owner, bool visible) {
    final prev = _ownerVisible[owner] ?? false;
    if (prev == visible) return;

    _ownerVisible[owner] = visible;
    final nextCount = _ownerVisible.values.where((v) => v).length;
    visibleCount.value = nextCount;
  }

  static void removeOwner(Object owner) {
    final wasVisible = _ownerVisible.remove(owner) ?? false;
    if (!wasVisible) return;
    visibleCount.value = _ownerVisible.values.where((v) => v).length;
  }
}

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

class _CommunityCenterScreenState extends State<CommunityCenterScreen>
    with WidgetsBindingObserver, RouteAware {
  /// ✅ How long the user can be away from ALL community pages before we require unlock again.
  static const Duration _reauthAfter = Duration(minutes: 3);

  /// Avoid auto-prompt spam if multiple visibility events happen quickly.
  static const Duration _autoPromptCooldown = Duration(seconds: 2);

  static const List<Map<String, String>> _aiModels = [
    {'value': 'gpt-4o-mini', 'label': 'GPT-4o Mini'},
    {'value': 'gpt-4o', 'label': 'GPT-4o'},
    {'value': 'gpt-5.1', 'label': 'GPT-5.1'},
    {'value': 'gpt-5.2', 'label': 'GPT-5.2'},
  ];

  final CommunityService _service = CommunityService();
  final AiProvider _ai = RealAiProvider(apiKey: dotenv.env['OPENAI_API_KEY']);
  final _captionController = TextEditingController();
  final LocalAuthentication _localAuth = LocalAuthentication();
  final ScrollController _listController = ScrollController();

  Stream<List<CommunityPost>>? _postsStream;
  WeatherSnapshot? _weather;
  File? _photo;

  bool _loading = false;
  bool _loadingWeather = false;

  /// Device supports local auth (biometric OR device PIN/pattern/password).
  bool _biometricAvailable = false;

  /// UX only: whether biometrics are enrolled/available.
  bool _hasAnyBiometric = false;

  bool _authInProgress = false;

  /// When the user last left ALL community pages (timer only runs then).
  DateTime? _awaySince;

  /// To prevent immediate re-lock after a successful prompt.
  DateTime? _lastUnlockAt;

  DateTime? _lastAutoPromptAt;

  String _status = '';
  String _aiModel = 'gpt-4o-mini';
  bool _tagFoodLow = false;
  bool _tagClogged = false;
  bool _tagCleaningDue = false;
  bool _showAdvancedTrends = false;
  int _postLimit = 50;
  String _searchQuery = '';
  bool _locked = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _loadPrefs();
    _postsStream = _service.watchCommunityPosts(limit: _postLimit);
    _refreshWeather();

    // Listen for "user is on any community page" changes.
    _CommunityVisibility.visibleCount.addListener(_handleCommunityVisibilityChanged);

    // First open: check device auth support and unlock once.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initBiometricSupport();
      if (_locked) {
        await _reauthenticate(userInitiated: false);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      communityRouteObserver.subscribe(this, route);
      // This route is currently visible when we subscribe.
      _CommunityVisibility.setVisible(this, true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _CommunityVisibility.visibleCount.removeListener(_handleCommunityVisibilityChanged);
    _CommunityVisibility.removeOwner(this);
    communityRouteObserver.unsubscribe(this);

    _captionController.dispose();
    _listController.dispose();
    super.dispose();
  }

  // ---- RouteAware (visibility for THIS route) ----
  @override
  void didPush() => _CommunityVisibility.setVisible(this, true);

  @override
  void didPopNext() => _CommunityVisibility.setVisible(this, true);

  @override
  void didPushNext() => _CommunityVisibility.setVisible(this, false);

  @override
  void didPop() => _CommunityVisibility.setVisible(this, false);

  // ---- App lifecycle (background/foreground) ----
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // During the system auth UI, Android/iOS can trigger lifecycle transitions.
    if (_authInProgress) return;

    final inCommunityNow = _CommunityVisibility.visibleCount.value > 0;

    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // If the app leaves foreground while user is in community, start "away timer".
      if (inCommunityNow) {
        _awaySince ??= DateTime.now();
      }
      return;
    }

    if (state == AppLifecycleState.resumed) {
      // If returning to app while in community, enforce timeout (but don't spam).
      if (inCommunityNow && _awaySince != null) {
        final elapsed = DateTime.now().difference(_awaySince!);
        _awaySince = null;
        _maybeRequireReauth(elapsed, autoPrompt: true);
      }
    }
  }

  void _handleCommunityVisibilityChanged() {
    final count = _CommunityVisibility.visibleCount.value;

    if (count == 0) {
      // User is NOT on any community page -> start away timer.
      _awaySince ??= DateTime.now();
      return;
    }

    // User returned to community (any community page visible).
    if (_awaySince != null) {
      final elapsed = DateTime.now().difference(_awaySince!);
      _awaySince = null;
      _maybeRequireReauth(elapsed, autoPrompt: true);
    }
  }

  void _maybeRequireReauth(Duration elapsed, {required bool autoPrompt}) {
    // If they just unlocked (and prompt itself caused transitions), do nothing.
    final now = DateTime.now();
    final recentlyUnlocked =
        _lastUnlockAt != null && now.difference(_lastUnlockAt!) < const Duration(seconds: 1);
    if (recentlyUnlocked) return;

    if (elapsed < _reauthAfter) return;

    // Require reauth after timeout.
    if (mounted) setState(() => _locked = true);

    if (!autoPrompt) return;
    if (_authInProgress) return;

    final lastAuto = _lastAutoPromptAt;
    if (lastAuto != null && now.difference(lastAuto) < _autoPromptCooldown) return;

    _lastAutoPromptAt = now;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (!_locked) return;
      await _reauthenticate(userInitiated: false);
    });
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
      final isSupported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      final available = await _localAuth.getAvailableBiometrics();

      if (!mounted) return;
      setState(() {
        _biometricAvailable = isSupported; // device credential OR biometrics
        _hasAnyBiometric = canCheck && available.isNotEmpty;
      });
    } catch (e) {
      debugPrint('Local auth support check failed: $e');
      if (mounted) {
        setState(() {
          _biometricAvailable = false;
          _hasAnyBiometric = false;
        });
      }
    }
  }

  void _bumpPostLimit([int? to]) {
    final next = to ?? (_postLimit < 100 ? 100 : 200);
    setState(() {
      _postLimit = next;
      _postsStream = _service.watchCommunityPosts(limit: _postLimit);
    });
  }

  Future<void> _refreshPosts() async {
    try {
      final nextStream = _service.watchCommunityPosts(limit: _postLimit);
      if (!mounted) return;
      setState(() {
        _postsStream = nextStream;
        _status = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Could not refresh feed: $e');
    }
  }

  List<CommunityPost> _filterPosts(List<CommunityPost> posts) {
    if (_searchQuery.isEmpty) return posts;
    final q = _searchQuery.toLowerCase();
    return posts.where((p) {
      return p.author.toLowerCase().contains(q) ||
          p.caption.toLowerCase().contains(q) ||
          p.model.toLowerCase().contains(q);
    }).toList();
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

  /// System prompt:
  /// - Biometrics if enrolled
  /// - Otherwise device PIN/pattern/password (Android) / passcode (iOS)
  Future<bool> _authenticateLocal({required bool requireEnrollment}) async {
    if (!_biometricAvailable) {
      if (requireEnrollment) {
        if (mounted) setState(() => _status = 'This device does not support secure local authentication.');
        return false;
      }
      return true;
    }

    if (_authInProgress) return false;
    _authInProgress = true;

    try {
      final didAuth = await _localAuth.authenticate(
        localizedReason: 'Unlock Community Center',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: false, // IMPORTANT: reduces prompt loop behavior
          useErrorDialogs: true,
        ),
      );
      return didAuth;
    } catch (e) {
      debugPrint('Local auth failed: $e');
      if (mounted) setState(() => _status = 'Local auth failed: $e');
      return false;
    } finally {
      _authInProgress = false;
    }
  }

  Future<void> _reauthenticate({required bool userInitiated}) async {
    if (_authInProgress) return;

    final ok = await _authenticateLocal(requireEnrollment: true);
    if (!mounted) return;

    setState(() {
      _locked = !ok;
      if (ok) {
        _lastUnlockAt = DateTime.now();
        _status = '';
      } else if (userInitiated) {
        _status = 'Unlock cancelled.';
      }
    });
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
      await _authenticateLocal(requireEnrollment: true);
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

    // Quick local-auth gate for posting (PIN fallback allowed).
    final authOk = await _authenticateLocal(requireEnrollment: false);
    if (!authOk) {
      setState(() => _status = 'Unlock cancelled.');
      return;
    }

    setState(() {
      _loading = true;
      _status = '';
    });
    try {
      await _service
          .createPost(
        caption: _captionController.text.trim(),
        photo: _photo,
        author: refreshedUser.email ?? 'community member',
        sensors: SensorSnapshot(lowFood: _tagFoodLow, clogged: _tagClogged, cleaningDue: _tagCleaningDue),
        weather: _weather,
      )
          .timeout(const Duration(seconds: 45), onTimeout: () {
        throw TimeoutException('Posting took too long. Check your connection and try again.');
      });
      _captionController.clear();
      _photo = null;
      await _refreshPosts();
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
    final key = dotenv.env['OPENAI_API_KEY'];
    if (key == null || key.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add OPENAI_API_KEY to .env to enable AI replies.')),
        );
      }
      return;
    }
    final messages = <AiMessage>[AiMessage('user', 'Any tips for my feeder community?')];
    AiMessage reply;
    try {
      reply = await _ai.send(
        messages,
        modelOverride: _aiModel,
        context: {
          'weather': _weather?.condition ?? 'n/a',
          'sensors': 'n/a',
        },
      );
    } catch (e) {
      reply = AiMessage('ai', 'AI response unavailable right now ($e). Please try again soon.');
    }
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
    if (_locked) {
      final unlockLabel = _hasAnyBiometric ? 'Unlock (biometric)' : 'Unlock (device PIN)';
      final unlockHint = _hasAnyBiometric
          ? 'Unlock with fingerprint/face (or device PIN)'
          : 'Unlock with your device PIN / pattern / password';

      return Scaffold(
        appBar: AppBar(title: const Text('Community')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 12),
              Text(unlockHint, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _reauthenticate(userInitiated: true),
                icon: Icon(_hasAnyBiometric ? Icons.fingerprint : Icons.password),
                label: Text(unlockLabel),
              ),
              if (_status.isNotEmpty) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                )
              ],
            ],
          ),
        ),
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    return RefreshIndicator(
      onRefresh: () async {
        await _refreshPosts();
        await _refreshWeather();
      },
      child: Stack(
        children: [
          ListView(
            controller: _listController,
            padding: const EdgeInsets.all(16),
            children: [
              _header(),
              const SizedBox(height: 12),
              _metaRow(user),
              const SizedBox(height: 12),
              _composer(),
              const SizedBox(height: 16),
              _buildSearchBar(),
              const SizedBox(height: 8),
              Row(
                children: const [
                  Icon(Icons.forum_outlined),
                  SizedBox(width: 8),
                  Text('Forum threads', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 8),
              StreamBuilder<List<CommunityPost>>(
                stream: _postsStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return _buildSkeletonFeed();
                  }
                  if (snapshot.hasError) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Could not load posts: ${snapshot.error}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    );
                  }
                  final posts = snapshot.data ?? const <CommunityPost>[];
                  if (posts.isEmpty) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _status.isNotEmpty ? _status : 'No posts yet. Sign in and start the first thread.',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    );
                  }
                  final filtered = _filterPosts(posts);
                  return Column(
                    children: [
                      Column(
                        children: filtered
                            .map(
                              (p) => AnimatedSize(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeInOut,
                            child: _buildPostTile(p),
                          ),
                        )
                            .toList(),
                      ),
                      if (posts.length >= _postLimit)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () => _bumpPostLimit(),
                            child: const Text('Load more'),
                          ),
                        ),
                    ],
                  );
                },
              )
            ],
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.small(
              heroTag: 'communityTop',
              onPressed: () {
                _listController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                );
              },
              child: const Icon(Icons.arrow_upward),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search),
        hintText: 'Search posts (author or caption)',
        border: OutlineInputBorder(),
      ),
      onChanged: (val) => setState(() => _searchQuery = val.trim()),
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
        gradient: LinearGradient(
          colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary],
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.hub_outlined, color: Colors.white, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Community Center',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
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
              onPressed: _ensureAuthenticated,
              icon: const Icon(Icons.login),
              label: const Text('Login'),
            )
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
              leading: Icon(_hasAnyBiometric ? Icons.fingerprint : Icons.password),
              title: const Text('Quick unlock'),
              subtitle: Text(_hasAnyBiometric
                  ? 'Fingerprint/Face (or device PIN) to confirm access'
                  : 'Device PIN / pattern / password to confirm access'),
              trailing: IconButton(
                icon: const Icon(Icons.verified_user_outlined),
                onPressed: () async {
                  final ok = await _authenticateLocal(requireEnrollment: true);
                  if (!mounted) return;
                  setState(() {
                    _status = ok ? 'Unlocked' : 'Unlock cancelled';
                    if (ok) _lastUnlockAt = DateTime.now();
                  });
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
                const Chip(
                  avatar: Icon(Icons.devices_other),
                  label: Text('Model Ornimetrics O1'),
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
    final sv = theme.colorScheme.surfaceVariant;
    final colors = [
      sv,
      Color.alphaBlend(theme.colorScheme.primaryContainer.withOpacity(0.18), sv),
      Color.alphaBlend(theme.colorScheme.secondaryContainer.withOpacity(0.18), sv),
      Color.alphaBlend(theme.colorScheme.tertiaryContainer.withOpacity(0.18), sv),
      Color.alphaBlend(Colors.teal.shade200.withOpacity(0.12), sv),
      Color.alphaBlend(Colors.blueGrey.shade200.withOpacity(0.12), sv),
    ];
    final bg = colors[p.id.hashCode.abs() % colors.length];
    final brightness = ThemeData.estimateBrightnessForColor(bg);
    final fg = brightness == Brightness.dark ? Colors.white : Colors.black87;
    final subtle = brightness == Brightness.dark ? Colors.white70 : Colors.black54;

    return Hero(
      tag: p.id,
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: bg,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => CommunityPostDetail(post: p)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: fg.withOpacity(0.12),
                      child: Text(
                        p.author.isNotEmpty ? p.author[0].toUpperCase() : '?',
                        style: TextStyle(color: fg),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.author, style: TextStyle(fontWeight: FontWeight.w700, color: fg)),
                          Text(
                            DateFormat('MMM d, hh:mm a').format(p.createdAt.toLocal()),
                            style: TextStyle(color: subtle, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  p.caption.isNotEmpty ? p.caption : '(No caption)',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: fg),
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
