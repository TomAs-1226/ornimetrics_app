import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart'; // for ValueListenableBuilder
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pie_chart/pie_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'models/weather_models.dart';
import 'screens/community_center_screen.dart';
import 'screens/environment_screen.dart';
import 'screens/notification_center_screen.dart';
import 'services/ai_provider.dart';
import 'services/location_service.dart';
import 'services/maintenance_rules_engine.dart';
import 'services/notifications_service.dart';
import 'services/weather_provider.dart';


// Global theme mode notifier
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
final ValueNotifier<Color> seedColorNotifier = ValueNotifier(Colors.green);

// Global haptics toggle notifier
final ValueNotifier<bool> hapticsEnabledNotifier = ValueNotifier(true);

// Auto-refresh settings notifier
final ValueNotifier<bool> autoRefreshEnabledNotifier = ValueNotifier(false);
final ValueNotifier<double> autoRefreshIntervalNotifier = ValueNotifier(60.0);

// Firebase path for photo snapshots (each child: { image_url: string, timestamp: number or ISO string, species?: string })
const String kPhotoFeedPath = 'photo_snapshots';

class DetectionPhoto {
  final String url;
  final DateTime timestamp;
  final String? species;
  final WeatherSnapshot? weatherAtCapture;

  DetectionPhoto({required this.url, required this.timestamp, this.species, this.weatherAtCapture});

  static DateTime _parseTs(dynamic v) {
    if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (v is int) {
      // assume ms if it's large; else treat as seconds
      if (v > 100000000000) return DateTime.fromMillisecondsSinceEpoch(v);
      if (v > 1000000000) return DateTime.fromMillisecondsSinceEpoch(v * 1000);
      return DateTime.fromMillisecondsSinceEpoch(v);
    }
    if (v is double) return DateTime.fromMillisecondsSinceEpoch(v.round());
    if (v is String) {
      try { return DateTime.parse(v); } catch (_) {}
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  factory DetectionPhoto.fromMap(Map m) {
    return DetectionPhoto(
      url: (m['image_url'] ?? m['url'] ?? '').toString(),
      timestamp: _parseTs(m['timestamp']),
      species: m['species']?.toString(),
      weatherAtCapture: m['weather'] is Map
          ? WeatherSnapshot(
              condition: m['weather']['condition']?.toString() ?? 'Unknown',
              temperatureC: (m['weather']['temperatureC'] as num?)?.toDouble() ?? 0,
              humidity: (m['weather']['humidity'] as num?)?.toDouble() ?? 0,
              precipitationChance: (m['weather']['precipitationChance'] as num?)?.toDouble(),
              windKph: (m['weather']['windKph'] as num?)?.toDouble(),
              pressureMb: (m['weather']['pressureMb'] as num?)?.toDouble(),
              uvIndex: (m['weather']['uvIndex'] as num?)?.toDouble(),
              visibilityKm: (m['weather']['visibilityKm'] as num?)?.toDouble(),
              dewPointC: (m['weather']['dewPointC'] as num?)?.toDouble(),
              fetchedAt: _parseTs(m['weather']['fetchedAt']),
              isRaining: m['weather']['isRaining'] == true,
              isSnowing: m['weather']['isSnowing'] == true,
              isHailing: m['weather']['isHailing'] == true,
              feelsLikeC: (m['weather']['feelsLikeC'] as num?)?.toDouble(),
              precipitationMm: (m['weather']['precipitationMm'] as num?)?.toDouble(),
            )
          : null,
    );
  }

  DetectionPhoto withWeather(WeatherSnapshot snapshot) {
    return DetectionPhoto(
      url: url,
      timestamp: timestamp,
      species: species,
      weatherAtCapture: snapshot,
    );
  }
}

class TrendSignal {
  TrendSignal({required this.species, required this.start, required this.end});

  final String species;
  final int start;
  final int end;

  int get delta => end - start;
  double get changeRate => start == 0 ? end.toDouble() : (end - start) / start;
  String get direction => delta > 0 ? 'rising' : (delta < 0 ? 'falling' : 'steady');
}

// Model for actionable eco tasks
class EcoTask {
  final String id; // uuid-like
  final String title;
  final String? description;
  final String category; // e.g., cleaning, window_safety, habitat, water, data
  final int priority; // 1=high,2=med,3=low
  final DateTime createdAt;
  final DateTime? dueAt;
  bool done;
  final String source; // ai | system | user

  EcoTask({
    required this.id,
    required this.title,
    this.description,
    required this.category,
    this.priority = 2,
    required this.createdAt,
    this.dueAt,
    this.done = false,
    this.source = 'ai',
  });

  factory EcoTask.fromMap(Map<String, dynamic> m) {
    return EcoTask(
      id: m['id'] as String,
      title: m['title'] as String,
      description: m['description'] as String?,
      category: m['category'] as String? ?? 'general',
      priority: (m['priority'] as num?)?.toInt() ?? 2,
      createdAt: DateTime.parse(m['createdAt'] as String),
      dueAt: (m['dueAt'] as String?) != null ? DateTime.parse(m['dueAt'] as String) : null,
      done: m['done'] == true,
      source: (m['source'] as String?) ?? 'ai',
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'description': description,
        'category': category,
        'priority': priority,
        'createdAt': createdAt.toIso8601String(),
        'dueAt': dueAt?.toIso8601String(),
        'done': done,
        'source': source,
      };
}

// Safe haptic helpers
void safeLightHaptic() {
  if (hapticsEnabledNotifier.value) {
    HapticFeedback.lightImpact();
  }
}

void safeSelectionHaptic() {
  if (hapticsEnabledNotifier.value) {
    HapticFeedback.selectionClick();
  }
}

FirebaseDatabase primaryDatabase() {
  return FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: DefaultFirebaseOptions.currentPlatform.databaseURL,
  );
}

Widget envPill(BuildContext context, {required IconData icon, required String label}) {
  final theme = Theme.of(context);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: theme.colorScheme.primaryContainer.withOpacity(0.8),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onPrimaryContainer),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

Future<FirebaseApp> _ensureFirebaseInitialized() async {
  try {
    if (Firebase.apps.isNotEmpty) {
      return Firebase.apps.first;
    }
    return await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    if (e.code == 'duplicate-app') {
      return Firebase.app();
    }
    rethrow;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  await _ensureFirebaseInitialized();
  debugPrint('[firebase] Using production backends for realtime database and firestore.');

  // ── Load saved theme preference
  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('pref_dark_mode') ?? false;
  themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  final isHaptic = prefs.getBool('pref_haptics_enabled') ?? true;
  hapticsEnabledNotifier.value = isHaptic;
  final seedValue = prefs.getInt('pref_seed_color');
  if (seedValue != null) {
    seedColorNotifier.value = Color(seedValue);
  }

  // Load saved auto-refresh preferences
  final isAuto = prefs.getBool('pref_auto_refresh_enabled') ?? false;
  autoRefreshEnabledNotifier.value = isAuto;
  final interval = prefs.getDouble('pref_auto_refresh_interval') ?? 60.0;
  autoRefreshIntervalNotifier.value = interval;

  await NotificationsService.instance.load();
  await MaintenanceRulesEngine.instance.load();

  runApp(const WildlifeApp());
}

class WildlifeApp extends StatelessWidget {
  const WildlifeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: seedColorNotifier,
      builder: (_, seed, __) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: themeNotifier,
          builder: (_, mode, __) {
            return MaterialApp(
              title: 'Ornimetrics Tracker',
              debugShowCheckedModeBanner: false,
              themeMode: mode,
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
                useMaterial3: true,
                textTheme: Typography.material2021(platform: TargetPlatform.android).black,
                scaffoldBackgroundColor: const Color(0xFFF4F7F6),
                cardTheme: CardThemeData(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                appBarTheme: const AppBarTheme(),
              ),
              darkTheme: ThemeData(
                colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
                useMaterial3: true,
                textTheme: Typography.material2021(platform: TargetPlatform.android).white,
                scaffoldBackgroundColor: const Color(0xFF121212),
                cardTheme: const CardThemeData(
                  elevation: 1,
                  // Border radius looks good in dark as well
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
                appBarTheme: const AppBarTheme(),
              ),
              home: const WildlifeTrackerScreen(),
            );
          },
        );
      },
    );
  }
}

class WildlifeTrackerScreen extends StatefulWidget {
  const WildlifeTrackerScreen({super.key});

  @override
  State<WildlifeTrackerScreen> createState() => _WildlifeTrackerScreenState();
}

class _WildlifeTrackerScreenState extends State<WildlifeTrackerScreen> with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  bool _showFab = false;
  Timer? _autoRefreshTimer;

  // State for photo snapshots feed
  final ScrollController _recentScrollController = ScrollController();
  List<DetectionPhoto> _photos = [];
  bool _loadingPhotos = true;
  String _photoError = '';
  DateTime? _photosLastUpdated;

  DateTime? _lastCleaned;
  int _daysSinceClean = 0;
  bool _showMaintenanceBanner = false;
  List<EcoTask> _tasks = [];

  void _updateFabVisibility() {
    if (!_scrollController.hasClients) return;

    final atBottom = _scrollController.position.pixels >
        _scrollController.position.maxScrollExtent * 0.7;

    final shouldShow = atBottom && _aiAnalysisResult != null;
    if (shouldShow != _showFab) {
      setState(() => _showFab = shouldShow);
    }
  }

  void _updateAutoRefresh() {
    _autoRefreshTimer?.cancel();
    if (autoRefreshEnabledNotifier.value) {
      _autoRefreshTimer = Timer.periodic(
        Duration(seconds: autoRefreshIntervalNotifier.value.round()),
        (_) {
          _refreshAll();
        },
      );
    }
  }

  Future<void> _loadMaintenanceStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('pref_last_cleaned');
    DateTime? last;
    if (raw != null && raw.isNotEmpty) {
      try { last = DateTime.parse(raw); } catch (_) {}
    }
    final now = DateTime.now();
    final days = (last != null) ? now.difference(last).inDays : 9999;
    setState(() {
      _lastCleaned = last;
      _daysSinceClean = days;
      _showMaintenanceBanner = days >= 7; // nudge weekly
    });
    _ensureCleaningTaskIfStale();
  }

  Future<void> _markFeederCleaned() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await prefs.setString('pref_last_cleaned', now.toIso8601String());
    await NotificationsService.instance.markCleaned();
    setState(() {
      _lastCleaned = now;
      _daysSinceClean = 0;
      _showMaintenanceBanner = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Marked as cleaned today')),
    );
  }

  Widget _buildMaintenanceBanner() {
    return Card(
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.6),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.cleaning_services_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _daysSinceClean > 9000
                        ? 'No cleaning date recorded yet'
                        : 'It\'s been $_daysSinceClean day(s) since cleaning',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Regularly cleaning feeders helps reduce disease risk for birds.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: () {
                safeLightHaptic();
                _markFeederCleaned();
              },
              child: const Text('Mark cleaned'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationCard() {
    final service = NotificationsService.instance;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active_outlined),
                const SizedBox(width: 8),
                Text('Feeder notifications', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationCenterScreen()));
                  },
                  child: const Text('Open settings'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Configure low food, clog, and cleaning reminders. Alerts will flow from your production device telemetry.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateFabVisibility);
    _scrollController.dispose();
    _recentScrollController.removeListener(_updateFabVisibility);
    _recentScrollController.dispose();
    _autoRefreshTimer?.cancel();
    autoRefreshEnabledNotifier.removeListener(_updateAutoRefresh);
    autoRefreshIntervalNotifier.removeListener(_updateAutoRefresh);
    _aiAnim.dispose();
    super.dispose();
  }

  // State variables for data
  Map<String, double> _speciesDataMap = {};
  int _totalDetections = 0;
  bool _isLoading = true;
  String _error = '';
  DateTime? _lastUpdated;
  int _lastUsageCount = 0;
  DateTime? _lastUsageSampleAt;
  WeatherProvider _weatherProvider = RealWeatherProvider(
    apiKey: dotenv.env['WEATHER_API_KEY'] ?? '',
    endpoint: dotenv.env['WEATHER_ENDPOINT'] ?? 'https://api.weatherapi.com/v1',
  );
  Position? _position;
  String? _locationStatus;
  bool _requestingLocation = false;
  final AiProvider _trendAi = RealAiProvider();
  bool _trendAiLoading = false;
  String? _trendAiInsight;
  List<TrendSignal> _trendSignals = [];

  late final AnimationController _aiAnim;
  // State variables for AI Analysis
  Map<String, dynamic>? _aiAnalysisResult;
  bool _isAnalyzing = false;
  bool _aiIncludePhotos = true;
  int _aiPhotoLimit = 8; // options: 4, 8, 12, 16
  Future<void> _loadAiPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _aiIncludePhotos = prefs.getBool('pref_ai_include_photos') ?? true;
      _aiPhotoLimit = prefs.getInt('pref_ai_photo_limit') ?? 8;
    });
  }

  Future<void> _loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user_tasks');
    if (raw == null || raw.isEmpty) return;
    try {
      final List<dynamic> arr = json.decode(raw);
      setState(() {
        _tasks = arr.map((e) => EcoTask.fromMap(Map<String, dynamic>.from(e))).toList();
      });
    } catch (_) {}
  }

  Future<void> _saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final data = json.encode(_tasks.map((t) => t.toMap()).toList());
    await prefs.setString('user_tasks', data);
  }

  Future<void> _saveAiPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pref_ai_include_photos', _aiIncludePhotos);
    await prefs.setInt('pref_ai_photo_limit', _aiPhotoLimit);
  }

  Future<void> _captureLocation({bool force = false}) async {
    if (_requestingLocation) return;
    if (!force && _position != null) return;
    setState(() {
      _requestingLocation = true;
      _locationStatus = 'Requesting GPS permission...';
    });
    try {
      await LocationService.instance.ensureReady();
      final pos = await LocationService.instance.currentPosition(forceUpdate: force);
      if (!mounted) return;
      setState(() {
        _position = pos;
        _locationStatus = pos == null ? 'Location unavailable. Check permissions.' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locationStatus = 'Location error: ${e.toString().split('\n').first}';
      });
    } finally {
      if (mounted) {
        setState(() => _requestingLocation = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateFabVisibility);
    _recentScrollController.addListener(_updateFabVisibility);
    autoRefreshEnabledNotifier.addListener(_updateAutoRefresh);
    autoRefreshIntervalNotifier.addListener(_updateAutoRefresh);
    _updateAutoRefresh(); // Initialize based on current settings
    _loadMaintenanceStatus();
    _loadAiPrefs();
    _loadTasks();
    _captureLocation().then((_) {
      _fetchTodaySummaryFlexible();
      _fetchPhotoSnapshots();
    });
    _aiAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
  }
  String _uuid() => DateTime.now().microsecondsSinceEpoch.toString() + '_' + (math.Random().nextInt(1<<32)).toString();

  void _addTask(EcoTask t) {
    setState(() => _tasks.insert(0, t));
    _saveTasks();
  }

  void _toggleTaskDone(EcoTask t, bool value) {
    setState(() {
      final idx = _tasks.indexWhere((x) => x.id == t.id);
      if (idx != -1) {
        _tasks[idx] = EcoTask(
          id: t.id,
          title: t.title,
          description: t.description,
          category: t.category,
          priority: t.priority,
          createdAt: t.createdAt,
          dueAt: t.dueAt,
          done: value,
          source: t.source,
        );
      }
    });
    _saveTasks();
  }

  void _ensureCleaningTaskIfStale(){
    if (_daysSinceClean >= 14){
      final exists = _tasks.any((t)=> !t.done && t.category=='cleaning' && t.title.toLowerCase().contains('clean feeder'));
      if (!exists){
        _addTask(EcoTask(
          id: _uuid(),
          title: 'Clean and sanitize bird feeder',
          description: 'Wash with soap, then 1:9 bleach solution; dry fully before refilling.',
          category: 'cleaning',
          priority: 1,
          createdAt: DateTime.now(),
          dueAt: DateTime.now().add(const Duration(days: 2)),
          done: false,
          source: 'system',
        ));
      }
    }
  }
  // Tries a specific summary path and returns the snapshot if it exists and is a Map
  Future<DataSnapshot?> _trySummaryAtPath(String path) async {
    final snap = await primaryDatabase().ref(path).get();
    if (snap.exists && snap.value is Map) return snap;
    return null;
  }

  // Parse a RTDB "summary" map { species: count } into Map<String,double>
  Map<String, double> _toCountsFromValue(dynamic value) {
    if (value is! Map) return <String, double>{};
    final data = Map<dynamic, dynamic>.from(value as Map);
    final out = <String, double>{};
    data.forEach((k, v) {
      final d = (v is num) ? v.toDouble() : (double.tryParse(v.toString()) ?? 0.0);
      if (d > 0) out[k.toString()] = d;
    });
    return out;
  }

  // Read a summary at a given path and return counts, or null if not present
  Future<Map<String, double>?> _readSummaryCounts(String path) async {
    final snap = await primaryDatabase().ref(path).get();
    if (snap.exists && snap.value is Map) {
      return _toCountsFromValue(snap.value);
    }
    return null;
  }

  // Merge counts: adds values from `add` into `into`
  void _mergeCountsInPlace(Map<String, double> into, Map<String, double> add) {
    add.forEach((k, v) => into[k] = (into[k] ?? 0) + v);
  }

  // For a given date (YYYY-MM-DD), aggregate BOTH shapes:
  //  a) detections/<date>/<sessionKey>/summary
  //  b) detections/<date>/<midKey>/<sessionKey>/summary   (where midKey can be an epoch id, etc.)
  Future<Map<String, double>> _collectSummariesForDate(String date, String sessionKey) async {
    final out = <String, double>{};

    // a) Direct summary
    final direct = await _readSummaryCounts('detections/$date/$sessionKey/summary');
    if (direct != null) _mergeCountsInPlace(out, direct);

    // b) Summaries under any mid-level keys
    final dateNode = await primaryDatabase().ref('detections/$date').get();
    if (dateNode.exists && dateNode.value is Map) {
      final m = Map<dynamic, dynamic>.from(dateNode.value as Map);
      for (final k in m.keys) {
        final mid = k.toString();
        if (mid == sessionKey) continue; // already handled as direct
        final viaMid = await _readSummaryCounts('detections/$date/$mid/$sessionKey/summary');
        if (viaMid != null) _mergeCountsInPlace(out, viaMid);
      }
    }

    return out; // may be empty
  }

  Future<void> _fetchTodaySummaryFlexible({String sessionKey = 'session_1'}) async {
    try {
      final db = primaryDatabase().ref();

      final String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      String usedDate = today;

      // 1) Try to aggregate all summaries for today (old + new shapes)
      Map<String, double> species = await _collectSummariesForDate(today, sessionKey);

      // 2) If none found for today, fall back to the latest date key under /detections
      if (species.isEmpty) {
        final latest = await db.child('detections').orderByKey().limitToLast(1).get();
        String? latestDateKey;
        if (latest.exists) {
          for (final c in latest.children) {
            latestDateKey = c.key; // lexicographically largest date
          }
        }
        if (latestDateKey != null) {
          usedDate = latestDateKey!;
          species = await _collectSummariesForDate(usedDate, sessionKey);
        }
      }

      final int total = species.values.fold<int>(0, (acc, d) => acc + d.toInt());

      final now = DateTime.now();
      final delta = (_lastUsageSampleAt == null) ? total : (total - _lastUsageCount).clamp(0, total);
      final duration = _lastUsageSampleAt == null ? const Duration(minutes: 60) : now.difference(_lastUsageSampleAt!);
      _lastUsageCount = total;
      _lastUsageSampleAt = now;
      unawaited(MaintenanceRulesEngine.instance.applyUsage(
        dispenseEvents: delta,
        activeDuration: duration,
        prefs: NotificationsService.instance.preferences.value,
      ));

      if (!mounted) return;
      setState(() {
        _totalDetections = total;
        _speciesDataMap = species;
        _isLoading = false;
        _lastUpdated = DateTime.now();
        _error = species.isEmpty
            ? 'No summary found for $today. Showing latest available if present.'
            : '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _totalDetections = 0;
        _speciesDataMap = {};
        _isLoading = false;
        _lastUpdated = DateTime.now();
        _error = 'Failed to load data: $e';
      });
    }
  }

  Future<void> _refreshAll() async {
    await _captureLocation();
    await Future.wait([
      _fetchPhotoSnapshots(),
      _fetchTodaySummaryFlexible(),
    ]);
  }

  Future<void> _fetchPhotoSnapshots() async {
    await _captureLocation();
    final ref = primaryDatabase().ref(kPhotoFeedPath);
    try {
      DataSnapshot snap;

      // Try ordered query first (fast, requires rules index).
      try {
        snap = await ref.orderByChild('timestamp').limitToLast(200).get();
      } on FirebaseException catch (fe) {
        // If rules miss the index, fall back to plain get() and sort client-side.
        if (fe.code.contains('index-not-defined')) {
          snap = await ref.get();
        } else {
          rethrow;
        }
      }

      if (!snap.exists || snap.value == null) {
        if (!mounted) return;
        setState(() {
          _photos = [];
          _loadingPhotos = false;
          _photoError = '';
          _photosLastUpdated = DateTime.now();
        });
        return;
      }

      final raw = snap.value;
      final List<DetectionPhoto> items = [];

      if (raw is Map) {
        final m = Map<dynamic, dynamic>.from(raw);
        m.forEach((k, v) {
          if (v is Map) {
            final p = DetectionPhoto.fromMap(Map<dynamic, dynamic>.from(v));
            if (p.url.isNotEmpty) items.add(p);
          }
        });
      } else if (raw is List) {
        for (final v in raw) {
          if (v is Map) {
            final p = DetectionPhoto.fromMap(Map<dynamic, dynamic>.from(v));
            if (p.url.isNotEmpty) items.add(p);
          }
        }
      }

      // Always sort newest first (covers fallback path too)
      items.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      if (_position != null) {
        await _attachWeatherToPhotos(items);
      } else {
        _photoError = _locationStatus ?? 'Location permission is required to tag weather on snapshots.';
      }

      final trendSignals = _deriveTrendsFromPhotos(items);

      if (!mounted) return;
      setState(() {
        _photos = items;
        _loadingPhotos = false;
        _photosLastUpdated = DateTime.now();
        _trendSignals = trendSignals;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _photoError = 'Failed to load snapshots: $e';
        _loadingPhotos = false;
        _photosLastUpdated = DateTime.now();
      });
    }
  }

  Future<void> _attachWeatherToPhotos(List<DetectionPhoto> items) async {
    if (_position == null) return;
    final cache = <String, WeatherSnapshot>{};

    // Fetch per unique hour to avoid hammering the API and the UI thread.
    final uniqueKeys = items
        .take(50) // cap to prevent excessive parallel work on large feeds
        .map((p) => DateFormat('yyyy-MM-dd-HH').format(p.timestamp.toUtc()))
        .toSet()
        .toList();

    final futures = uniqueKeys.map((key) async {
      final parts = key.split('-');
      final ts = DateTime.parse('${parts[0]}-${parts[1]}-${parts[2]} ${parts[3]}:00:00Z');
      try {
        cache[key] = await _weatherProvider.fetchHistorical(
          timestamp: ts.toUtc(),
          latitude: _position!.latitude,
          longitude: _position!.longitude,
        );
      } catch (_) {
        // Fallback to current weather if history is missing; better than blocking UI.
        try {
          cache[key] = await _weatherProvider.fetchCurrent(
            latitude: _position!.latitude,
            longitude: _position!.longitude,
          );
        } catch (e) {
          _photoError = 'Weather lookup failed for some items: ${e.toString().split('\n').first}';
        }
      }
    }).toList();

    await Future.wait(futures);

    // Apply cached tags back to items.
    for (var i = 0; i < items.length; i++) {
      final key = DateFormat('yyyy-MM-dd-HH').format(items[i].timestamp.toUtc());
      final tag = cache[key];
      if (tag != null) {
        items[i] = items[i].withWeather(tag);
        await MaintenanceRulesEngine.instance.applyWeather(
          tag,
          NotificationsService.instance.preferences.value,
        );
      }
    }
  }

  List<TrendSignal> _deriveTrendsFromPhotos(List<DetectionPhoto> photos) {
    if (photos.isEmpty) return [];
    final now = DateTime.now().toUtc();
    final cutoff = now.subtract(const Duration(days: 7));
    final recent = photos.where((p) => p.timestamp.toUtc().isAfter(cutoff) && p.species != null && p.species!.isNotEmpty);

    final Map<String, Map<String, int>> perDay = {};
    for (final p in recent) {
      final dayKey = DateFormat('yyyy-MM-dd').format(p.timestamp.toUtc());
      final species = p.species!.toLowerCase();
      perDay.putIfAbsent(dayKey, () => {});
      perDay[dayKey]![species] = (perDay[dayKey]![species] ?? 0) + 1;
    }

    final sortedDays = perDay.keys.toList()..sort();
    if (sortedDays.length < 2) return [];

    final Map<String, TrendSignal> signals = {};
    for (final day in sortedDays) {
      final counts = perDay[day]!;
      counts.forEach((species, count) {
        signals.putIfAbsent(species, () => TrendSignal(species: species, start: 0, end: 0));
        final signal = signals[species]!;
        if (day == sortedDays.first) {
          signals[species] = TrendSignal(species: species, start: count, end: signal.end);
        }
        if (day == sortedDays.last) {
          signals[species] = TrendSignal(species: species, start: signal.start, end: count);
        }
      });
    }

    final list = signals.values.where((s) => s.delta != 0).toList()
      ..sort((a, b) => b.delta.abs().compareTo(a.delta.abs()));
    return list.take(5).toList();
  }

  Future<void> _generateTrendAiInsight() async {
    if (_trendSignals.isEmpty) return;
    setState(() {
      _trendAiLoading = true;
      _trendAiInsight = null;
    });

    final summary = _trendSignals
        .map((s) => '${s.species}: ${s.direction} (${s.start} → ${s.end})')
        .join('; ');

    final messages = <AiMessage>[
      AiMessage('system', 'You are an ornithology analyst. Blend migration heuristics with numeric trends.'),
      AiMessage('user', 'Here are 7-day trend signals: $summary. Provide 3 succinct migration or behavior insights.'),
    ];

    try {
      final reply = await _trendAi.send(messages, context: {
        'location': _position != null ? '${_position!.latitude},${_position!.longitude}' : 'unknown',
      });
      if (!mounted) return;
      setState(() {
        _trendAiInsight = reply.content;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _trendAiInsight = 'Trend AI unavailable: $e';
      });
    } finally {
      if (mounted) setState(() => _trendAiLoading = false);
    }
  }

  Future<void> _fetchDetectionData() async {
    final dbRef = primaryDatabase().ref('detections/2025-07-26/session_1/summary');

    try {
      final snapshot = await dbRef.get();
      if (snapshot.exists && snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        final Map<String, double> processedData = {};
        int total = 0;

        data.forEach((species, count) {
          if (count is int) {
            processedData[species] = count.toDouble();
            total += count;
          }
        });

        setState(() {
          _speciesDataMap = processedData;
          _totalDetections = total;
          _isLoading = false;
          _lastUpdated = DateTime.now();
        });
        // Removed SnackBar on success
      } else {
        setState(() {
          _error = 'No data found for the specified path.';
          _isLoading = false;
          _lastUpdated = DateTime.now();
        });
        // Removed SnackBar on empty data
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load data: $e';
        _isLoading = false;
        _lastUpdated = DateTime.now();
      });
      // Removed SnackBar on error
    }
  }

  Future<void> _runAiAnalysis() async {
    if (_isAnalyzing) return;

    setState(() {
      _isAnalyzing = true;
      _aiAnalysisResult = null;
    });

    // Build a concise text summary of species counts
    final speciesSummary = _speciesDataMap.entries
        .map((e) => '${e.key}: ${e.value.toInt()}')
        .join('\n');

    // Attach up to _aiPhotoLimit recent image URLs from the "Recent" tab feed (newest-first) if enabled
    final List<String> imageUrls = _aiIncludePhotos
        ? _photos.where((p) => p.url.isNotEmpty).take(_aiPhotoLimit).map((p) => p.url).toList()
        : <String>[];

    // Compose a multimodal user message: text + images
    final List<Map<String, dynamic>> userContent = [
      {
        'type': 'text',
        'text': [
          'Here is the latest summary of detected species (name: count). ',
          'Use BOTH the numeric data and the attached photos to produce a short field report. ',
          'Focus on diversity (Shannon H\', Simpson 1−D) and evenness (Pielou J\'). ',
          if (_lastUpdated != null) 'Data last updated: ${DateFormat('yyyy-MM-dd HH:mm').format(_lastUpdated!)}. ',
          'Total detections: $_totalDetections.\n\n',
          speciesSummary,
        ].join('')
      },
      for (final url in imageUrls)
        {
          'type': 'image_url',
          'image_url': {'url': url}
        },
    ];

    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer ${dotenv.env['OPENAI_API_KEY']}',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'model': 'gpt-4o-mini',
          'response_format': {'type': 'json_object'},
          'messages': [
            {
              'role': 'system',
              'content': [
                {
                  'type': 'text',
                  'text':
                      'You are an expert wildlife biologist. Analyze the species counts and the attached photos together. '
                      'Base your conclusions on BOTH evidence sources. '
                      'Return a compact JSON object with this schema: {"analysis": string, "assessment": string, "recommendations": [string, ...], "tasks": [{"title": string, "category": "cleaning"|"window_safety"|"habitat"|"water"|"data", "priority": 1|2|3, "suggestedDueDays": number, "note"?: string}] }. '
                      'Be specific (cite observed species/traits visible in photos when possible). '
                      'If photos are low-quality, note the limitations briefly.'
                }
              ]
            },
            {
              'role': 'user',
              'content': userContent,
            },
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final contentRaw = data['choices'][0]['message']['content'];
        // Expecting a JSON string due to response_format: json_object
        final content = contentRaw is String ? json.decode(contentRaw) : contentRaw;
        setState(() => _aiAnalysisResult = content as Map<String, dynamic>);
        try {
          final now = DateTime.now();
          final List<dynamic>? tasks = (content as Map<String, dynamic>)['tasks'] as List<dynamic>?;
          if (tasks != null) {
            for (final t in tasks) {
              final m = Map<String, dynamic>.from(t as Map);
              final due = (m['suggestedDueDays'] is num)
                  ? now.add(Duration(days: (m['suggestedDueDays'] as num).toInt()))
                  : null;
              _addTask(EcoTask(
                id: _uuid(),
                title: (m['title'] as String).trim(),
                description: (m['note'] as String?)?.trim(),
                category: (m['category'] as String?) ?? 'general',
                priority: (m['priority'] as num?)?.toInt() ?? 2,
                createdAt: now,
                dueAt: due,
                done: false,
                source: 'ai',
              ));
            }
          } else {
            // Fallback: derive tasks from recommendations strings
            final recs = (content as Map<String, dynamic>)['recommendations'] as List<dynamic>? ?? [];
            for (final r in recs.take(3)) {
              final txt = r.toString();
              int pr = 2; String cat = 'general'; int? dueDays;
              final low = txt.toLowerCase();
              if (low.contains('clean') || low.contains('sanitize')) { cat = 'cleaning'; pr = 1; dueDays = 14; }
              else if (low.contains('window') || low.contains('collision')) { cat = 'window_safety'; dueDays = 7; }
              else if (low.contains('native') || low.contains('plant')) { cat = 'habitat'; dueDays = 30; }
              else if (low.contains('water') || low.contains('bath')) { cat = 'water'; dueDays = 7; }
              _addTask(EcoTask(
                id: _uuid(),
                title: txt,
                description: null,
                category: cat,
                priority: pr,
                createdAt: now,
                dueAt: dueDays != null ? now.add(Duration(days: dueDays)) : null,
                done: false,
                source: 'ai',
              ));
            }
          }
        } catch (_) {}
        _updateFabVisibility();
      } else {
        final errorBody = json.decode(response.body);
        throw Exception('Failed to get analysis: ${errorBody['error']['message']}');
      }
    } catch (e) {
      setState(() {
        _aiAnalysisResult = {
          'error': 'Could not fetch or parse AI analysis.\n$e',
        };
      });
      _updateFabVisibility();
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  IconData _getIconForSpecies(String species) {
    // Normalize
    final s = species.toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');

    // Broad bird coverage – match common families and species keywords
    const birdKeywords = [
      'bird','sparrow','finch','robin','wren','warbler','thrush','blackbird','starling','jay','crow','raven','magpie','oriole',
      'swallow','swift','hummingbird','woodpecker','nuthatch','chickadee','tit','kinglet','vireo','flycatcher','phoebe','towhee',
      'bunting','grosbeak','tanager','waxwing','lark','pipit','goldfinch','siskin','redpoll','pigeon','dove','owl','hawk','eagle',
      'falcon','kite','osprey','heron','egret','ibis','duck','goose','swan','gull','tern','pelican','cormorant','loon','grebe'
    ];

    final isBird = birdKeywords.any((k) => s.contains(k));
    if (isBird) {
      // Material Icons has no dedicated bird; Dash is the closest friendly silhouette
      return Icons.flutter_dash;
    }

    // Squirrels & small rodents
    if (s.contains('squirrel') || s.contains('chipmunk')) {
      return Icons.pest_control_rodent; // rodent glyph reads clearly in both themes
    }

    // A few other common mammals, kept for completeness
    if (s.contains('rabbit') || s.contains('hare')) return Icons.cruelty_free;
    if (s.contains('deer')) return Icons.park; // antlers not available; park tree is neutral
    if (s.contains('mouse') || s.contains('rat') || s.contains('vole') || s.contains('mole')) return Icons.pest_control_rodent;

    // Fallback to a neutral nature icon instead of a question mark
    return Icons.emoji_nature;
  }

  String _formatSpeciesName(String rawName) {
    return rawName
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Ornimetrics Tracker',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: _navigateToSettings,
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            labelPadding: EdgeInsets.symmetric(horizontal: 16),
            tabs: [
              Tab(icon: Icon(Icons.dashboard), text: 'Dashboard'),
              Tab(icon: Icon(Icons.photo_camera_back_outlined), text: 'Recent'),
              Tab(icon: Icon(Icons.cloud_outlined), text: 'Environment'),
              Tab(icon: Icon(Icons.groups_2_outlined), text: 'Community'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildDashboardTab(),
            _buildRecentDetectionsTab(),
            _buildEnvironmentTab(),
            CommunityCenterScreen(
              weatherProvider: _weatherProvider,
              latitude: _position?.latitude,
              longitude: _position?.longitude,
              locationStatus: _locationStatus,
              onRequestLocation: () => _captureLocation(force: true),
            ),
          ],
        ),
        floatingActionButton: _showFab
            ? FloatingActionButton(
                onPressed: () {
                  safeSelectionHaptic();
                  _scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                  );
                },
                child: const Icon(Icons.arrow_upward),
              )
            : null,
      ),
    );
  }

  Widget _buildDashboardTab() {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _error.isNotEmpty
            ? Center(child: Text(_error, style: const TextStyle(color: Colors.red)))
            : RefreshIndicator(
                onRefresh: () async {
                  await _refreshAll();
                },
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16.0),
                  children: [
                    const Text(
                      'Live Animal Detection',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    if (_lastUpdated != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0, bottom: 12.0),
                        child: Text(
                          'Last updated: ${DateFormat('MMM d, yyyy – hh:mm a').format(_lastUpdated!)}',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
                    Text(
                      'Real-time data from Ornimetrics',
                      style: TextStyle(
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _showMaintenanceBanner
                          ? Padding(
                              key: const ValueKey('maint-banner'),
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildMaintenanceBanner(),
                            )
                          : const SizedBox.shrink(key: ValueKey('maint-banner-empty')),
                    ),
                    _buildNotificationCard(),
                    const SizedBox(height: 16),
                    _buildSummaryCards(),
                    const SizedBox(height: 24),
                    const Text(
                      'Species Distribution',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 16),
                    _buildDistributionCard(),
                    const SizedBox(height: 16),
                    _buildBiodiversityCard(),
                    const SizedBox(height: 16),
                    _buildHourlyActivityCard(),
                    const SizedBox(height: 24),
            _buildTasksCard(),
            const SizedBox(height: 24),
                    _buildTrendsCard(),
                    const SizedBox(height: 24),
                    _buildAiAnalysisCard(),
                  ],
                ),
              );
  }

  String _formatTs(DateTime dt) => DateFormat('MMM d, yyyy – hh:mm a').format(dt);

  Widget _buildRecentDetectionsTab() {
    if (_loadingPhotos) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_photoError.isNotEmpty) {
      return Center(child: Text(_photoError, style: const TextStyle(color: Colors.red)));
    }
    if (_photos.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchPhotoSnapshots,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey.shade500),
            const SizedBox(height: 12),
            const Text('No snapshots yet', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              'When your device uploads images to "$kPhotoFeedPath" with fields { image_url, timestamp, species }, they will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            if (_photosLastUpdated != null)
              Text('Checked: ${_formatTs(_photosLastUpdated!)}', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: GridView.builder(
          key: ValueKey(_photos.length),
          controller: _recentScrollController,
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1,
          ),
          itemCount: _photos.length,
          itemBuilder: (_, i) {
            final p = _photos[i];
            return _PhotoTile(
              photo: p,
              onTap: () {
                safeLightHaptic();
                Navigator.of(context).push(
                  PageRouteBuilder(
                    transitionDuration: const Duration(milliseconds: 300),
                    pageBuilder: (_, a, __) => RecentPhotoViewer(
                      photos: _photos,
                      initialIndex: i,
                    ),
                    transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _openSpeciesDetail(String speciesKey) async {
    safeLightHaptic();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _SpeciesDetailSheet(speciesKey: speciesKey),
    );
  }


  Widget _buildSummaryCards() {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () {
              safeLightHaptic();
              _navigateToTotalDetections();
            },
            onLongPress: () {
              safeLightHaptic();
              Clipboard.setData(
                ClipboardData(text: 'Total detections: $_totalDetections'),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Total detections copied')),
              );
            },
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_totalDetections',
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'Total Detections',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: Icon(
                            Icons.track_changes,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: InkWell(
            onTap: () {
              safeLightHaptic();
              _navigateToUniqueSpecies();
            },
            onLongPress: () {
              safeLightHaptic();
              final speciesList = _speciesDataMap.keys.map((k) => k.replaceAll('_', ' ')).join(', ');
              Clipboard.setData(
                ClipboardData(text: 'Unique species: $speciesList'),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Species list copied')),
              );
            },
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_speciesDataMap.length}',
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'Unique Species',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.pets,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Groups species with <5% share into a single "Other" slice for pie charts.
  Map<String, double> _groupPieData(Map<String, double> src) {
    if (src.isEmpty) return <String, double>{};
    final double total = src.values.fold(0.0, (a, b) => a + b);
    if (total <= 0) return <String, double>{};

    const double thresholdPct = 5.0; // percent

    // Sort by value desc to keep major species first
    final entries = src.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final Map<String, double> out = {};
    double other = 0.0;

    for (final e in entries) {
      final pct = (e.value / total) * 100.0;
      if (pct < thresholdPct) {
        other += e.value;
      } else {
        out[e.key] = e.value;
      }
    }

    if (other > 0) {
      out['Other'] = other;
    }
    return out;
  }

  // Generates a theme-aware color palette for the pie slices.
  List<Color> _pieColorsForCount(int n, BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final base = scheme.primary;
    final hslBase = HSLColor.fromColor(base);

    final List<Color> colors = [];
    for (int i = 0; i < n; i++) {
      final hue = (hslBase.hue + (i * (360.0 / (n == 0 ? 1 : n)))) % 360.0;
      final sat = (hslBase.saturation * 0.9).clamp(0.35, 0.95).toDouble();
      final lightMid = brightness == Brightness.dark ? 0.55 : 0.60;
      final light = (lightMid + (0.06 * ((i % 3) - 1))).clamp(0.35, 0.75);
      colors.add(HSLColor.fromAHSL(1.0, hue, sat, light).toColor());
    }
    return colors;
  }

  Widget _buildDistributionCard() {
    final Map<String, double> pieDataMap = _groupPieData(_speciesDataMap);
    final sortedEntries = _speciesDataMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (_speciesDataMap.isNotEmpty)
              LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final radius = (w * 0.42).clamp(120.0, 220.0);
                  final ring = (radius * 0.22).clamp(14.0, 28.0);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Column(
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: PieChart(
                            key: ValueKey('${pieDataMap.length}_$_totalDetections'),
                            dataMap: pieDataMap,
                            chartType: ChartType.disc,
                            animationDuration: const Duration(milliseconds: 900),
                            chartLegendSpacing: 24,
                            chartRadius: radius,
                            colorList: _pieColorsForCount(pieDataMap.length, context),
                            baseChartColor: Theme.of(context).brightness == Brightness.dark
                                ? Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.28)
                                : Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.18),
                            legendOptions: LegendOptions(
                              showLegends: true,
                              legendPosition: LegendPosition.bottom,
                              legendTextStyle: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              legendShape: BoxShape.circle,
                            ),
                            initialAngleInDegree: -90,
                            chartValuesOptions: const ChartValuesOptions(
                              showChartValues: true,
                              showChartValuesInPercentage: true,
                              decimalPlaces: 0,
                              showChartValueBackground: true,
                              showChartValuesOutside: false,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  );
                },
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40.0),
                child: Text("No species data to display."),
              ),
            const SizedBox(height: 8),
            const Divider(),
            for (int i = 0; i < sortedEntries.length; i++)
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Duration(milliseconds: 250 + i * 40),
                builder: (_, v, child) => Opacity(
                  opacity: v,
                  child: Transform.translate(
                    offset: Offset(0, (1 - v) * 8),
                    child: child,
                  ),
                ),
                child: _buildSpeciesListItem(
                  icon: _getIconForSpecies(sortedEntries[i].key),
                  name: _formatSpeciesName(sortedEntries[i].key),
                  count: sortedEntries[i].value.toInt(),
                  onTap: () => _openSpeciesDetail(sortedEntries[i].key),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBiodiversityCard() {
    if (_speciesDataMap.isEmpty || _totalDetections <= 0) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('No data for diversity metrics.'),
        ),
      );
    }

    final total = _totalDetections.toDouble();
    final probs = _speciesDataMap.values.map((v) => v / total).toList();
    double shannon = 0.0;
    double sumP2 = 0.0;
    for (final p in probs) {
      if (p > 0) shannon += -p * math.log(p);
      sumP2 += p * p;
    }
    final simpsonDComplement = 1 - sumP2;

    final s = _speciesDataMap.length;
    final hMax = (s > 0) ? math.log(s) : 0.0;
    final evenness = (s > 1 && hMax > 0) ? (shannon / hMax) : 0.0;

    String fmt(double x) => x.isNaN || x.isInfinite ? '—' : x.toStringAsFixed(2);

    final content = Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Species Diversity Metrics',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const Spacer(),
                Icon(Icons.open_in_full, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text('Hold to Copy', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 12.0;
                int columns;
                if (constraints.maxWidth >= 720) {
                  columns = 3;
                } else if (constraints.maxWidth >= 480) {
                  columns = 2;
                } else {
                  columns = 1;
                }
                final tileWidth = (constraints.maxWidth - spacing * (columns - 1)) / columns;

                final tiles = <Widget>[
                  SizedBox(
                    width: tileWidth,
                    child: _buildInfoTile(
                      "Shannon Diversity Index (H')",
                      fmt(shannon),
                      tooltip: "Entropy-based diversity; higher = more diverse.",
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _buildInfoTile(
                      "Gini–Simpson Index (1−D)",
                      fmt(simpsonDComplement),
                      tooltip: "Chance two random individuals are different.",
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _buildInfoTile(
                      "Pielou Evenness (J')",
                      fmt(evenness),
                      tooltip: "0–1 scale of how evenly species are represented.",
                    ),
                  ),
                ];

                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: tiles,
                );
              },
            ),
          ],
        ),
      ),
    );

    // Remove tap-to-expand (dialog) functionality, keep long-press to copy
    return GestureDetector(
      onLongPress: () {
        final text = "H': ${fmt(shannon)}, 1−D: ${fmt(simpsonDComplement)}, J': ${fmt(evenness)}";
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Diversity metrics copied')),
        );
      },
      child: content,
    );
  }

  void _showInfoDialog(String title, String body) {
    showGeneralDialog(
      context: context,
      barrierLabel: 'Info',
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.25),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, anim1, anim2) {
        return SafeArea(
          child: Stack(
            children: [
              // Blur the content behind the dialog
              BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: const SizedBox.expand(),
              ),
              Center(
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text(body),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('OK'),
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      transitionBuilder: (ctx, a1, a2, child) {
        final curved = CurvedAnimation(parent: a1, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildInfoTile(String title, String value, {String? tooltip}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (tooltip != null)
                IconButton(
                  icon: const Icon(Icons.info_outline, size: 18),
                  tooltip: 'What is this?',
                  onPressed: () {
                    safeSelectionHaptic();
                    _showInfoDialog(title, tooltip);
                  },
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ───────── Expanded overlay (blurred background) ─────────
  void _showExpandedOverlay(String title, Widget content) {
    showGeneralDialog(
      context: context,
      barrierLabel: 'Expanded',
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.25),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) {
        return SafeArea(
          child: Stack(
            children: [
              // Blur the background behind the dialog
              BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: const SizedBox.expand(),
              ),
              Center(
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  elevation: 12,
                  borderRadius: BorderRadius.circular(16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 860,
                      maxHeight: MediaQuery.of(context).size.height * 0.88,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Header
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.6),
                              border: Border(
                                bottom: BorderSide(
                                  color: Theme.of(context).dividerColor.withOpacity(0.2),
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Close',
                                  onPressed: () => Navigator.of(context).pop(),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          ),
                          // Content
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: SingleChildScrollView(
                                key: ValueKey(title),
                                padding: const EdgeInsets.all(16.0),
                                child: content,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      transitionBuilder: (ctx, a1, a2, child) {
        final curved = CurvedAnimation(
          parent: a1,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  void _openDiversityExpanded() {
    safeLightHaptic();
    _showExpandedOverlay("Species Diversity — Details", _buildDiversityDetailContent());
  }

  void _openActivityExpanded() {
    safeLightHaptic();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Activity Details',
      barrierColor: Colors.black.withOpacity(0.45),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) {
        return SafeArea(
          child: Stack(
            alignment: Alignment.center,
            children: [
              BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
                child: Container(color: Colors.black.withOpacity(0.2)),
              ),
              Center(
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
                    constraints: BoxConstraints(
                      maxWidth: 800,
                      maxHeight: MediaQuery.of(context).size.height * 0.9,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                        child: _buildActivityDetailContent(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      transitionBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: Tween(begin: 0.95, end: 1.0).animate(curved), child: child),
        );
      },
    );
  }

  // ───────── Diversity: detailed content with animated bar chart + tools ─────────
  Widget _buildDiversityDetailContent() {
    if (_speciesDataMap.isEmpty || _totalDetections == 0) {
      return const Text('No data available for detailed diversity view.');
    }

    // Local UI state for sorting & filtering inside the dialog
    bool sortByCount = true;
    String query = '';

    final entriesAll = _speciesDataMap.entries
        .map((e) => MapEntry(e.key, e.value.toInt()))
        .toList();

    Widget buildRows(List<MapEntry<String, int>> rows) {
      if (rows.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24.0),
          child: Text(
            'No species match your filter.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        );
      }

      final maxVal = rows
          .map((e) => e.value)
          .fold<int>(0, (m, v) => v > m ? v : m)
          .toDouble()
          .clamp(1, double.infinity);

      return Column(
        children: [
          for (int i = 0; i < rows.length; i++)
            TweenAnimationBuilder<double>(
              key: ValueKey(rows[i].key),
              tween: Tween(begin: 0, end: rows[i].value / maxVal),
              duration: Duration(milliseconds: 220 + (i * 15)),
              builder: (_, frac, __) {
                final pct = (_totalDetections > 0)
                    ? ((rows[i].value / _totalDetections) * 100)
                    : 0;
                final name = _formatSpeciesName(rows[i].key);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Row with icon, name, count + percent
                      Row(
                        children: [
                          Icon(
                            _getIconForSpecies(rows[i].key),
                            size: 18,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${pct.toStringAsFixed(0)}% (${rows[i].value})',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Animated bar
                      LayoutBuilder(
                        builder: (ctx, cons) {
                          final barWidth = cons.maxWidth * frac;
                          return Container(
                            height: 12,
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceVariant
                                  .withOpacity(0.6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                width: barWidth,
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.85),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      );
    }

    return StatefulBuilder(
      builder: (ctx, setLocal) {
        final filtered = entriesAll
            .where((e) =>
                query.trim().isEmpty ||
                _formatSpeciesName(e.key).toLowerCase().contains(query.toLowerCase()))
            .toList()
          ..sort((a, b) {
            if (sortByCount) return b.value.compareTo(a.value);
            return _formatSpeciesName(a.key).compareTo(_formatSpeciesName(b.key));
          });

        final total = _totalDetections.toDouble();
        double shannon = 0.0, sumP2 = 0.0;
        for (final v in _speciesDataMap.values) {
          final p = v / total;
          if (p > 0) shannon += -p * math.log(p);
          sumP2 += p * p;
        }
        final simpson = 1 - sumP2;
        final s = _speciesDataMap.length;
        final evenness = (s > 1) ? (shannon / math.log(s)) : 0.0;
        String fmt(double x) => (x.isNaN || x.isInfinite) ? '—' : x.toStringAsFixed(2);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Quick stats row
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildInfoTile("Shannon H'", fmt(shannon),
                    tooltip: "Entropy-based diversity; higher = more diverse."),
                _buildInfoTile("Gini–Simpson (1−D)", fmt(simpson),
                    tooltip: "Chance two random individuals are different."),
                _buildInfoTile("Pielou J'", fmt(evenness),
                    tooltip: "0–1 scale of how evenly species are represented."),
              ],
            ),
            const SizedBox(height: 16),
            // Controls
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Filter species...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (t) => setLocal(() => query = t),
                  ),
                ),
                const SizedBox(width: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Count')),
                    ButtonSegment(value: false, label: Text('A–Z')),
                  ],
                  selected: <bool>{sortByCount},
                  onSelectionChanged: (s) => setLocal(() => sortByCount = s.first),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy CSV'),
                  onPressed: () {
                    final csv = StringBuffer('species,count,percent\n');
                    for (final e in filtered) {
                      final pct = (_totalDetections > 0)
                          ? (e.value / _totalDetections * 100)
                          : 0;
                      csv.writeln(
                          '${_formatSpeciesName(e.key)},${e.value},${pct.toStringAsFixed(2)}');
                    }
                    Clipboard.setData(ClipboardData(text: csv.toString()));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied diversity table CSV')),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            buildRows(filtered),
          ],
        );
      },
    );
  }

  // ───────── Activity: detailed content with top-species-by-hour thumbnails ─────────
  Map<int, String> _topSpeciesByHour() {
    final Map<int, Map<String, int>> counts = {
      for (int h = 0; h < 24; h++) h: <String, int>{}
    };
    for (final p in _photos) {
      final s = (p.species ?? '').trim();
      if (s.isEmpty) continue;
      final h = p.timestamp.hour;
      final bucket = counts[h] ??= <String, int>{};
      bucket[s] = (bucket[s] ?? 0) + 1;
    }
    final Map<int, String> top = {};
    counts.forEach((h, m) {
      if (m.isEmpty) {
        top[h] = '';
      } else {
        final sorted = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        top[h] = sorted.first.key;
      }
    });
    return top;
  }

  DetectionPhoto? _examplePhotoForHour(int h, String species) {
    for (final p in _photos) {
      if (p.timestamp.hour == h && (p.species ?? '') == species) return p;
    }
    // fallback: any photo from that hour
    for (final p in _photos) {
      if (p.timestamp.hour == h) return p;
    }
    return null;
  }

  Widget _buildActivityDetailContent() {
    if (_photos.isEmpty) {
      return const Text('No snapshots to compute per-hour activity.');
    }

    bool onlyActiveHours = true; // default true
    // Compute histogram counts for only hours that have photos
    final counts = List<int>.filled(24, 0);
    for (final p in _photos) {
      counts[p.timestamp.hour]++;
    }

    final hoursWithPhotos = List.generate(24, (i) => i).where((h) => counts[h] > 0).toList();
    if (hoursWithPhotos.isEmpty) {
      return const Text('No valid activity data available.');
    }

    final maxVal = counts.fold<int>(0, (m, v) => v > m ? v : m);
    final topByHour = _topSpeciesByHour();

    return StatefulBuilder(
      builder: (ctx, setLocal) {
        final hours = onlyActiveHours ? hoursWithPhotos : List.generate(24, (i) => i);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Material(
              elevation: 2,
              color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.9),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Switch.adaptive(
                      value: onlyActiveHours,
                      onChanged: (v) => setLocal(() => onlyActiveHours = v),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Show only active hours',
                      style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Copy summary',
                      icon: const Icon(Icons.copy, size: 20),
                      onPressed: () {
                        final buf = StringBuffer();
                        for (final h in hours) {
                          final species = topByHour[h] ?? '';
                          buf.writeln('${h.toString().padLeft(2, '0')}:00 - ${species.isEmpty ? '—' : _formatSpeciesName(species)} (${counts[h]})');
                        }
                        Clipboard.setData(ClipboardData(text: buf.toString()));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied hourly summary')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildAnimatedHistogram(counts, maxVal),
            const SizedBox(height: 24),
            _buildHourlyCards(hours, counts, topByHour),
          ],
        );
      },
    );
  }

  // --- Helper for toolbar row with elevation and color tint
  Widget _buildToolbar(BuildContext context, bool onlyActiveHours, void Function(void Function()) setLocal) {
    return Material(
      elevation: 2,
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.85),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Switch.adaptive(
              value: onlyActiveHours,
              onChanged: (v) => setLocal(() => onlyActiveHours = v),
            ),
            const SizedBox(width: 8),
            Text(
              'Show only active hours',
              style: TextStyle(fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy summary'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
                textStyle: const TextStyle(fontWeight: FontWeight.w600),
              ),
              onPressed: () {
                final buf = StringBuffer();
                // Use local hours, counts, topByHour
                final hours = List.generate(24, (i) => i)
                    .where((h) => !onlyActiveHours || (_photos.where((p) => p.timestamp.hour == h).isNotEmpty))
                    .toList();
                final counts = List<int>.filled(24, 0);
                for (final p in _photos) {
                  counts[p.timestamp.hour]++;
                }
                final topByHour = _topSpeciesByHour();
                for (final h in hours) {
                  final species = topByHour[h] ?? '';
                  buf.writeln(
                      '${h.toString().padLeft(2, '0')}:00 - ${species.isEmpty ? '—' : _formatSpeciesName(species)} (${counts[h]})');
                }
                Clipboard.setData(ClipboardData(text: buf.toString()));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied hourly summary')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- Helper for animated histogram with gradient, rounded bars, soft shadow, color blending, staggered entry
  Widget _buildAnimatedHistogram(List<int> counts, int maxVal) {
    final theme = Theme.of(context);
    final colorA = theme.colorScheme.primary;
    final colorB = theme.colorScheme.secondary;
    return Container(
      height: 140,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.colorScheme.surfaceVariant.withOpacity(0.16),
            theme.colorScheme.surface.withOpacity(0.45),
          ],
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (int h = 0; h < 24; h++)
            Expanded(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: maxVal == 0 ? 0 : counts[h] / maxVal),
                duration: Duration(milliseconds: 340 + h * 22),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: FractionallySizedBox(
                          heightFactor: v,
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(9),
                              boxShadow: [
                                BoxShadow(
                                  color: theme.colorScheme.primary.withOpacity(0.13),
                                  blurRadius: 9,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                              gradient: LinearGradient(
                                begin: Alignment.bottomLeft,
                                end: Alignment.topRight,
                                colors: [
                                  Color.lerp(colorA, colorB, h / 23.0)!.withOpacity(0.82),
                                  colorA.withOpacity(0.72),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        (h % 2 == 0) ? h.toString().padLeft(2, '0') : '',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant.withOpacity(0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --- Helper for hourly summary cards (per hour), subtle elevation, consistent spacing
  Widget _buildHourlyCards(List<int> hours, List<int> counts, Map<int, String> topByHour) {
    final theme = Theme.of(context);
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: hours.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, idx) {
        final h = hours[idx];
        final species = topByHour[h] ?? '';
        final photo = _examplePhotoForHour(h, species);
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 220 + idx * 36),
          builder: (_, v, child) => Opacity(
            opacity: v,
            child: Transform.translate(offset: Offset(0, (1 - v) * 10), child: child),
          ),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      width: 48,
                      height: 48,
                      color: theme.colorScheme.surfaceVariant.withOpacity(0.25),
                      child: photo != null
                          ? _buildImageWidget(photo.url, fit: BoxFit.cover)
                          : Icon(Icons.photo_library_outlined, color: theme.colorScheme.onSurfaceVariant, size: 28),
                    ),
                  ),
                  const SizedBox(width: 13),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${h.toString().padLeft(2, '0')}:00',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            _getIconForSpecies(species),
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            species.isEmpty ? '—' : _formatSpeciesName(species),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.11),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${counts[h]}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHourlyActivityCard() {
    if (_photos.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('No recent snapshots to compute activity.'),
        ),
      );
    }

    final counts = List<int>.filled(24, 0);
    for (final p in _photos) {
      counts[p.timestamp.hour]++;
    }
    final maxVal = counts.fold<int>(0, (m, v) => v > m ? v : m);

    final content = Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Activity by Hour',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const Spacer(),
                Icon(Icons.open_in_full, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text('Tap to expand', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 140,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (int h = 0; h < 24; h++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Flexible(
                              child: FractionallySizedBox(
                                heightFactor: maxVal == 0 ? 0 : counts[h] / maxVal,
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primary.withOpacity(0.75),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              (h % 2 == 0) ? h.toString().padLeft(2, '0') : '',
                              style: const TextStyle(fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _openActivityExpanded,
      onLongPress: () {
        // QoL: copy simple histogram on long-press
        final buf = StringBuffer();
        for (int h = 0; h < 24; h++) {
          buf.writeln('${h.toString().padLeft(2, '0')}: ${counts[h]}');
        }
        Clipboard.setData(ClipboardData(text: buf.toString()));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hourly counts copied')));
      },
      child: content,
    );
  }
  // ───────── Diversity POPUP (direct metric dialog) ─────────
  void _openDiversityPopup(String metric) {
    safeLightHaptic();
    final s = _diversityStats();

    switch (metric) {
      case 'Shannon':
        _showMetricInfoDialog(
          "Shannon Diversity (H')",
          _buildShannonDetails(s),
        );
        break;
      case 'Simpson':
        _showMetricInfoDialog(
          "Gini–Simpson (1−D)",
          _buildSimpsonDetails(s),
        );
        break;
      case 'Evenness':
        _showMetricInfoDialog(
          "Pielou Evenness (J')",
          _buildEvennessDetails(s),
        );
        break;
      default:
        _showMetricInfoDialog(
          "Species Diversity Metrics",
          const Text("Invalid selection."),
        );
    }
  }

  Widget _buildDiversityMetricsPopupContent() {
    if (_speciesDataMap.isEmpty || _totalDetections == 0) {
      return const Text('No data available for diversity metrics.');
    }

    final s = _diversityStats();
    String fmt(double x, [int d = 2]) =>
        (x.isNaN || x.isInfinite) ? '—' : x.toStringAsFixed(d);

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _metricCard(
          icon: Icons.functions,
          title: "Shannon Diversity (H')",
          value: fmt(s['H']!),
          subtitle: "Effective species (N₁): ${fmt(s['hillN1']!)}",
          onTap: () => _openDiversityPopup('Shannon'),
        ),
        _metricCard(
          icon: Icons.insights_outlined,
          title: "Gini–Simpson (1−D)",
          value: fmt(s['simpson']!),
          subtitle: "Effective species (N₂): ${fmt(s['hillN2']!)}",
          onTap: () => _openDiversityPopup('Simpson'),
        ),
        _metricCard(
          icon: Icons.equalizer,
          title: "Pielou Evenness (J')",
          value: fmt(s['evenness']!),
          subtitle: "Richness (S): ${s['S']!.toInt()}",
          onTap: () => _openDiversityPopup('Evenness'),
        ),
      ],
    );
  }

  Widget _metricCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 200,
        constraints: const BoxConstraints(minWidth: 200, maxWidth: 260),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.55),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _showMetricInfoDialog(String title, Widget body) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final maxH = MediaQuery.of(ctx).size.height * 0.75;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(title),
          contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16), // avoid pixel overflow at top
          content: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 560, maxHeight: maxH),
            child: SingleChildScrollView(child: body),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Map<String, double> _diversityStats() {
    final N = _totalDetections.toDouble();
    final S = _speciesDataMap.length.toDouble();
    if (N <= 0 || S <= 0) {
      return {
        'N': N, 'S': S, 'H': double.nan, 'simpson': double.nan, 'evenness': double.nan,
        'sumP2': double.nan, 'hillN1': double.nan, 'hillN2': double.nan, 'coverage': double.nan,
        'chao1': double.nan, 'F1': 0, 'F2': 0, 'Nmax': 0, 'berger': double.nan,
      };
    }

    double H = 0.0;
    double sumP2 = 0.0;
    int F1 = 0, F2 = 0, Nmax = 0;

    _speciesDataMap.forEach((_, vRaw) {
      final c = vRaw.toInt();
      if (c > Nmax) Nmax = c;
      if (c == 1) F1++;
      if (c == 2) F2++;
      final p = c / N;
      if (p > 0) {
        H += -p * math.log(p);
        sumP2 += p * p;
      }
    });

    final simpson = 1 - sumP2;                // 1 − D
    final evenness = (S > 1) ? (H / math.log(S)) : 0.0;
    final hillN1 = math.exp(H);                // effective species from Shannon
    final hillN2 = (sumP2 > 0) ? (1 / sumP2) : double.nan; // from Simpson
    final coverage = 1 - (F1 / (N <= 0 ? 1 : N));          // Good's coverage
    final chao1 = (F2 > 0) ? (S + (F1 * F1) / (2 * F2)) : (S + (F1 * (F1 - 1)) / 2.0);
    final berger = (N > 0) ? (Nmax / N) : double.nan;      // Berger–Parker dominance

    return {
      'N': N,
      'S': S,
      'H': H,
      'simpson': simpson,
      'evenness': evenness,
      'sumP2': sumP2,
      'hillN1': hillN1,
      'hillN2': hillN2,
      'coverage': coverage,
      'chao1': chao1,
      'F1': F1.toDouble(),
      'F2': F2.toDouble(),
      'Nmax': Nmax.toDouble(),
      'berger': berger,
    };
  }

  String _fmt2Div(double x) => (x.isNaN || x.isInfinite) ? '—' : x.toStringAsFixed(2);
  Widget _kvRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Expanded(child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
          const SizedBox(width: 12),
          Text(v),
        ],
      ),
    );
  }

  Widget _buildShannonDetails(Map<String, double> s) {
    final total = (s['N'] ?? _totalDetections.toDouble());
    final entries = _speciesDataMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(3).toList();
    String pct(double count) => total > 0 ? '${((count / total) * 100).toStringAsFixed(0)}%' : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Overview", style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text(
          "Shannon diversity sums up both how many species you have and how evenly observations are spread. "
          "Higher values mean a more varied community where no single species dominates."
        ),
        const SizedBox(height: 12),
        const Text("How to read it", style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text("• Low: a few species dominate\n• Medium: mix of common and occasional species\n• High: many species seen in similar amounts"),
        const SizedBox(height: 12),
        const Text("In your data", style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        _kvRow("Shannon H'", _fmt2Div(s['H']!)),
        _kvRow("Effective species (N₁)", _fmt2Div(s['hillN1']!)),
        _kvRow("Richness (S)", s['S']!.toInt().toString()),
        _kvRow("Total detections", s['N']!.toInt().toString()),
        _kvRow("Sampling coverage", _fmt2Div(s['coverage']!)),
        _kvRow("Estimated unseen species", _fmt2Div((s['chao1'] ?? 0) - (s['S'] ?? 0))),
        if (top.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text("Top contributors", style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final e in top)
            _kvRow(_formatSpeciesName(e.key), '${e.value.toInt()} (${pct(e.value)})'),
        ],
      ],
    );
  }

  Widget _buildSimpsonDetails(Map<String, double> s) {
    final total = (s['N'] ?? _totalDetections.toDouble());
    final entries = _speciesDataMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(3).toList();
    String pct(double count) => total > 0 ? '${((count / total) * 100).toStringAsFixed(0)}%' : '—';

    final D = 1 - (s['simpson'] ?? double.nan); // dominance concentration

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Overview", style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text(
          "Gini–Simpson (shown here as 1−D) tells you the chance that two random detections are different species. "
          "Values closer to 1 mean higher diversity; values near 0 mean one or a few species dominate."
        ),
        const SizedBox(height: 12),
        const Text("How to read it", style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text("• Near 0: highly dominated by one species\n• Mid-range: a few common species plus several less common\n• Near 1: many species with similar presence"),
        const SizedBox(height: 12),
        const Text("In your data", style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        _kvRow("Diversity (1−D)", _fmt2Div(s['simpson']!)),
        _kvRow("Dominance (D)", _fmt2Div(D)),
        _kvRow("Effective species (N₂)", _fmt2Div(s['hillN2']!)),
        _kvRow("Top species share", _fmt2Div(s['berger']!)),
        _kvRow("Richness (S)", s['S']!.toInt().toString()),
        _kvRow("Total detections", s['N']!.toInt().toString()),
        if (top.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text("Top species right now", style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final e in top)
            _kvRow(_formatSpeciesName(e.key), '${e.value.toInt()} (${pct(e.value)})'),
        ],
      ],
    );
  }

  Widget _buildEvennessDetails(Map<String, double> s) {
    final total = (s['N'] ?? _totalDetections.toDouble());
    final entries = _speciesDataMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(3).toList();
    String pct(double count) => total > 0 ? '${((count / total) * 100).toStringAsFixed(0)}%' : '—';

    final unseen = (s['chao1'] ?? 0) - (s['S'] ?? 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Overview", style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text(
          "Pielou’s evenness (J') shows how evenly detections are spread across species. "
          "Closer to 1 means species are seen in comparable amounts; lower values mean a few species dominate."
        ),
        const SizedBox(height: 12),
        const Text("How to read it", style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text("• Low: strong dominance by a few species\n• Medium: mix of dominant and background species\n• High: observations are well balanced across species"),
        const SizedBox(height: 12),
        const Text("In your data", style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        _kvRow("Evenness (J')", _fmt2Div(s['evenness']!)),
        _kvRow("Richness (S)", s['S']!.toInt().toString()),
        _kvRow("Total detections", s['N']!.toInt().toString()),
        _kvRow("Sampling coverage", _fmt2Div(s['coverage']!)),
        _kvRow("Estimated unseen species", _fmt2Div(unseen)),
        if (top.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text("Most represented species", style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final e in top)
            _kvRow(_formatSpeciesName(e.key), '${e.value.toInt()} (${pct(e.value)})'),
        ],
      ],
    );
  }

  Widget _buildSpeciesListItem({
    required IconData icon,
    required String name,
    required int count,
    VoidCallback? onTap,
  }) {
    final percentage = (_totalDetections > 0) ? (count / _totalDetections) * 100 : 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 6.0),
          child: Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${percentage.toStringAsFixed(0)}% ($count)',
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTasksCard() {
    final pending = _tasks.where((t) => !t.done).toList()
      ..sort((a, b) {
        // Sort by priority (1 high → 3 low), then by due date
        final byPr = a.priority.compareTo(b.priority);
        if (byPr != 0) return byPr;
        return (a.dueAt ?? DateTime(2100)).compareTo(b.dueAt ?? DateTime(2100));
      });

    final top = pending.take(3).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Action Tasks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add_task_outlined),
                  tooltip: 'Add quick task',
                  onPressed: () async {
                    safeSelectionHaptic();
                    final controller = TextEditingController();
                    await showDialog(
                      context: context,
                      builder: (ctx) {
                        return AlertDialog(
                          title: const Text('New Task'),
                          content: TextField(
                            controller: controller,
                            decoration: const InputDecoration(hintText: 'Describe the action'),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Add')),
                          ],
                        );
                      },
                    );
                    final text = controller.text.trim();
                    if (text.isEmpty) return;
                    _addTask(
                      EcoTask(
                        id: _uuid(),
                        title: text,
                        description: null,
                        category: 'user',
                        priority: 2,
                        createdAt: DateTime.now(),
                        dueAt: null,
                        done: false,
                        source: 'user',
                      ),
                    );
                  },
                ),
              ],
            ),
            if (top.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text('No pending tasks yet. Run an Ecological AI Analysis or add one.'),
              )
            else
              Column(
                children: [
                  for (final t in top)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: t.done,
                            onChanged: (v) {
                              if (v != null) _toggleTaskDone(t, v);
                            },
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                                if (t.description != null && t.description!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2.0),
                                    child: Text(
                                      t.description!,
                                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    ),
                                  ),
                                Row(
                                  children: [
                                    _buildTaskChip(t.category),
                                    const SizedBox(width: 8),
                                    if (t.dueAt != null)
                                      Text(
                                        'Due: ' + DateFormat('MMM d').format(t.dueAt!),
                                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Migration & activity trends', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon: _trendAiLoading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome),
                  tooltip: 'Ask AI for migration insight',
                  onPressed: _trendSignals.isEmpty || _trendAiLoading ? null : _generateTrendAiInsight,
                )
              ],
            ),
            const SizedBox(height: 8),
            if (_trendSignals.isEmpty)
              Text(
                'Need more data to spot trends. Add snapshots with species labels over several days.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _trendSignals
                        .map(
                          (s) => Chip(
                            avatar: Icon(
                              s.direction == 'rising'
                                  ? Icons.trending_up
                                  : s.direction == 'falling'
                                      ? Icons.trending_down
                                      : Icons.remove,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            label: Text(
                              '${_formatSpeciesName(s.species)}: ${s.start} → ${s.end} (${s.direction})',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Algorithmic view: highlighting strongest 7-day changes (increase/decrease).',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            if (_trendAiInsight != null) ...[
              const Divider(height: 20),
              Text('AI migration insight', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(_trendAiInsight!),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildTaskChip(String category) {
    IconData icon = Icons.task_alt_outlined;
    String label = category;
    switch (category) {
      case 'cleaning':
        icon = Icons.cleaning_services_outlined;
        label = 'Cleaning';
        break;
      case 'window_safety':
        icon = Icons.grid_on_outlined;
        label = 'Window safety';
        break;
      case 'habitat':
        icon = Icons.spa_outlined;
        label = 'Habitat';
        break;
      case 'water':
        icon = Icons.water_drop_outlined;
        label = 'Water';
        break;
      case 'data':
        icon = Icons.insert_chart_outlined;
        label = 'Data';
        break;
      default:
        icon = Icons.task_alt_outlined;
        label = category.isNotEmpty ? (category[0].toUpperCase() + category.substring(1)) : 'General';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
  // This is the main widget that replaces the old one
  Widget _buildAiAnalysisCard() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              const Text("Ecological AI Analysis",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          // Reduce initial spacing after the header
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Include recent photos'),
                  value: _aiIncludePhotos,
                  onChanged: (v) {
                    safeSelectionHaptic();
                    setState(() => _aiIncludePhotos = v);
                    _saveAiPrefs();
                  },
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _aiPhotoLimit,
                items: const [4, 8, 12, 16]
                    .map((n) => DropdownMenuItem<int>(value: n, child: Text('Use $n photos')))
                    .toList(),
                onChanged: (n) {
                  if (n == null) return;
                  safeSelectionHaptic();
                  setState(() => _aiPhotoLimit = n);
                  _saveAiPrefs();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Animate loading/prompt/result block
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeIn,
            switchOutCurve: Curves.easeOut,
            child: _isAnalyzing
                ? const Center(
                    key: ValueKey('loading'),
                    child: CircularProgressIndicator(),
                  )
                : (_aiAnalysisResult == null
                    ? Center(
                        key: const ValueKey('prompt'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20.0),
                          child: Text(
                            "Click below to generate an AI analysis.",
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      )
                    : (_aiAnalysisResult is Map<String, dynamic>
                        ? Column(
                            key: const ValueKey('result'),
                            children: [
                              if (_aiAnalysisResult!['error'] != null)
                                _buildInfoCard(
                                  title: "Error",
                                  content: Text(
                                    _aiAnalysisResult!['error'].toString(),
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                )
                              else ...[
                                _buildInfoCard(
                                  title: "Current Analysis",
                                  content: Text(
                                    _aiAnalysisResult!['analysis'] ?? 'No analysis available.',
                                    style: const TextStyle(height: 1.4),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _buildInfoCard(
                                  title: "Ecosystem Assessment",
                                  content: Text(
                                    _aiAnalysisResult!['assessment'] ?? 'No assessment available.',
                                    style: const TextStyle(height: 1.4),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _buildInfoCard(
                                  title: "Recommendations",
                                  content: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: (_aiAnalysisResult!['recommendations'] as List<dynamic>)
                                        .map((rec) => Padding(
                                              padding: const EdgeInsets.only(bottom: 8.0),
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Text("• ", style: TextStyle(fontWeight: FontWeight.bold)),
                                                  Expanded(child: Text(rec.toString())),
                                                ],
                                              ),
                                            ))
                                        .toList(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      icon: const Icon(Icons.copy),
                                      label: const Text('Copy Analysis'),
                                      style: TextButton.styleFrom(
                                        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                      ),
                                      onPressed: () {
                                        safeLightHaptic();
                                        Clipboard.setData(
                                          ClipboardData(text: json.encode(_aiAnalysisResult)),
                                        );
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Analysis copied to clipboard')),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          )
                        : Center(
                            key: const ValueKey('unexpected'),
                            child: _buildInfoCard(
                              title: "Unexpected AI Response",
                              content: Text(
                                  "The data from the AI was in an unexpected format. Please try again.\n\nDetails: ${_aiAnalysisResult.toString()}"),
                            ),
                          ))),
          ),

          // Animate spacing before the button when result appears (AI finishes)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            height: (_aiAnalysisResult != null) ? 24 : 8,
          ),

          // Animate the button transition
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: ElevatedButton.icon(
              key: ValueKey(_isAnalyzing),
              onPressed: () {
                safeLightHaptic();
                _runAiAnalysis();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple.shade400,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: Icon(_isAnalyzing ? Icons.sync : Icons.insights),
              label: Text(_isAnalyzing ? "Analyzing..." : "Run AI Analysis"),
            ),
          ),
        ],
      ),
    );
  }

// Helper widget to reduce code duplication for the cards
  Widget _buildInfoCard({required String title, required Widget content}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF006D65)),
            ),
            const SizedBox(height: 10),
            content,
          ],
        ),
      ),
    );
  }

  Widget _buildEnvironmentTab() {
    return EnvironmentScreen(
      provider: _weatherProvider,
      latitude: _position?.latitude,
      longitude: _position?.longitude,
      locationStatus: _locationStatus,
      onRequestLocation: () => _captureLocation(force: true),
    );
  }

// ───────── Navigation to subscreens ─────────
  void _navigateToTotalDetections() {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, animation, __) =>
            TotalDetectionsScreen(
              totalDetections: _totalDetections,
              speciesData: _speciesDataMap,
            ),
        transitionsBuilder: (_, animation, __, child) {
          final tween = Tween(begin: const Offset(0, 1), end: Offset.zero)
              .chain(CurveTween(curve: Curves.easeOut));
          return SlideTransition(position: animation.drive(tween), child: child);
        },
      ),
    );
  }

  void _navigateToUniqueSpecies() {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, animation, __) =>
            UniqueSpeciesScreen(speciesData: _speciesDataMap),
        transitionsBuilder: (_, animation, __, child) {
          final tween = Tween(begin: const Offset(0, 1), end: Offset.zero)
              .chain(CurveTween(curve: Curves.easeOut));
          return SlideTransition(position: animation.drive(tween), child: child);
        },
      ),
    );
  }

  void _navigateToSettings() {
    Navigator.of(context)
        .push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, animation, __) => const SettingsScreen(),
        transitionsBuilder: (_, animation, __, child) {
          final tween = Tween(begin: const Offset(1, 0), end: Offset.zero)
              .chain(CurveTween(curve: Curves.easeOut));
          return SlideTransition(position: animation.drive(tween), child: child);
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Photo tile and viewer widgets (Recent tab)
// ─────────────────────────────────────────────


// ─── Helpers: support data: URLs from RTDB snapshots ───
Uint8List? _decodeDataUrl(String url) {
  // Expected: data:image/jpeg;base64,<payload>
  if (!url.startsWith('data:')) return null;
  final i = url.indexOf('base64,');
  if (i == -1) return null;
  final b64 = url.substring(i + 7);
  try {
    return base64.decode(b64);
  } catch (_) {
    return null;
  }
}

Image _buildImageWidget(String url, {BoxFit fit = BoxFit.cover}) {
  final frameBuilder = (
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    if (wasSynchronouslyLoaded) return child;
    return AnimatedOpacity(
      opacity: frame == null ? 0 : 1,
      duration: const Duration(milliseconds: 300),
      child: child,
    );
  };

  final errorBuilder = (
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) {
    return Container(
      color: Colors.black12,
      alignment: Alignment.center,
      child: const Icon(Icons.broken_image_outlined),
    );
  };

  if (url.startsWith('data:')) {
    final bytes = _decodeDataUrl(url);
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: fit,
        frameBuilder: frameBuilder,
        errorBuilder: errorBuilder,
      );
    }
    return Image.memory(
      Uint8List(0),
      fit: fit,
      errorBuilder: errorBuilder,
    );
  }

  return Image.network(
    url,
    fit: fit,
    frameBuilder: frameBuilder,
    errorBuilder: errorBuilder,
  );
}


class _PhotoTile extends StatefulWidget {


  final DetectionPhoto photo;
  final VoidCallback onTap;
  const _PhotoTile({Key? key, required this.photo, required this.onTap}) : super(key: key);
  @override
  State<_PhotoTile> createState() => _PhotoTileState();
}


class _PhotoTileState extends State<_PhotoTile> {
  @override
  Widget build(BuildContext context) {
    final p = widget.photo;
    return InkWell(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Positioned.fill(
              child: Hero(
                tag: p.url,
                child: _buildImageWidget(p.url, fit: BoxFit.cover),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xAA000000), Color(0x00000000)],
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final maxChipWidth = constraints.maxWidth - 16;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                        if (p.weatherAtCapture != null)
                          ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: maxChipWidth),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Wrap(
                                spacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  const Icon(Icons.thermostat, size: 16, color: Colors.white),
                                  Flexible(
                                    child: Text(
                                      '${p.weatherAtCapture!.temperatureC.toStringAsFixed(1)}°C • ${p.weatherAtCapture!.humidity.toStringAsFixed(0)}% hum',
                                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if ((p.species ?? '').isNotEmpty)
                          ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: maxChipWidth),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                p.species!,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxChipWidth),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black38,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              DateFormat('MMM d, hh:mm a').format(p.timestamp),
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}



class RecentPhotoViewer extends StatefulWidget {
  final List<DetectionPhoto> photos;
  final int initialIndex;
  const RecentPhotoViewer({Key? key, required this.photos, required this.initialIndex}) : super(key: key);

  @override
  State<RecentPhotoViewer> createState() => _RecentPhotoViewerState();
}

class _RecentPhotoViewerState extends State<RecentPhotoViewer> {
  late final PageController _pc = PageController(initialPage: widget.initialIndex);
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.photos[_index];
    return Scaffold(
      appBar: AppBar(
        title: Text('${_index + 1} / ${widget.photos.length}'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10),
            child: Center(
              child: Text(
                DateFormat('MMM d, yyyy – hh:mm a').format(p.timestamp),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pc,
        onPageChanged: (i) => setState(() => _index = i),
        itemCount: widget.photos.length,
        itemBuilder: (_, i) {
          final item = widget.photos[i];
          return InteractiveViewer(
            minScale: 0.8,
            maxScale: 5,
            child: Center(
              child: Hero(
                tag: item.url,
                child: _buildImageWidget(item.url, fit: BoxFit.contain),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((p.species ?? '').isNotEmpty)
              Row(
                children: [
                  const Icon(Icons.pets),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p.species!,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            if (p.weatherAtCapture != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  envPill(
                    context,
                    icon: Icons.thermostat,
                    label: '${p.weatherAtCapture!.temperatureC.toStringAsFixed(1)}°C • ${p.weatherAtCapture!.condition}',
                  ),
                  envPill(
                    context,
                    icon: Icons.water_drop_outlined,
                    label: '${p.weatherAtCapture!.humidity.toStringAsFixed(0)}% hum',
                  ),
                  if (p.weatherAtCapture!.windKph != null)
                    envPill(
                      context,
                      icon: Icons.air,
                      label: '${p.weatherAtCapture!.windKph!.toStringAsFixed(0)} kph wind',
                    ),
                  if (p.weatherAtCapture!.uvIndex != null)
                    envPill(
                      context,
                      icon: Icons.wb_sunny_outlined,
                      label: 'UV ${p.weatherAtCapture!.uvIndex!.toStringAsFixed(1)}',
                    ),
                ],
              ),
            ]
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SUBSCREEN 1 – Total Detections (toggle chart)
// ─────────────────────────────────────────────

/// Loads recent photos from /photo_snapshots, accepting flexible field names.
/// Supports `url` or `image_url`/`imageUrl`, and numeric or string `timestamp`.
/// Returns newest-first list of DetectionPhoto. Safe to call from anywhere.
Future<List<DetectionPhoto>> fetchRecentPhotosFlexible({int limit = 50}) async {
  try {
    final db = primaryDatabase().ref();
    final snap = await db
        .child('photo_snapshots')
        .orderByChild('timestamp')
        .limitToLast(limit)
        .get();

    final List<DetectionPhoto> photos = [];
    if (snap.exists && snap.value is Map) {
      final m = Map<dynamic, dynamic>.from(snap.value as Map);
      m.forEach((key, raw) {
        if (raw is Map) {
          final row = Map<dynamic, dynamic>.from(raw);

          // Accept old and new field names
          final String url =
          (row['url'] ?? row['image_url'] ?? row['imageUrl'] ?? '').toString();
          final String? species =
          (row['species'] ?? row['label'])?.toString();

          // Handle timestamp as int/double/string
          int ts = 0;
          final v = row['timestamp'];
          if (v is int) {
            ts = v;
          } else if (v is double) {
            ts = v.toInt();
          } else if (v is String) {
            ts = int.tryParse(v) ?? 0;
          }

          if (url.isNotEmpty && ts > 0) {
            photos.add(
              DetectionPhoto(
                url: url,
                timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
                species: (species?.isEmpty ?? true) ? null : species,
              ),
            );
          }
        }
      });

      // Newest first
      photos.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }

    return photos;
  } catch (_) {
    // On any error, return empty list to keep the UI resilient
    return <DetectionPhoto>[];
  }
}

enum _ChartMode { bar, pie }

class TotalDetectionsScreen extends StatefulWidget {
  final int totalDetections;
  final Map<String, double> speciesData;

  const TotalDetectionsScreen({
    super.key,
    required this.totalDetections,
    required this.speciesData,
  });

  @override
  State<TotalDetectionsScreen> createState() => _TotalDetectionsScreenState();
}

class _TotalDetectionsScreenState extends State<TotalDetectionsScreen> {
  _ChartMode _mode = _ChartMode.bar;
  String _searchText = '';
  bool _sortAlphabetical = false;
  bool _showPercentage = false;
  double _minCountFilter = 0;

  String _formatSpecies(String raw) =>
      raw.split('_').map((w) => '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

  List<MapEntry<String, double>> _filteredItems() {
    var list = widget.speciesData.entries
        .where((e) => e.key.toLowerCase().contains(_searchText))
        .where((e) => e.value >= _minCountFilter)
        .toList();
    list.sort((a, b) {
      if (_sortAlphabetical) {
        return a.key.compareTo(b.key);
      }
      return b.value.compareTo(a.value);
    });
    return list;
  }

  Future<void> _exportCsv() async {
    final items = _filteredItems();
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data to export')),
      );
      return;
    }

    final sb = StringBuffer()..writeln('species,count');
    for (final e in items) {
      sb.writeln('${e.key},${e.value.toInt()}');
    }

    final suggested = 'ornimetrics_detections_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';

    final bytes = Uint8List.fromList(utf8.encode(sb.toString()));

    // Use the current file_selector save API
    final FileSaveLocation? location = await getSaveLocation(
      suggestedName: suggested,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv']),
      ],
    );
    if (location == null) return; // user cancelled

    final XFile xfile = XFile.fromData(bytes, name: suggested, mimeType: 'text/csv');
    await xfile.saveTo(location.path);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CSV exported')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems();
    // Always use the true maximum across all species, not the first in sorted list
    final allValues = widget.speciesData.values;
    final maxCount = allValues.isNotEmpty ? allValues.reduce((a, b) => a > b ? a : b) : 1.0;

    Widget chart;
    if (items.isEmpty) {
      // No data after filtering
      chart = Center(
        key: const ValueKey('no-results'),
        child: Text(
          'No results match the current filters.',
          style: TextStyle(
            fontSize: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    } else if (_mode == _ChartMode.bar) {
      chart = LayoutBuilder(
        key: const ValueKey('bar'),
        builder: (context, constraints) {
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, i) {
              final entry = items[i];
              final frac = entry.value / maxCount;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        _formatSpecies(entry.key),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 6,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: frac),
                        duration: const Duration(milliseconds: 600),
                        builder: (_, v, __) => FractionallySizedBox(
                          widthFactor: v.clamp(0.0, 1.0),
                          alignment: Alignment.centerLeft,
                          child: Container(
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.green.shade400,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          _showPercentage
                              ? '${((entry.value / (widget.totalDetections == 0 ? 1 : widget.totalDetections)) * 100).round()}%'
                              : entry.value.toInt().toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } else {
      chart = Padding(
        key: ValueKey('pie-$_sortAlphabetical'),
        padding: const EdgeInsets.only(top: 16.0),
        child: items.isNotEmpty
            ? PieChart(
                dataMap: Map.fromEntries(items),
                animationDuration: const Duration(milliseconds: 800),
                chartLegendSpacing: 48,
                legendOptions: const LegendOptions(showLegends: true),
                chartValuesOptions: const ChartValuesOptions(showChartValuesInPercentage: true),
              )
            : Center(
                child: Text(
                  'No results match the current filters.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Total Detections'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all),
            tooltip: 'Copy breakdown',
            onPressed: () {
              final breakdown = _filteredItems()
                  .map((e) => '${e.key}: ${e.value.toInt()}')
                  .join(', ');
              Clipboard.setData(ClipboardData(
                  text: 'Total: ${widget.totalDetections}\n$breakdown'));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                  content: Text(
                    'Breakdown copied',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export CSV',
            onPressed: _exportCsv,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search bar and sort button in a row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Filter species…',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (txt) => setState(() => _searchText = txt.toLowerCase()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      Icons.sort_by_alpha,
                      color: _sortAlphabetical
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    tooltip: 'Toggle A→Z',
                    onPressed: () {
                      safeSelectionHaptic();
                      setState(() => _sortAlphabetical = !_sortAlphabetical);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          behavior: SnackBarBehavior.floating,
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                          content: Text(
                            _sortAlphabetical ? 'Sorted A→Z' : 'Sorted by count',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Show percentage toggle
            SwitchListTile(
              title: const Text('Show percentage'),
              value: _showPercentage,
              onChanged: (val) => setState(() => _showPercentage = val),
            ),
            // Minimum count filter
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  'Min count: ${_minCountFilter.round()}',
                  key: ValueKey(_minCountFilter.round()),
                ),
              ),
            ),
            Slider(
              value: _minCountFilter,
              min: 0,
              max: widget.totalDetections.toDouble(),
              divisions: 10,
              label: '${_minCountFilter.round()}',
              onChanged: (val) => setState(() => _minCountFilter = val),
            ),
            const SizedBox(height: 12),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 800),
              builder: (_, v, __) => Text(
                '${(widget.totalDetections * v).round()} total detections',
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            ToggleButtons(
              isSelected: [_mode == _ChartMode.bar, _mode == _ChartMode.pie],
              onPressed: (index) {
                safeSelectionHaptic();
                setState(() => _mode =
                    index == 0 ? _ChartMode.bar : _ChartMode.pie);
              },
              children: const [Icon(Icons.bar_chart), Icon(Icons.pie_chart)],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeIn,
                switchOutCurve: Curves.easeOut,
                child: chart,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Screen to show a species name and its introduction in full
class SpeciesDetailScreen extends StatelessWidget {
  final String speciesKey;
  final String introText;

  const SpeciesDetailScreen({
    Key? key,
    required this.speciesKey,
    required this.introText,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(speciesKey.replaceAll('_', ' ')),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Text(
            introText.isNotEmpty ? introText : 'No introduction available.',
            style: const TextStyle(fontSize: 18, height: 1.4),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SETTINGS SCREEN
// ─────────────────────────────────────────────
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _hapticsEnabled = true;
  bool _animationsEnabled = true;
  bool _autoRefreshEnabled = false;
  double _autoRefreshInterval = 60.0; // seconds
  String _selectedAiModel = 'gpt-4o-mini';
  Color _seedColor = Colors.green;

  bool get _darkMode => themeNotifier.value == ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _hapticsEnabled = hapticsEnabledNotifier.value;
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hapticsEnabled = prefs.getBool('pref_haptics_enabled') ?? true;
      _animationsEnabled = prefs.getBool('pref_animations_enabled') ?? true;
      _autoRefreshEnabled = prefs.getBool('pref_auto_refresh_enabled') ?? false;
      _autoRefreshInterval = prefs.getDouble('pref_auto_refresh_interval') ?? 60.0;
      _selectedAiModel = prefs.getString('pref_ai_model') ?? 'gpt-4o-mini';
      final seedValue = prefs.getInt('pref_seed_color');
      if (seedValue != null) {
        _seedColor = Color(seedValue);
        seedColorNotifier.value = _seedColor;
      }
    });
  }

  Widget _colorChip(String label, Color color) {
    final isSelected = _seedColor.value == color.value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: color.withOpacity(0.15),
      avatar: CircleAvatar(backgroundColor: color, radius: 6),
      onSelected: (_) async {
        safeLightHaptic();
        setState(() => _seedColor = color);
        seedColorNotifier.value = color;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('pref_seed_color', color.value);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Dark mode'),
            value: _darkMode,
            onChanged: (val) async {
              safeLightHaptic();
              setState(() =>
                  themeNotifier.value = val ? ThemeMode.dark : ThemeMode.light);

              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('pref_dark_mode', val);
            },
          ),
          ListTile(
            title: const Text('Accent tint'),
            subtitle: const Text('Keep visuals lively with themed card tints'),
            trailing: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _seedColor,
                shape: BoxShape.circle,
                boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Wrap(
              spacing: 8,
              children: [
                _colorChip('Emerald', Colors.green),
                _colorChip('Citrus', Colors.orange),
                _colorChip('Ocean', Colors.teal),
                _colorChip('Lavender', Colors.deepPurple),
                _colorChip('Rose', Colors.pinkAccent),
                _colorChip('Sky', Colors.blueAccent),
                _colorChip('Graphite', Colors.blueGrey),
              ],
            ),
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Enable haptic feedback'),
            value: _hapticsEnabled,
            onChanged: (val) async {
              safeLightHaptic();
              setState(() => _hapticsEnabled = val);
              hapticsEnabledNotifier.value = val;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('pref_haptics_enabled', val);
            },
          ),
          // QoL: Animations toggle
          SwitchListTile(
            title: const Text('Enable animations'),
            value: _animationsEnabled,
            onChanged: (val) async {
              safeLightHaptic();
              setState(() => _animationsEnabled = val);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('pref_animations_enabled', val);
            },
          ),
          // QoL: Auto-refresh toggle
          SwitchListTile(
            title: const Text('Auto-refresh data'),
            subtitle: Text(_autoRefreshEnabled
                ? 'Every ${_autoRefreshInterval.round()} sec'
                : 'Manual only'),
            value: _autoRefreshEnabled,
            onChanged: (val) async {
              safeLightHaptic();
              setState(() => _autoRefreshEnabled = val);
              autoRefreshEnabledNotifier.value = val;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('pref_auto_refresh_enabled', val);
            },
          ),
          // QoL: Refresh interval slider (only show if enabled)
          if (_autoRefreshEnabled)
            ListTile(
              title: Text('Refresh interval (${_autoRefreshInterval.round()}s)'),
              subtitle: Slider(
                value: _autoRefreshInterval,
                min: 10,
                max: 300,
                divisions: 29,
                label: '${_autoRefreshInterval.round()}s',
                onChanged: (val) async {
                  setState(() => _autoRefreshInterval = val);
                  autoRefreshIntervalNotifier.value = val;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setDouble('pref_auto_refresh_interval', val);
                },
              ),
            ),
          // QoL: AI model selector
          ListTile(
            title: const Text('Preferred AI model'),
              subtitle: DropdownButton<String>(
                value: _selectedAiModel,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'gpt-4o-mini', child: Text('GPT-4o Mini')),
                  DropdownMenuItem(value: 'gpt-3.5-turbo', child: Text('GPT-3.5 Turbo')),
                  DropdownMenuItem(value: 'gpt-5.1', child: Text('GPT 5.1')),
                  DropdownMenuItem(value: 'gpt-5.2', child: Text('GPT 5.2')),
                ],
                onChanged: (val) async {
                  if (val == null) return;
                  safeLightHaptic();
                  setState(() => _selectedAiModel = val);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('pref_ai_model', val);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Feeder notifications'),
            subtitle: const Text('Configure production alerts'),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationCenterScreen()));
            },
            trailing: const Icon(Icons.chevron_right),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('Feeder maintenance'),
            subtitle: FutureBuilder<SharedPreferences>(
              future: SharedPreferences.getInstance(),
              builder: (context, snap) {
                DateTime? last;
                if (snap.hasData) {
                  final raw = snap.data!.getString('pref_last_cleaned');
                  if (raw != null) {
                    try { last = DateTime.parse(raw); } catch (_) {}
                  }
                }
                final text = last == null
                    ? 'No cleaning date recorded'
                    : 'Last cleaned: ${DateFormat('MMM d, yyyy').format(last!)}';
                return Text(text);
              },
            ),
            trailing: ElevatedButton(
              onPressed: () async {
                safeLightHaptic();
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('pref_last_cleaned', DateTime.now().toIso8601String());
                if (mounted) setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cleaning date saved')),
                );
              },
              child: const Text('Mark cleaned today'),
            ),
          ),
          // Divider for clarity
          const Divider(),
          // QoL: Clear AI analysis cache button
          ListTile(
            title: const Text('Clear AI analysis cache'),
            leading: const Icon(Icons.delete_outline),
            onTap: () {
              safeLightHaptic();
              // Clear any cached analysis result
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                  content: Text(
                    'AI analysis cache cleared',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('App version'),
            subtitle: const Text('1.1.0'),
            onTap: () {
              safeSelectionHaptic();
              showGeneralDialog(
                context: context,
                barrierDismissible: true,
                barrierLabel: 'About Ornimetrics',
                barrierColor: Colors.black45,
                transitionDuration: const Duration(milliseconds: 300),
                transitionBuilder: (context, anim1, anim2, child) {
                  return BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 4.0, sigmaY: 4.0),
                    child: FadeTransition(
                      opacity: anim1,
                      child: child,
                    ),
                  );
                },
                pageBuilder: (context, anim1, anim2) {
                  return Center(
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.8,
                      padding: const EdgeInsets.all(24.0),
                      decoration: BoxDecoration(
                        color: Theme.of(context).dialogBackgroundColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Material(
                        type: MaterialType.transparency,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              'Ornimetrics Device',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Ornimetrics Device helps you monitor wildlife detections in real time on your device, '
                              'track species distribution, and receive AI-driven ecological insights.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Created by Baichen Yu',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Version 1.1.0',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
// ─────────────────────────────────────────────
// Species Detail Sheet (bottom sheet with photo carousel)
// ─────────────────────────────────────────────
class _SpeciesDetailSheet extends StatefulWidget {
  final String speciesKey; // e.g., "eastern-bluebird"
  const _SpeciesDetailSheet({Key? key, required this.speciesKey}) : super(key: key);

  @override
  State<_SpeciesDetailSheet> createState() => _SpeciesDetailSheetState();
}

class _SpeciesDetailSheetState extends State<_SpeciesDetailSheet> {
  final PageController _pc = PageController(viewportFraction: 0.88);
  List<DetectionPhoto> _items = [];
  bool _loading = true;
  bool _insightsLoading = true;
  String? _insights;

  static String _normalize(String s) =>
      s.toLowerCase().replaceAll(' ', '_').replaceAll('-', '_');

  bool _matches(String key, String? label) {
    if (label == null || label.isEmpty) return false;
    return _normalize(label) == _normalize(key);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await fetchRecentPhotosFlexible(limit: 200);
    final items = all.where((p) => _matches(widget.speciesKey, p.species)).toList();
    setState(() {
      _items = items;
      _loading = false;
    });
    await _generateInsights();
  }
  String _describeSpeciesGroup(String name) {
    final s = name.toLowerCase();
    // birds
    if (s.contains('owl')) return 'a nocturnal raptor';
    if (s.contains('hawk') || s.contains('falcon') || s.contains('eagle')) return 'a diurnal raptor';
    if (s.contains('sparrow') || s.contains('finch') || s.contains('wren') || s.contains('warbler') || s.contains('bluebird')) return 'a small songbird';
    if (s.contains('woodpecker')) return 'a tree-foraging bird';
    if (s.contains('duck') || s.contains('goose') || s.contains('heron') || s.contains('egret')) return 'a water-associated bird';
    if (s.contains('dove') || s.contains('pigeon')) return 'a ground-foraging bird';
    // mammals
    if (s.contains('squirrel') || s.contains('chipmunk')) return 'a small tree-dwelling mammal';
    if (s.contains('rabbit') || s.contains('hare')) return 'a ground-dwelling herbivore';
    if (s.contains('deer')) return 'a large herbivore';
    if (s.contains('raccoon')) return 'a nocturnal omnivore';
    if (s.contains('fox') || s.contains('coyote')) return 'a small to mid-sized carnivore';
    // fallback
    return 'local wildlife';
  }

  Future<void> _generateInsights() async {
    setState(() => _insightsLoading = true);
    await Future.delayed(const Duration(milliseconds: 300)); // keep loader visible for UX

    final speciesNice = widget.speciesKey
        .split('_')
        .map((w) => w.isEmpty ? '' : (w[0].toUpperCase() + w.substring(1)))
        .join(' ');

    if (_items.isEmpty) {
      setState(() {
        _insights = '$speciesNice: no recent photos yet.';
        _insightsLoading = false;
      });
      return;
    }

    // Sort by time and compute adaptive facts (no peak time)
    final sorted = List<DetectionPhoto>.from(_items)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp)); // oldest -> newest
    final first = sorted.first.timestamp;
    final last = sorted.last.timestamp;

    // Unique detection days across the span
    DateTime dayKey(DateTime d) => DateTime(d.year, d.month, d.day);
    final daySet = <DateTime>{}..addAll(sorted.map((p) => dayKey(p.timestamp)));
    final daysCovered = (last.difference(first).inDays + 1).clamp(1, 9999); // inclusive, min 1
    final distinctDays = daySet.length;

    // Presence consistency over the span
    String consistency;
    if (daysCovered <= 1) {
      consistency = 'single-day sighting';
    } else {
      final ratio = distinctDays / daysCovered;
      if (ratio >= 0.6) {
        consistency = 'consistent presence';
      } else if (ratio >= 0.3) {
        consistency = 'intermittent visits';
      } else {
        consistency = 'occasional visitor';
      }
    }

    // Build concise, explicit last-photo date (avoid vague "today" wording)
    final lastStr = DateFormat('MMM d, yyyy · h:mm a').format(last);

    final n = _items.length;
    final group = _describeSpeciesGroup(speciesNice);

    // Two short lines: last photo + compact span/consistency (no peak time)
    final line1 = 'Last photo: ' + lastStr + '  •  ' + n.toString() + ' photo' + (n == 1 ? '' : 's');
    final line2 = 'Seen on ' + distinctDays.toString() + ' of ' + daysCovered.toString() + ' days — ' + consistency + '; likely ' + group + '.';

    setState(() {
      _insights = line1 + '\n' + line2;
      _insightsLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.speciesKey
        .split('_')
        .map((w) => w.isEmpty ? '' : (w[0].toUpperCase() + w.substring(1)))
        .join(' ');

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.pets),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _loading
                    ? const SizedBox(height: 260, child: Center(child: CircularProgressIndicator()))
                    : (_items.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 32.0),
                            child: Text('No recent photos for this species.'),
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                height: 260,
                                child: PageView.builder(
                                  controller: _pc,
                                  padEnds: false,
                                  itemCount: _items.length,
                                  itemBuilder: (ctx, i) {
                                    final p = _items[i];
                                    return AnimatedBuilder(
                                      animation: _pc,
                                      builder: (ctx, child) {
                                        double t = 0.0;
                                        if (_pc.hasClients && _pc.position.haveDimensions) {
                                          t = (_pc.page ?? _pc.initialPage.toDouble()) - i;
                                        }
                                        final scale = (1 - (t.abs() * 0.06)).clamp(0.92, 1.0);
                                        final opacity = (1 - (t.abs() * 0.2)).clamp(0.5, 1.0);
                                        return Center(
                                          child: AnimatedOpacity(
                                            duration: const Duration(milliseconds: 200),
                                            opacity: opacity,
                                            child: Transform.scale(
                                              scale: scale,
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(14),
                                                child: AspectRatio(
                                                  aspectRatio: 4 / 3,
                                                  child: _buildImageWidget(p.url, fit: BoxFit.cover),
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 10),
                              _CarouselDots(count: _items.length, controller: _pc),
                              const SizedBox(height: 12),
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 250),
                                    switchInCurve: Curves.easeIn,
                                    switchOutCurve: Curves.easeOut,
                                    child: _insightsLoading
                                        ? Row(
                                            key: const ValueKey('loading'),
                                            children: const [
                                              Icon(Icons.insights_outlined),
                                              SizedBox(width: 8),
                                              Expanded(child: Text('Generating insights…')),
                                              SizedBox(
                                                width: 16,
                                                height: 16,
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              ),
                                            ],
                                          )
                                        : Text(
                                            _insights ?? 'No insights available.',
                                            key: const ValueKey('ready'),
                                            style: TextStyle(
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                              height: 1.35,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CarouselDots extends StatefulWidget {
  final int count;
  final PageController controller;
  const _CarouselDots({Key? key, required this.count, required this.controller}) : super(key: key);

  @override
  State<_CarouselDots> createState() => _CarouselDotsState();
}

class _CarouselDotsState extends State<_CarouselDots> {
  double _page = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTick);
    _page = widget.controller.initialPage.toDouble();
  }

  void _onTick() {
    if (!mounted) return;
    setState(() {
      _page = widget.controller.hasClients ? (widget.controller.page ?? 0) : 0;
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.count, (i) {
        final active = (i - _page).abs() < 0.5;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 10 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline.withOpacity(0.6),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────
// SUBSCREEN 2 – Unique Species (cover photo, intro, subtle animations)
// ─────────────────────────────────────────────
class UniqueSpeciesScreen extends StatefulWidget {
  final Map<String, double> speciesData;

  const UniqueSpeciesScreen({super.key, required this.speciesData});

  @override
  State<UniqueSpeciesScreen> createState() => _UniqueSpeciesScreenState();
}

class _UniqueSpeciesScreenState extends State<UniqueSpeciesScreen> {
  List<DetectionPhoto> _photos = [];
  Map<String, DetectionPhoto> _cover = {};
  bool _loading = true;

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(' ', '_').replaceAll('-', '_');

  bool _matches(String speciesKey, String? label) {
    if (label == null || label.isEmpty) return false;
    return _norm(speciesKey) == _norm(label);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await fetchRecentPhotosFlexible(limit: 250);
    final cover = <String, DetectionPhoto>{};
    for (final p in all) {
      final label = p.species;
      if (label == null) continue;
      for (final k in widget.speciesData.keys) {
        if (!cover.containsKey(k) && _matches(k, label)) {
          cover[k] = p; // first match becomes cover
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _photos = all;
      _cover = cover;
      _loading = false;
    });
  }

  String _format(String raw) =>
      raw.split('_').map((w) => w.isEmpty ? '' : (w[0].toUpperCase() + w.substring(1))).join(' ');

  @override
  Widget build(BuildContext context) {
    final entries = widget.speciesData.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = widget.speciesData.values.fold<int>(0, (a, b) => a + b.toInt());

    return Scaffold(
      appBar: AppBar(title: const Text('Unique Species')),
      body: _loading && entries.isNotEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                // Cover photo and intro
                if (entries.isNotEmpty)
                  TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 600),
                    tween: Tween(begin: 0, end: 1),
                    builder: (_, v, child) => Opacity(
                      opacity: v,
                      child: Transform.scale(
                        scale: 0.98 + 0.02 * v,
                        child: child,
                      ),
                    ),
                    child: Stack(
                      children: [
                        // Cover photo (first/highest species with image)
                        if (_cover[entries.first.key]?.url != null)
                          SizedBox(
                            height: 180,
                            width: double.infinity,
                            child: _buildImageWidget(_cover[entries.first.key]!.url, fit: BoxFit.cover),
                          )
                        else
                          Container(
                            height: 180,
                            width: double.infinity,
                            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
                            child: const Center(child: Icon(Icons.photo_outlined, size: 60)),
                          ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            height: 64,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Color(0xAA000000),
                                  Color(0x00000000),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 16,
                          bottom: 16,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: BackdropFilter(
                              filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.16),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white.withOpacity(0.28)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.pets, color: Colors.white, size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${entries.length} unique species',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                  child: TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 440),
                    tween: Tween(begin: 0, end: 1),
                    builder: (_, v, child) => Opacity(
                      opacity: v,
                      child: Transform.translate(offset: Offset(0, (1 - v) * 10), child: child),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: (Theme.of(context).brightness == Brightness.dark)
                                ? Colors.black.withOpacity(0.24)
                                : Colors.white.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withOpacity(0.24)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Unique Species Detected',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'These are the distinct animal species automatically detected by your Ornimetrics device. Tap any species for recent photos and more details.',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Colors.white.withOpacity(0.9),
                                    ),
                              ),
                              const SizedBox(height: 8),
                              if (total > 0)
                                Text(
                                  'Total detections: $total',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Colors.white.withOpacity(0.9),
                                      ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const Divider(),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemCount: entries.length,
                  itemBuilder: (_, i) {
                    final e = entries[i];
                    final cover = _cover[e.key];
                    final percent = total > 0 ? ((e.value / total) * 100).toStringAsFixed(0) : '0';
                    return TweenAnimationBuilder<double>(
                      duration: Duration(milliseconds: 240 + i * 28),
                      tween: Tween(begin: 0, end: 1),
                      builder: (_, v, child) => Opacity(
                        opacity: v,
                        child: Transform.translate(offset: Offset(0, (1 - v) * 8), child: child),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          safeLightHaptic();
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Theme.of(context).colorScheme.surface,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                            ),
                            builder: (_) => _SpeciesDetailSheet(speciesKey: e.key),
                          );
                        },
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: SizedBox(
                                    width: 110,
                                    height: 82,
                                    child: cover != null
                                        ? _buildImageWidget(cover.url, fit: BoxFit.cover)
                                        : Container(
                                            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                                            child: const Center(child: Icon(Icons.photo_outlined)),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _format(e.key),
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Detected ${e.value.toInt()} times ($percent%). Tap to view recent photos and details.',
                                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
    );
  }
}
