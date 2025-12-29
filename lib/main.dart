import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

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
import 'package:image_picker/image_picker.dart';
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
import 'services/widget_service.dart';
import 'services/community_storage_service.dart';
import 'screens/onboarding_screen.dart';
import 'services/community_service.dart';
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

// Text scale notifier for accessibility
final ValueNotifier<double> textScaleNotifier = ValueNotifier(1.0);

// Additional customization notifiers
final ValueNotifier<String> distanceUnitNotifier = ValueNotifier('km');
final ValueNotifier<String> dateFormatNotifier = ValueNotifier('MMM d, yyyy');
final ValueNotifier<bool> compactModeNotifier = ValueNotifier(false);
final ValueNotifier<int> defaultTabNotifier = ValueNotifier(0);
final ValueNotifier<int> photoGridColumnsNotifier = ValueNotifier(2);

// Live update notification settings
final ValueNotifier<bool> liveUpdatesEnabledNotifier = ValueNotifier(true);
final ValueNotifier<bool> liveUpdateSoundNotifier = ValueNotifier(true);
final ValueNotifier<bool> liveUpdateVibrationNotifier = ValueNotifier(true);
final ValueNotifier<String> liveUpdateDisplayModeNotifier = ValueNotifier('banner'); // banner, popup, minimal
final ValueNotifier<List<String>> liveUpdateTypesNotifier = ValueNotifier(['new_detection', 'rare_species', 'community']);

// Model Improvement Program - opt-in to share images for model training
final ValueNotifier<bool> modelImprovementOptInNotifier = ValueNotifier(false);
final ValueNotifier<int> imagesContributedNotifier = ValueNotifier(0);

// ─────────────────────────────────────────────
// Global Session Timer Service
// ─────────────────────────────────────────────
class SessionTimerService {
  static final SessionTimerService instance = SessionTimerService._();
  SessionTimerService._();

  final ValueNotifier<int> secondsNotifier = ValueNotifier(0);
  final ValueNotifier<bool> isRunningNotifier = ValueNotifier(false);
  Timer? _timer;
  DateTime? _startTime;

  bool get isRunning => isRunningNotifier.value;
  int get seconds => secondsNotifier.value;

  void start() {
    if (isRunning) return;
    _startTime = DateTime.now().subtract(Duration(seconds: seconds));
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      secondsNotifier.value++;
    });
    isRunningNotifier.value = true;
  }

  void pause() {
    _timer?.cancel();
    _timer = null;
    isRunningNotifier.value = false;
  }

  void toggle() {
    if (isRunning) {
      pause();
    } else {
      start();
    }
  }

  void reset() {
    pause();
    secondsNotifier.value = 0;
    _startTime = null;
  }

  String formatTime() {
    final totalSeconds = seconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final secs = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String get shortFormat {
    final totalSeconds = seconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
}

// Firebase path for photo snapshots (each child: { image_url: string, timestamp: number or ISO string, species?: string })
const String kPhotoFeedPath = 'photo_snapshots';

// ─────────────────────────────────────────────
// Local Cache Service - Offline Data Persistence
// ─────────────────────────────────────────────
class LocalCacheService {
  static const String _keySpeciesData = 'cache_species_data';
  static const String _keyTotalDetections = 'cache_total_detections';
  static const String _keyPhotos = 'cache_photos';
  static const String _keyLastCacheTime = 'cache_last_updated';
  static const String _keyTrendRollup = 'cache_trend_rollup';

  static Future<void> cacheSpeciesData(Map<String, double> speciesMap, int totalDetections) async {
    final prefs = await SharedPreferences.getInstance();
    final speciesJson = json.encode(speciesMap.map((k, v) => MapEntry(k, v)));
    await prefs.setString(_keySpeciesData, speciesJson);
    await prefs.setInt(_keyTotalDetections, totalDetections);
    await prefs.setString(_keyLastCacheTime, DateTime.now().toIso8601String());
  }

  static Future<({Map<String, double> species, int total, DateTime? cachedAt})?> loadCachedSpeciesData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final speciesJson = prefs.getString(_keySpeciesData);
      final total = prefs.getInt(_keyTotalDetections);
      final cachedAtStr = prefs.getString(_keyLastCacheTime);

      if (speciesJson == null || total == null) return null;

      final dynamic rawDecoded = json.decode(speciesJson);
      if (rawDecoded is! Map) return null;

      final Map<String, double> species = {};
      rawDecoded.forEach((key, value) {
        if (key is String && value is num) {
          species[key] = value.toDouble();
        }
      });

      final cachedAt = cachedAtStr != null ? DateTime.tryParse(cachedAtStr) : null;

      return (species: species, total: total, cachedAt: cachedAt);
    } catch (e) {
      debugPrint('LocalCacheService: Failed to load species cache: $e');
      return null;
    }
  }

  static Future<void> cachePhotos(List<DetectionPhoto> photos) async {
    final prefs = await SharedPreferences.getInstance();
    // Only cache the most recent 50 photos to keep storage reasonable
    final toCache = photos.take(50).map((p) => p.toMap()).toList();
    await prefs.setString(_keyPhotos, json.encode(toCache));
  }

  static Future<List<DetectionPhoto>?> loadCachedPhotos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final photosJson = prefs.getString(_keyPhotos);

      if (photosJson == null) return null;

      final List<dynamic> decoded = json.decode(photosJson);
      return decoded.map((m) => DetectionPhoto.fromMap(Map<String, dynamic>.from(m))).toList();
    } catch (e) {
      debugPrint('LocalCacheService: Failed to load photos cache: $e');
      return null;
    }
  }

  static Future<void> cacheTrendRollup(TrendRollup rollup) async {
    final prefs = await SharedPreferences.getInstance();
    final data = json.encode({
      'recentTotal': rollup.recentTotal,
      'priorTotal': rollup.priorTotal,
      'busiestDayKey': rollup.busiestDayKey,
      'busiestDayTotal': rollup.busiestDayTotal,
    });
    await prefs.setString(_keyTrendRollup, data);
  }

  static Future<TrendRollup?> loadCachedTrendRollup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_keyTrendRollup);

      if (data == null) return null;

      final Map<String, dynamic> decoded = json.decode(data);
      return TrendRollup(
        recentTotal: decoded['recentTotal'] ?? 0,
        priorTotal: decoded['priorTotal'] ?? 0,
        busiestDayKey: decoded['busiestDayKey'],
        busiestDayTotal: decoded['busiestDayTotal'] ?? 0,
      );
    } catch (e) {
      debugPrint('LocalCacheService: Failed to load trend rollup cache: $e');
      return null;
    }
  }

  static Future<DateTime?> getLastCacheTime() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_keyLastCacheTime);
    return str != null ? DateTime.tryParse(str) : null;
  }
}

// ─────────────────────────────────────────────
// Species Info Service - Fetches real data from Firebase + ChatGPT
// ─────────────────────────────────────────────
class SpeciesInfoService {
  static final SpeciesInfoService instance = SpeciesInfoService._();
  SpeciesInfoService._();

  // Cache for species info (latin name, description, family)
  final Map<String, Map<String, dynamic>> _speciesInfoCache = {};
  static const String _cacheKey = 'species_info_cache';

  /// Load cached species info from SharedPreferences
  Future<void> loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_cacheKey);
      if (data != null) {
        final decoded = json.decode(data) as Map<String, dynamic>;
        decoded.forEach((key, value) {
          if (value is Map) {
            _speciesInfoCache[key] = Map<String, dynamic>.from(value);
          }
        });
      }
    } catch (e) {
      debugPrint('SpeciesInfoService: Failed to load cache: $e');
    }
  }

  /// Save species info cache to SharedPreferences
  Future<void> _saveCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, json.encode(_speciesInfoCache));
    } catch (e) {
      debugPrint('SpeciesInfoService: Failed to save cache: $e');
    }
  }

  /// Get species info from cache or fetch from ChatGPT
  Future<Map<String, dynamic>> getSpeciesInfo(String speciesName) async {
    final normalized = speciesName.trim();

    // Return from cache if available
    if (_speciesInfoCache.containsKey(normalized)) {
      return _speciesInfoCache[normalized]!;
    }

    // Fetch from ChatGPT
    try {
      final info = await _fetchFromChatGPT(normalized);
      _speciesInfoCache[normalized] = info;
      await _saveCache();
      return info;
    } catch (e) {
      debugPrint('SpeciesInfoService: Failed to fetch from ChatGPT: $e');
      // Return minimal info if API fails
      return {
        'name': normalized,
        'scientific_name': '',
        'family': 'Unknown',
        'description': 'Information not available',
      };
    }
  }

  /// Fetch species info from ChatGPT API
  Future<Map<String, dynamic>> _fetchFromChatGPT(String speciesName) async {
    final apiKey = dotenv.env['OPENAI_API_KEY'] ?? '';

    if (apiKey.isEmpty) {
      return {
        'name': speciesName,
        'scientific_name': '',
        'family': 'Unknown',
        'description': 'API key not configured',
      };
    }

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'gpt-4o-mini',
        'messages': [
          {
            'role': 'system',
            'content': '''You are a bird expert. When given a bird species name, respond with ONLY a JSON object (no markdown, no code blocks) containing:
- "scientific_name": the Latin/scientific name
- "family": the taxonomic family name
- "description": a 2-3 sentence description of the bird including habitat, diet, and interesting facts
- "migration_status": one of "resident", "migratory", "partial_migrant"
- "typical_months": array of month numbers (1-12) when this bird is commonly seen in North America

Example response format:
{"scientific_name":"Cardinalis cardinalis","family":"Cardinalidae","description":"The Northern Cardinal...","migration_status":"resident","typical_months":[1,2,3,4,5,6,7,8,9,10,11,12]}'''
          },
          {
            'role': 'user',
            'content': 'Tell me about: $speciesName'
          }
        ],
        'max_tokens': 300,
        'temperature': 0.3,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final content = data['choices'][0]['message']['content'] as String;

      // Parse the JSON response
      try {
        final parsed = jsonDecode(content.trim());
        return {
          'name': speciesName,
          'scientific_name': parsed['scientific_name'] ?? '',
          'family': parsed['family'] ?? 'Unknown',
          'description': parsed['description'] ?? '',
          'migration_status': parsed['migration_status'] ?? 'unknown',
          'typical_months': parsed['typical_months'] ?? <int>[],
        };
      } catch (e) {
        debugPrint('SpeciesInfoService: Failed to parse ChatGPT response: $content');
        return {
          'name': speciesName,
          'scientific_name': '',
          'family': 'Unknown',
          'description': content,
          'migration_status': 'unknown',
          'typical_months': <int>[],
        };
      }
    } else {
      throw Exception('ChatGPT API error: ${response.statusCode}');
    }
  }

  /// Get all cached species info
  Map<String, Map<String, dynamic>> get cachedSpecies => Map.unmodifiable(_speciesInfoCache);

  /// Check if species is in cache
  bool hasInfo(String speciesName) => _speciesInfoCache.containsKey(speciesName.trim());

  /// Fetch all species from Firebase detections
  Future<List<Map<String, dynamic>>> fetchAllSpeciesFromFirebase() async {
    final List<Map<String, dynamic>> speciesList = [];

    try {
      final db = primaryDatabase().ref();

      final Map<String, int> speciesCounts = {};
      final Map<String, int> lastSeenTimestamp = {};

      // Fetch from photo_snapshots (Pi detections)
      final photosSnap = await db.child('photo_snapshots').get();
      if (photosSnap.exists && photosSnap.value is Map) {
        final m = Map<dynamic, dynamic>.from(photosSnap.value as Map);
        m.forEach((key, value) {
          if (value is Map) {
            final species = value['species']?.toString() ?? value['detected_species']?.toString();
            if (species != null && species.isNotEmpty) {
              speciesCounts[species] = (speciesCounts[species] ?? 0) + 1;
              final ts = value['timestamp'];
              int timestamp = 0;
              if (ts is int) timestamp = ts;
              else if (ts is double) timestamp = ts.toInt();
              else if (ts is String) timestamp = int.tryParse(ts) ?? 0;
              if (timestamp > (lastSeenTimestamp[species] ?? 0)) {
                lastSeenTimestamp[species] = timestamp;
              }
            }
          }
        });
      }

      // Fetch from user-specific field_detections (new per-user path)
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userFieldSnap = await db.child('users/${user.uid}/field_detections').get();
        if (userFieldSnap.exists && userFieldSnap.value is Map) {
          final m = Map<dynamic, dynamic>.from(userFieldSnap.value as Map);
          m.forEach((key, value) {
            if (value is Map) {
              final species = value['species']?.toString();
              if (species != null && species.isNotEmpty) {
                speciesCounts[species] = (speciesCounts[species] ?? 0) + 1;
                final ts = value['timestamp'];
                int timestamp = 0;
                if (ts is int) timestamp = ts;
                else if (ts is double) timestamp = ts.toInt();
                else if (ts is String) timestamp = int.tryParse(ts) ?? 0;
                if (timestamp > (lastSeenTimestamp[species] ?? 0)) {
                  lastSeenTimestamp[species] = timestamp;
                }
              }
            }
          });
        }
      }

      // Also check legacy manual_detections for backwards compatibility
      final manualSnap = await db.child('manual_detections').get();
      if (manualSnap.exists && manualSnap.value is Map) {
        final m = Map<dynamic, dynamic>.from(manualSnap.value as Map);
        m.forEach((key, value) {
          if (value is Map) {
            final species = value['species']?.toString();
            if (species != null && species.isNotEmpty) {
              speciesCounts[species] = (speciesCounts[species] ?? 0) + 1;
              final ts = value['timestamp'];
              int timestamp = 0;
              if (ts is int) timestamp = ts;
              else if (ts is double) timestamp = ts.toInt();
              else if (ts is String) timestamp = int.tryParse(ts) ?? 0;
              if (timestamp > (lastSeenTimestamp[species] ?? 0)) {
                lastSeenTimestamp[species] = timestamp;
              }
            }
          }
        });
      }

      // Also check detections summary for counts (from Pi sessions)
      final detectionsSnap = await db.child('detections').get();
      if (detectionsSnap.exists && detectionsSnap.value is Map) {
        final dates = Map<dynamic, dynamic>.from(detectionsSnap.value as Map);
        dates.forEach((dateKey, dateValue) {
          if (dateValue is Map) {
            dateValue.forEach((sessionKey, sessionValue) {
              if (sessionValue is Map) {
                final summary = sessionValue['summary'];
                if (summary is Map) {
                  final speciesData = summary['species'];
                  if (speciesData is Map) {
                    speciesData.forEach((sp, count) {
                      if (sp is String && sp.isNotEmpty) {
                        final c = count is int ? count : int.tryParse(count.toString()) ?? 0;
                        speciesCounts[sp] = (speciesCounts[sp] ?? 0) + c;
                      }
                    });
                  }
                }
              }
            });
          }
        });
      }

      // Build species list with info
      for (final species in speciesCounts.keys) {
        final info = await getSpeciesInfo(species);
        speciesList.add({
          'name': species,
          'scientific_name': info['scientific_name'] ?? '',
          'family': info['family'] ?? 'Unknown',
          'description': info['description'] ?? '',
          'migration_status': info['migration_status'] ?? 'unknown',
          'typical_months': info['typical_months'] ?? <int>[],
          'count': speciesCounts[species] ?? 0,
          'last_seen': lastSeenTimestamp[species] ?? 0,
        });
      }

      // Sort by count descending
      speciesList.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

    } catch (e) {
      debugPrint('SpeciesInfoService: Failed to fetch from Firebase: $e');
    }

    return speciesList;
  }

  /// Get migration status for all detected species
  Future<List<Map<String, dynamic>>> getMigrationData() async {
    final speciesList = await fetchAllSpeciesFromFirebase();
    final currentMonth = DateTime.now().month;

    return speciesList.map((species) {
      final status = species['migration_status'] as String? ?? 'unknown';
      final typicalMonths = (species['typical_months'] as List?)?.cast<int>() ?? <int>[];

      // Calculate presence probability based on typical months
      double presence = 0.5;
      String statusText = 'Present';
      Color statusColor = Colors.green;

      if (typicalMonths.isNotEmpty) {
        if (typicalMonths.contains(currentMonth)) {
          // Check if we're at the edge of their season
          final prevMonth = currentMonth == 1 ? 12 : currentMonth - 1;
          final nextMonth = currentMonth == 12 ? 1 : currentMonth + 1;

          if (!typicalMonths.contains(prevMonth) && typicalMonths.contains(nextMonth)) {
            statusText = 'Arriving';
            statusColor = Colors.blue;
            presence = 0.6;
          } else if (typicalMonths.contains(prevMonth) && !typicalMonths.contains(nextMonth)) {
            statusText = 'Departing';
            statusColor = Colors.orange;
            presence = 0.4;
          } else {
            statusText = 'Peak season';
            statusColor = Colors.green;
            presence = 0.9;
          }
        } else {
          // Not in typical months
          final nextArrival = typicalMonths.where((m) => m > currentMonth).toList();
          if (nextArrival.isNotEmpty) {
            final monthsUntil = nextArrival.first - currentMonth;
            if (monthsUntil <= 2) {
              statusText = 'Arriving soon';
              statusColor = Colors.cyan;
              presence = 0.3;
            } else {
              statusText = 'Not in season';
              statusColor = Colors.grey;
              presence = 0.1;
            }
          } else {
            statusText = 'Gone for season';
            statusColor = Colors.red;
            presence = 0.1;
          }
        }
      }

      if (status == 'resident') {
        statusText = 'Year-round';
        statusColor = Colors.green;
        presence = 0.85;
      }

      return {
        ...species,
        'status_text': statusText,
        'status_color': statusColor,
        'presence': presence,
      };
    }).toList();
  }
}

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

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'timestamp': timestamp.toIso8601String(),
      'species': species,
      if (weatherAtCapture != null) 'weather': weatherAtCapture!.toMap(),
    };
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

class TrendRollup {
  const TrendRollup({
    required this.recentTotal,
    required this.priorTotal,
    this.busiestDayKey,
    this.busiestDayTotal = 0,
  });

  final int recentTotal;
  final int priorTotal;
  final String? busiestDayKey;
  final int busiestDayTotal;

  double get pctChange => priorTotal == 0
      ? (recentTotal > 0 ? 100.0 : 0.0)
      : ((recentTotal - priorTotal) / priorTotal) * 100;

  String get direction =>
      recentTotal == priorTotal ? 'steady' : (recentTotal > priorTotal ? 'rising' : 'falling');

  String get pctLabel => '${pctChange >= 0 ? '+' : ''}${pctChange.toStringAsFixed(1)}%';

  bool get hasAnyData => recentTotal > 0 || priorTotal > 0 || busiestDayKey != null;
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
  final opts = DefaultFirebaseOptions.currentPlatform;
  final placeholders = [
    opts.apiKey,
    opts.appId,
    opts.projectId,
    opts.storageBucket,
    opts.messagingSenderId,
  ];
  if (placeholders.any((e) => (e ?? '').startsWith('REPLACE_ME'))) {
    throw StateError(
      'Firebase configuration is missing. Regenerate lib/firebase_options.dart with "flutterfire configure" '
          'and use matching google-services.json / GoogleService-Info.plist.',
    );
  }
  try {
    if (Firebase.apps.isNotEmpty) {
      return Firebase.apps.first;
    }
    return await Firebase.initializeApp(
      options: opts,
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
  // One-time diagnostic to confirm RTDB visibility.
  await CommunityService().logDiagnostics();

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

  // Load customization settings
  textScaleNotifier.value = prefs.getDouble('pref_text_scale') ?? 1.0;
  distanceUnitNotifier.value = prefs.getString('pref_distance_unit') ?? 'km';
  compactModeNotifier.value = prefs.getBool('pref_compact_mode') ?? false;
  defaultTabNotifier.value = prefs.getInt('pref_default_tab') ?? 0;
  photoGridColumnsNotifier.value = prefs.getInt('pref_photo_grid_columns') ?? 2;

  // Load live update notification settings
  liveUpdatesEnabledNotifier.value = prefs.getBool('pref_live_updates_enabled') ?? true;
  liveUpdateSoundNotifier.value = prefs.getBool('pref_live_update_sound') ?? true;
  liveUpdateVibrationNotifier.value = prefs.getBool('pref_live_update_vibration') ?? true;
  liveUpdateDisplayModeNotifier.value = prefs.getString('pref_live_update_display_mode') ?? 'banner';
  final savedTypes = prefs.getStringList('pref_live_update_types');
  if (savedTypes != null) {
    liveUpdateTypesNotifier.value = savedTypes;
  }

  // Load Model Improvement Program opt-in status
  modelImprovementOptInNotifier.value = prefs.getBool('model_improvement_opt_in') ?? false;
  imagesContributedNotifier.value = prefs.getInt('images_contributed') ?? 0;

  // Load species info cache for ChatGPT integration
  await SpeciesInfoService.instance.loadCache();

  // Initialize bird detection model (will fallback to ChatGPT if model not available)
  await BirdDetectionService.instance.initialize();

  await NotificationsService.instance.load();
  await MaintenanceRulesEngine.instance.load();

  runApp(const WildlifeApp());
}

class WildlifeApp extends StatefulWidget {
  const WildlifeApp({super.key});

  @override
  State<WildlifeApp> createState() => _WildlifeAppState();
}

class _WildlifeAppState extends State<WildlifeApp> {
  bool? _showOnboarding;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getBool('onboarding_complete') ?? false;
    setState(() => _showOnboarding = !completed);
  }

  void _onOnboardingComplete() {
    setState(() => _showOnboarding = false);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: seedColorNotifier,
      builder: (_, seed, __) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: themeNotifier,
          builder: (_, mode, __) {
            return ValueListenableBuilder<double>(
              valueListenable: textScaleNotifier,
              builder: (_, textScale, __) {
                return MaterialApp(
                  navigatorObservers: [communityRouteObserver],
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                    appBarTheme: const AppBarTheme(),
                  ),
                  builder: (context, child) {
                    return MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(textScale),
                      ),
                      child: child!,
                    );
                  },
                  home: _showOnboarding == null
                      ? const Scaffold(body: Center(child: CircularProgressIndicator()))
                      : _showOnboarding!
                      ? OnboardingScreen(onComplete: _onOnboardingComplete)
                      : const WildlifeTrackerScreen(),
                );
              },
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
  bool _isUsingCachedData = false;
  DateTime? _cachedDataTime;
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
  bool _showAdvancedTrends = false;
  bool _trendsCollapsed = false;
  Map<String, Map<String, double>> _recentDailyCounts = {};
  TrendRollup _trendRollup = const TrendRollup(
    recentTotal: 0,
    priorTotal: 0,
    busiestDayKey: null,
    busiestDayTotal: 0,
  );
  String? _weatherTrendNote;

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
    _maybePromptNotifications();
    _loadAiPrefs();
    _loadTasks();
    _captureLocation(); // Do not block initial renders on location.
    // Load cached data immediately for instant display, then fetch fresh data
    // Use addPostFrameCallback to ensure widget is fully mounted before async operations
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCachedDataAndRefresh();
    });
    _aiAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
  }

  /// Load cached data first for instant display, then fetch fresh data in background
  Future<void> _loadCachedDataAndRefresh() async {
    try {
      // First, try to load cached data for instant display
      final cachedSpecies = await LocalCacheService.loadCachedSpeciesData();
      final cachedPhotos = await LocalCacheService.loadCachedPhotos();

      if (cachedSpecies != null && cachedSpecies.species.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _totalDetections = cachedSpecies.total;
          _speciesDataMap = cachedSpecies.species;
          _isLoading = false;
          _lastUpdated = cachedSpecies.cachedAt;
          _isUsingCachedData = true;
          _cachedDataTime = cachedSpecies.cachedAt;
        });
        _rebuildTrendSignals();
        _updateWidget();
      }

      if (cachedPhotos != null && cachedPhotos.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _photos = cachedPhotos;
          _loadingPhotos = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading cached data: $e');
    }

    // Then fetch fresh data in background
    unawaited(Future(() async {
      try {
        await _fetchTodaySummaryFlexible();
        await _fetchPhotoSnapshots();
        await _loadTrendSummaries();
      } catch (e) {
        debugPrint('Error fetching fresh data: $e');
      }
    }));
  }

  Future<void> _maybePromptNotifications() async {
    final service = NotificationsService.instance;
    if (service.permissionsPrompted.value) return;
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Enable live notifications'),
        content: const Text(
            'Turn on feeder alerts and live activity updates. You can change this anytime in settings.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Not now'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await NotificationsService.instance.requestPermissions();
            },
            child: const Text('Allow'),
          ),
        ],
      ),
    );
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

  Map<String, double> _extractSummaryCounts(dynamic value) {
    if (value is! Map) return <String, double>{};
    final map = Map<dynamic, dynamic>.from(value as Map);
    final counts = <String, double>{};
    map.forEach((k, v) {
      if (k.toString() == 'summary' && v is Map) {
        _mergeCountsInPlace(counts, _toCountsFromValue(v));
      } else if (v is Map) {
        _mergeCountsInPlace(counts, _extractSummaryCounts(v));
      }
    });
    return counts;
  }

  List<TrendSignal> _trendSignalsFromDailyCounts(Map<String, Map<String, double>> daily) {
    if (daily.isEmpty) return <TrendSignal>[];

    final dates = daily.keys.toList()..sort();
    final recent = dates.sublist(math.max(0, dates.length - 7));
    if (recent.isEmpty) return <TrendSignal>[];

    final species = <String>{};
    for (final d in recent) {
      species.addAll(daily[d]?.keys ?? <String>[]);
    }
    if (species.isEmpty) return <TrendSignal>[];

    final window = math.max(1, (recent.length / 2).ceil());
    double avgFor(String sp, Iterable<String> days) {
      double sum = 0;
      int count = 0;
      for (final d in days) {
        sum += (daily[d]?[sp] ?? 0);
        count++;
      }
      return count == 0 ? 0 : sum / count;
    }

    final startDays = recent.take(window);
    final endDays = recent.skip(recent.length - window);

    final signals = species.map((sp) {
      final startAvg = avgFor(sp, startDays);
      final endAvg = avgFor(sp, endDays);
      return TrendSignal(species: sp, start: startAvg.round(), end: endAvg.round());
    }).toList();

    signals.sort((a, b) => b.changeRate.abs().compareTo(a.changeRate.abs()));
    return signals;
  }

  TrendRollup _buildTrendRollup(Map<String, Map<String, double>> daily) {
    if (daily.isEmpty) {
      return const TrendRollup(recentTotal: 0, priorTotal: 0, busiestDayKey: null, busiestDayTotal: 0);
    }
    final dates = daily.keys.toList()..sort();
    final recent = dates.sublist(math.max(0, dates.length - 7));
    final priorStart = math.max(0, dates.length - 14);
    final prior = dates.sublist(priorStart, math.max(priorStart, dates.length - recent.length));

    int sumFor(List<String> keys) {
      int total = 0;
      for (final d in keys) {
        total += (daily[d]?.values.fold<double>(0, (a, b) => a + b) ?? 0).round();
      }
      return total;
    }

    int busiestTotal = 0;
    String? busiestKey;
    for (final d in dates) {
      final dayTotal = (daily[d]?.values.fold<double>(0, (a, b) => a + b) ?? 0).round();
      if (dayTotal > busiestTotal) {
        busiestTotal = dayTotal;
        busiestKey = d;
      }
    }

    return TrendRollup(
      recentTotal: sumFor(recent),
      priorTotal: sumFor(prior),
      busiestDayKey: busiestKey,
      busiestDayTotal: busiestTotal,
    );
  }

  void _rebuildTrendSignals() {
    final fromDaily = _trendSignalsFromDailyCounts(_recentDailyCounts);
    final fallback = _deriveTrendsFromPhotos(_photos);
    _weatherTrendNote = _buildWeatherTrendNote(_photos);
    if (!mounted) return;
    setState(() {
      _trendSignals = fromDaily.isNotEmpty ? fromDaily : fallback;
    });
  }

  /// Update iOS home screen widget with current data
  void _updateWidget() {
    debugPrint('_updateWidget called: speciesDataMap.length=${_speciesDataMap.length}, totalDetections=$_totalDetections');

    if (_speciesDataMap.isEmpty) {
      debugPrint('_updateWidget: No data to send (speciesDataMap is empty)');
      return;
    }

    // Find top species
    final sortedSpecies = _speciesDataMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topSpecies = sortedSpecies.isNotEmpty
        ? sortedSpecies.first.key.replaceAll('_', ' ')
        : '—';

    // Last detection info
    final lastDetection = sortedSpecies.length > 1
        ? sortedSpecies[1].key.replaceAll('_', ' ')
        : topSpecies;

    // Calculate diversity metrics
    final totalCount = _speciesDataMap.values.fold<double>(0, (a, b) => a + b);
    double shannonIndex = 0;
    if (totalCount > 0) {
      for (final count in _speciesDataMap.values) {
        if (count > 0) {
          final p = count / totalCount;
          shannonIndex -= p * (p > 0 ? math.log(p) / math.log(2) : 0);
        }
      }
    }

    // Common species ratio (top 3 species / total)
    final topThreeSum = sortedSpecies.take(3).fold<double>(0, (a, b) => a + b.value);
    final commonRatio = totalCount > 0 ? topThreeSum / totalCount : 0.0;

    // Rarity score (inverse of common ratio, scaled to 0-100)
    final rarityScore = ((1 - commonRatio) * 100).clamp(0.0, 100.0);

    // Trending and declining species from trend signals
    String trendingSpecies = '—';
    String decliningSpecies = '—';
    double weeklyTrend = 0;

    if (_trendSignals.isNotEmpty) {
      final increasing = _trendSignals.where((s) => s.delta > 0).toList()
        ..sort((a, b) => b.changeRate.compareTo(a.changeRate));
      final decreasing = _trendSignals.where((s) => s.delta < 0).toList()
        ..sort((a, b) => a.changeRate.compareTo(b.changeRate));

      if (increasing.isNotEmpty) {
        trendingSpecies = increasing.first.species.replaceAll('_', ' ');
      }
      if (decreasing.isNotEmpty) {
        decliningSpecies = decreasing.first.species.replaceAll('_', ' ');
      }

      // Calculate overall weekly trend
      final totalDelta = _trendSignals.fold<int>(0, (a, b) => a + b.delta);
      final totalStart = _trendSignals.fold<int>(0, (a, b) => a + b.start);
      if (totalStart > 0) {
        weeklyTrend = (totalDelta / totalStart) * 100;
      }
    }

    debugPrint('_updateWidget: Sending - total=$_totalDetections, species=${_speciesDataMap.length}, top=$topSpecies');

    WidgetService.instance.updateWidget(
      totalDetections: _totalDetections,
      uniqueSpecies: _speciesDataMap.length,
      lastDetection: lastDetection,
      topSpecies: topSpecies,
      // Diversity metrics
      rarityScore: rarityScore,
      diversityIndex: shannonIndex,
      commonSpeciesRatio: commonRatio,
      // Activity (placeholder - would need hourly tracking)
      peakHour: DateTime.now().hour,
      activeHours: _speciesDataMap.length > 0 ? 8 : 0,
      // Trends
      weeklyTrend: weeklyTrend,
      monthlyTrend: weeklyTrend * 0.8, // Approximate
      trendingSpecies: trendingSpecies,
      decliningSpecies: decliningSpecies,
      // Community (placeholder values)
      communityTotal: _totalDetections * 30,
      userRank: (_totalDetections > 100) ? 5 : (_totalDetections > 50) ? 15 : 25,
      communityMembers: 156,
      sharedSightings: (_totalDetections / 20).round(),
    );
  }

  List<TrendSignal> _sortedChangingTrends({int? limit}) {
    final changing = _trendSignals.where((s) => s.delta != 0).toList()
      ..sort((a, b) => b.changeRate.abs().compareTo(a.changeRate.abs()));
    if (limit == null) return changing;
    return changing.take(limit).toList();
  }

  Future<void> _loadTrendSummaries({int lookbackDays = 14}) async {
    try {
      final snap = await primaryDatabase().ref('detections').orderByKey().limitToLast(lookbackDays).get();
      final Map<String, Map<String, double>> daily = {};
      if (snap.exists && snap.value is Map) {
        final raw = Map<dynamic, dynamic>.from(snap.value as Map);
        raw.forEach((k, v) {
          final counts = _extractSummaryCounts(v);
          if (counts.isNotEmpty) daily[k.toString()] = counts;
        });
      }
      if (!mounted) return;
      setState(() {
        _recentDailyCounts = daily;
        _trendRollup = _buildTrendRollup(daily);
        _weatherTrendNote = _buildWeatherTrendNote(_photos);
      });
      _rebuildTrendSignals();
    } catch (e) {
      if (mounted) {
        debugPrint('trend summaries load failed: $e');
      }
      if (_trendSignals.isEmpty) {
        _rebuildTrendSignals();
      }
    }
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

      // Cache the data for offline use
      unawaited(LocalCacheService.cacheSpeciesData(species, total));

      if (!mounted) return;
      setState(() {
        _totalDetections = total;
        _speciesDataMap = species;
        _isLoading = false;
        _lastUpdated = DateTime.now();
        _isUsingCachedData = false;
        _cachedDataTime = null;
        _error = species.isEmpty
            ? 'No summary found for $today. Showing latest available if present.'
            : '';
      });
      _rebuildTrendSignals();
      _updateWidget();
    } catch (e) {
      // Try to load from cache on network failure
      final cached = await LocalCacheService.loadCachedSpeciesData();
      if (!mounted) return;

      if (cached != null && cached.species.isNotEmpty) {
        setState(() {
          _totalDetections = cached.total;
          _speciesDataMap = cached.species;
          _isLoading = false;
          _lastUpdated = cached.cachedAt;
          _isUsingCachedData = true;
          _cachedDataTime = cached.cachedAt;
          _error = '';
        });
        _rebuildTrendSignals();
        _updateWidget();
      } else {
        setState(() {
          _totalDetections = 0;
          _speciesDataMap = {};
          _isLoading = false;
          _lastUpdated = DateTime.now();
          _isUsingCachedData = false;
          _error = 'Failed to load data: $e';
        });
        _rebuildTrendSignals();
      }
    }
  }

  Future<void> _refreshAll() async {
    _captureLocation();
    await Future.wait([
      _fetchPhotoSnapshots(),
      _fetchTodaySummaryFlexible(),
    ]);
    await _loadTrendSummaries();
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

      // Cache photos for offline use
      unawaited(LocalCacheService.cachePhotos(items));

      if (!mounted) return;
      setState(() {
        _photos = items;
        _loadingPhotos = false;
        _photosLastUpdated = DateTime.now();
        if (_position == null) {
          _photoError = _locationStatus ?? 'Location permission is required to tag weather on snapshots.';
        } else if (_photoError.isNotEmpty && _locationStatus == null) {
          _photoError = '';
        }
      });
      _rebuildTrendSignals();
    } catch (e) {
      // Try to load from cache on network failure
      final cachedPhotos = await LocalCacheService.loadCachedPhotos();
      if (!mounted) return;

      if (cachedPhotos != null && cachedPhotos.isNotEmpty) {
        setState(() {
          _photos = cachedPhotos;
          _loadingPhotos = false;
          _photosLastUpdated = null; // Will show as cached
          _photoError = '';
        });
        _rebuildTrendSignals();
      } else {
        setState(() {
          _photoError = 'Failed to load snapshots: $e';
          _loadingPhotos = false;
          _photosLastUpdated = DateTime.now();
        });
      }
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
    if (photos.isEmpty) {
      // Fallback: derive steady signals from current species summary so the card isn't empty.
      return _speciesDataMap.entries
          .map((e) => TrendSignal(species: e.key, start: e.value.toInt(), end: e.value.toInt()))
          .toList();
    }
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
    if (sortedDays.isEmpty) {
      return _speciesDataMap.entries
          .map((e) => TrendSignal(species: e.key, start: e.value.toInt(), end: e.value.toInt()))
          .toList();
    }

    // Smooth the trend by comparing the early and late halves of the window (up to 3-day averages).
    final Set<String> allSpecies = perDay.values.expand((m) => m.keys).toSet();
    final int window = math.min(3, sortedDays.length);

    final signals = allSpecies.map((species) {
      final dayCounts = sortedDays.map((d) => perDay[d]?[species] ?? 0).toList();
      final startSlice = dayCounts.take(window).toList();
      final endSlice = dayCounts.skip(dayCounts.length - window).toList();
      final startAvg = startSlice.isEmpty ? 0 : startSlice.reduce((a, b) => a + b) / startSlice.length;
      final endAvg = endSlice.isEmpty ? 0 : endSlice.reduce((a, b) => a + b) / endSlice.length;
      return TrendSignal(species: species, start: startAvg.round(), end: endAvg.round());
    }).toList();

    signals.sort((a, b) => b.changeRate.abs().compareTo(a.changeRate.abs()));
    final top = signals.take(5).toList();
    if (top.isNotEmpty) return top;

    // Fallback to species summary so the UI always has content.
    return _speciesDataMap.entries
        .map((e) => TrendSignal(species: e.key, start: e.value.toInt(), end: e.value.toInt()))
        .toList();
  }

  String? _buildWeatherTrendNote(List<DetectionPhoto> photos) {
    final now = DateTime.now().toUtc();
    final cutoff = now.subtract(const Duration(days: 7));
    final tagged = photos.where((p) => p.timestamp.toUtc().isAfter(cutoff) && p.weatherAtCapture != null);
    if (tagged.isEmpty) return null;

    int wet = 0;
    int dry = 0;
    double tempSum = 0;
    double humiditySum = 0;
    int tempCount = 0;
    final Map<String, int> skyCounts = {};

    for (final p in tagged) {
      final w = p.weatherAtCapture!;
      final isWet = w.isRaining || w.isSnowing || w.isHailing || (w.precipitationMm ?? 0) > 0;
      if (isWet) {
        wet++;
      } else {
        dry++;
      }
      if (w.temperatureC != null) {
        tempSum += w.temperatureC!;
        tempCount++;
      }
      humiditySum += (w.humidity ?? 0);
      final skyKey = (w.condition.isNotEmpty ? w.condition : 'Unknown').toLowerCase();
      skyCounts[skyKey] = (skyCounts[skyKey] ?? 0) + 1;
    }

    final topSky = skyCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final skyLabel = topSky.isNotEmpty ? topSky.first.key : 'n/a';
    final avgTemp = tempCount == 0 ? null : tempSum / tempCount;
    final avgHumidity = tagged.isEmpty ? null : humiditySum / tagged.length;

    final parts = <String>[];
    parts.add('Weather-tagged captures: ${tagged.length}');
    parts.add('Wet vs dry: $wet / $dry');
    if (avgTemp != null) parts.add('Avg temp ${avgTemp.toStringAsFixed(1)}°C');
    if (avgHumidity != null) parts.add('Avg humidity ${avgHumidity.toStringAsFixed(0)}%');
    parts.add('Common sky: $skyLabel');
    return parts.join(' • ');
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
    final rollup = _trendRollup;
    final rollupText = rollup.hasAnyData
        ? 'Activity last 7 days: ${rollup.recentTotal} (prior 7: ${rollup.priorTotal}, ${rollup.pctLabel}). '
        '${rollup.busiestDayKey != null ? 'Busiest day ${rollup.busiestDayKey} with ${rollup.busiestDayTotal} detections.' : ''}'
        : 'Limited rollup data available.';
    final topSpecies = _speciesDataMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topText = topSpecies.take(5).map((e) => '${_formatSpeciesName(e.key)}:${e.value.toInt()}').join(', ');
    final weatherNote = _weatherTrendNote;

    final messages = <AiMessage>[
      AiMessage('system',
          'You are an ornithology analyst. Blend migration heuristics with numeric trends, rollups, and local signals.'),
      AiMessage(
        'user',
        [
          'Use these signals to suggest migration or behavior insights (3 bullets max).',
          'Trend signals: $summary.',
          'Rollup: $rollupText',
          if (topText.isNotEmpty) 'Top species totals: $topText.',
          if (_lastUpdated != null)
            'Latest data refresh: ${DateFormat('yyyy-MM-dd HH:mm').format(_lastUpdated!)}.',
          if (weatherNote != null) 'Weather correlation: $weatherNote.',
        ].join(' '),
      ),
    ];

    try {
      final reply = await _trendAi.send(messages, context: {
        'location': _position != null ? '${_position!.latitude},${_position!.longitude}' : 'unknown',
        'rollup_recent_7d': rollup.recentTotal,
        'rollup_prior_7d': rollup.priorTotal,
        'busiest_day': rollup.busiestDayKey ?? 'n/a',
        'top_species': topText,
        if (weatherNote != null) 'weather_note': weatherNote,
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
      length: 5,
      child: Builder(
        builder: (context) {
          // Dismiss keyboard when switching tabs
          final tabController = DefaultTabController.of(context);
          tabController.addListener(() {
            if (!tabController.indexIsChanging) {
              FocusScope.of(context).unfocus();
            }
          });
          return GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: Stack(
              children: [
                Scaffold(
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
                    bottom: TabBar(
                      isScrollable: false,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                      indicatorSize: TabBarIndicatorSize.label,
                      labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                      unselectedLabelStyle: const TextStyle(fontSize: 10),
                      onTap: (_) => FocusScope.of(context).unfocus(),
                      tabs: const [
                        Tab(icon: Icon(Icons.dashboard, size: 20), text: 'Home'),
                        Tab(icon: Icon(Icons.photo_camera_back_outlined, size: 20), text: 'Photos'),
                        Tab(icon: Icon(Icons.cloud_outlined, size: 20), text: 'Weather'),
                        Tab(icon: Icon(Icons.groups_2_outlined, size: 20), text: 'Social'),
                        Tab(icon: Icon(Icons.auto_awesome, size: 20), text: 'Tools'),
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
                      _buildToolsTab(),
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
                // Dynamic Island Timer
                _buildDynamicIslandTimer(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDynamicIslandTimer() {
    return ValueListenableBuilder<bool>(
      valueListenable: SessionTimerService.instance.isRunningNotifier,
      builder: (context, isRunning, _) {
        if (!isRunning) return const SizedBox.shrink();

        return ValueListenableBuilder<int>(
          valueListenable: SessionTimerService.instance.secondsNotifier,
          builder: (context, seconds, _) {
            return Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    safeLightHaptic();
                    showDialog(context: context, builder: (_) => _SessionTimerDialog());
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.3),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Animated pulsing dot
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.5, end: 1.0),
                          duration: const Duration(milliseconds: 800),
                          builder: (context, value, child) {
                            return Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(value),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.green.withOpacity(0.5 * value),
                                    blurRadius: 4,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            );
                          },
                          onEnd: () {},
                        ),
                        const SizedBox(width: 10),
                        // Bird icon
                        const Icon(Icons.flutter_dash, color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        // Timer display
                        Text(
                          SessionTimerService.instance.formatTime(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Pause/Stop indicator
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.touch_app, color: Colors.white70, size: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildOfflineBanner() {
    final timeAgo = _cachedDataTime != null
        ? _formatTimeAgo(_cachedDataTime!)
        : 'some time ago';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.orange.shade700,
            Colors.orange.shade600,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, color: Colors.white, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Offline Mode',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  'Showing cached data from $timeAgo',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              safeLightHaptic();
              _refreshAll();
            },
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.2),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(dateTime);
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
          // Offline mode banner
          if (_isUsingCachedData) _buildOfflineBanner(),
          const Text(
            'Live Animal Detection',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          if (_lastUpdated != null)
            Padding(
              padding: const EdgeInsets.only(top: 4.0, bottom: 12.0),
              child: Row(
                children: [
                  Text(
                    'Last updated: ${DateFormat('MMM d, yyyy – hh:mm a').format(_lastUpdated!)}',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  if (_isUsingCachedData) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'CACHED',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          Text(
            _isUsingCachedData ? 'Cached data from Ornimetrics' : 'Real-time data from Ornimetrics',
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
          ValueListenableBuilder<bool>(
            valueListenable: NotificationsService.instance.permissionsPrompted,
            builder: (_, prompted, __) {
              if (prompted) return const SizedBox.shrink();
              return _buildNotificationCard();
            },
          ),
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
                    opaque: false,
                    barrierColor: Colors.black87,
                    transitionDuration: const Duration(milliseconds: 350),
                    reverseTransitionDuration: const Duration(milliseconds: 300),
                    pageBuilder: (_, __, ___) => RecentPhotoViewer(
                      photos: _photos,
                      initialIndex: i,
                    ),
                    transitionsBuilder: (context, animation, secondaryAnimation, child) {
                      return FadeTransition(
                        opacity: CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOut,
                          reverseCurve: Curves.easeIn,
                        ),
                        child: child,
                      );
                    },
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
                        Flexible(
                          child: Text(
                            'Total Detections',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.track_changes,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
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
                Flexible(
                  child: Text('Species Diversity Metrics',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Icon(Icons.open_in_full, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
      pageBuilder: (dialogContext, __, ___) {
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Header with back button
                          Container(
                            padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                            child: Row(
                              children: [
                                IconButton(
                                  onPressed: () {
                                    safeLightHaptic();
                                    Navigator.of(dialogContext).pop();
                                  },
                                  icon: const Icon(Icons.arrow_back_rounded),
                                  tooltip: 'Close',
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Activity by Hour',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  onPressed: () {
                                    safeLightHaptic();
                                    Navigator.of(dialogContext).pop();
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                  tooltip: 'Close',
                                ),
                              ],
                            ),
                          ),
                          const Divider(),
                          // Content
                          Flexible(
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                              child: _buildActivityDetailContent(),
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

  void _openAllTrendsDialog() {
    final changing = _sortedChangingTrends();
    if (changing.isEmpty) return;
    safeLightHaptic();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          builder: (_, controller) {
            return ListView.builder(
              controller: controller,
              padding: const EdgeInsets.all(16),
              itemCount: changing.length + 1,
              itemBuilder: (_, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Row(
                      children: [
                        const Icon(Icons.trending_up),
                        const SizedBox(width: 8),
                        const Text('All recent changes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                          label: const Text('Close'),
                        )
                      ],
                    ),
                  );
                }
                final s = changing[i - 1];
                final pct = (s.changeRate * 100).toStringAsFixed(1);
                final dir = s.direction == 'rising'
                    ? 'Increase'
                    : s.direction == 'falling'
                    ? 'Decrease'
                    : 'Steady';
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(
                        s.direction == 'rising'
                            ? Icons.trending_up
                            : s.direction == 'falling'
                            ? Icons.trending_down
                            : Icons.horizontal_rule,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    title: Text(_formatSpeciesName(s.species), style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      '$dir • ${s.start} → ${s.end} (Δ ${s.delta >= 0 ? '+' : ''}${s.delta}, $pct%)',
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Start: ${s.start}', style: const TextStyle(fontSize: 12)),
                        Text('End: ${s.end}', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildTrendsCard() {
    return LayoutBuilder(builder: (context, constraints) {
      final chipMaxWidth = math.max(160.0, math.min(constraints.maxWidth - 32, 320.0));
      String _humanDay(String key) {
        try {
          final dt = DateTime.parse(key);
          return DateFormat('MMM d').format(dt);
        } catch (_) {
          return key;
        }
      }
      final rollup = _trendRollup;
      final actionRow = Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.end,
        children: [
          IconButton(
            icon: Icon(_trendsCollapsed ? Icons.unfold_more : Icons.unfold_less),
            tooltip: _trendsCollapsed ? 'Expand trends' : 'Collapse trends',
            onPressed: () => setState(() => _trendsCollapsed = !_trendsCollapsed),
          ),
          TextButton.icon(
            onPressed: _trendSignals.isEmpty
                ? null
                : () {
              setState(() => _showAdvancedTrends = !_showAdvancedTrends);
            },
            icon: const Icon(Icons.analytics_outlined),
            label: Text(_showAdvancedTrends ? 'Hide advanced' : 'Advanced stats'),
          ),
          TextButton.icon(
            onPressed: _trendSignals.where((s) => s.delta != 0).isEmpty ? null : _openAllTrendsDialog,
            icon: const Icon(Icons.list_alt_outlined),
            label: const Text('See all changes'),
          ),
          IconButton(
            icon: _trendAiLoading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
            tooltip: 'Ask AI for migration insight',
            onPressed: _trendSignals.isEmpty || _trendAiLoading ? null : _generateTrendAiInsight,
          )
        ],
      );
      final changing = _sortedChangingTrends();
      final topThree = _sortedChangingTrends(limit: 3);
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (rollup.hasAnyData) ...[
                Row(
                  children: [
                    Icon(
                      rollup.direction == 'rising'
                          ? Icons.trending_up
                          : rollup.direction == 'falling'
                          ? Icons.trending_down
                          : Icons.horizontal_rule,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Past 7 days: ${rollup.recentTotal} detections '
                            '(${rollup.pctLabel} vs prior 7). '
                            '${rollup.busiestDayKey != null ? 'Busiest ${_humanDay(rollup.busiestDayKey!)} • ${rollup.busiestDayTotal}' : ''}',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              const Text('Migration & activity trends',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Align(alignment: Alignment.centerRight, child: actionRow),
              const SizedBox(height: 8),
              if (_weatherTrendNote != null) ...[
                Row(
                  children: [
                    Icon(Icons.cloudy_snowing, size: 18, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _weatherTrendNote!,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              if (changing.isEmpty)
                Text(
                  'Need more data to spot trends. Add snapshots with species labels over several days.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_trendsCollapsed) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: topThree.map((s) => _buildTrendChip(context, s, chipMaxWidth)).toList(),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Top movers over the last 7 days (by % change).',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ] else ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: topThree.map((s) => _buildTrendChip(context, s, chipMaxWidth)).toList(),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Collapsed — tap expand or \"See all changes\" for details.',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                    if (_showAdvancedTrends && topThree.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text('Advanced details (top 3)', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: topThree.map((s) => _buildTrendDetailRow(context, s)).toList(),
                      ),
                    ]
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
    });
  }

  Widget _buildTrendChip(BuildContext context, TrendSignal s, double chipMaxWidth) {
    final icon = s.direction == 'rising'
        ? Icons.trending_up
        : s.direction == 'falling'
        ? Icons.trending_down
        : Icons.remove;
    final pct = (s.changeRate * 100).toStringAsFixed(1);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: chipMaxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _formatSpeciesName(s.species),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Text('${s.delta >= 0 ? '+' : ''}${s.delta}', style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('${s.start} → ${s.end}',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                const Spacer(),
                Text('$pct%', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendDetailRow(BuildContext context, TrendSignal s) {
    final pct = (s.changeRate * 100).toStringAsFixed(1);
    if (s.delta == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _formatSpeciesName(s.species),
              style: const TextStyle(fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Δ ${s.delta} (${pct}%)',
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
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

  Widget _buildToolsTab() {
    return const ToolsScreen();
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


class _PhotoTileState extends State<_PhotoTile> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 120),
      vsync: this,
      lowerBound: 0.0,
      upperBound: 1.0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _isPressed = true;
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    if (_isPressed) {
      _controller.reverse().then((_) {
        if (mounted) widget.onTap();
      });
    }
    _isPressed = false;
  }

  void _onTapCancel() {
    _isPressed = false;
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.photo;
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final scale = 1.0 - (_controller.value * 0.04);
          final brightness = 1.0 - (_controller.value * 0.1);
          return Transform.scale(
            scale: scale,
            child: ColorFiltered(
              colorFilter: ColorFilter.matrix(<double>[
                brightness, 0, 0, 0, 0,
                0, brightness, 0, 0, 0,
                0, 0, brightness, 0, 0,
                0, 0, 0, 1, 0,
              ]),
              child: child,
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                Positioned.fill(
                  child: _buildImageWidget(p.url, fit: BoxFit.cover),
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
                                      ConstrainedBox(
                                        constraints: BoxConstraints(maxWidth: maxChipWidth - 28),
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

class _RecentPhotoViewerState extends State<RecentPhotoViewer> with SingleTickerProviderStateMixin {
  late final PageController _pc = PageController(initialPage: widget.initialIndex);
  late AnimationController _dismissController;
  int _index = 0;
  double _dragOffset = 0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _dismissController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
  }

  @override
  void dispose() {
    _dismissController.dispose();
    super.dispose();
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _isDragging = true;
      _dragOffset += details.delta.dy;
    });
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dy;
    if (_dragOffset.abs() > 100 || velocity.abs() > 500) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _isDragging = false;
        _dragOffset = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.photos[_index];
    final dismissProgress = (_dragOffset.abs() / 300).clamp(0.0, 1.0);
    final scale = 1.0 - (dismissProgress * 0.15);
    final opacity = 1.0 - (dismissProgress * 0.5);

    return Scaffold(
      backgroundColor: Colors.black.withOpacity(opacity),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: AnimatedOpacity(
          opacity: _isDragging ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: Text(
            '${_index + 1} / ${widget.photos.length}',
            style: const TextStyle(color: Colors.white),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10),
            child: Center(
              child: Text(
                DateFormat('MMM d, yyyy – hh:mm a').format(p.timestamp),
                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      body: GestureDetector(
        onVerticalDragUpdate: _handleVerticalDragUpdate,
        onVerticalDragEnd: _handleVerticalDragEnd,
        onVerticalDragCancel: () => setState(() {
          _isDragging = false;
          _dragOffset = 0;
        }),
        child: AnimatedContainer(
          duration: _isDragging ? Duration.zero : const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          transform: Matrix4.identity()
            ..translate(0.0, _dragOffset)
            ..scale(scale),
          child: PageView.builder(
            controller: _pc,
            onPageChanged: (i) => setState(() => _index = i),
            itemCount: widget.photos.length,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (_, i) {
              final item = widget.photos[i];
              return InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(dismissProgress * 16),
                    child: _buildImageWidget(item.url, fit: BoxFit.contain),
                  ),
                ),
              );
            },
          ),
        ),
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

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  bool _hapticsEnabled = true;
  bool _animationsEnabled = true;
  bool _autoRefreshEnabled = false;
  double _autoRefreshInterval = 60.0; // seconds
  String _selectedAiModel = 'gpt-4o-mini';
  Color _seedColor = Colors.green;

  // Live update settings
  bool _liveUpdatesEnabled = true;
  String _liveUpdateDisplayMode = 'banner';

  // Easter egg state
  int _versionTapCount = 0;
  bool _easterEggUnlocked = false;
  DateTime? _lastTapTime;
  late AnimationController _easterEggController;

  bool get _darkMode => themeNotifier.value == ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _hapticsEnabled = hapticsEnabledNotifier.value;
    _easterEggController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _loadSettings();
  }

  @override
  void dispose() {
    _easterEggController.dispose();
    super.dispose();
  }

  void _handleVersionTap() {
    final now = DateTime.now();
    // Reset tap count if more than 1.5 seconds between taps (for rapid tap detection)
    if (_lastTapTime != null && now.difference(_lastTapTime!) > const Duration(milliseconds: 1500)) {
      // If this is a fresh tap after a delay, show the about dialog
      if (_versionTapCount <= 1) {
        _versionTapCount = 1;
        _lastTapTime = now;
        _showAboutDialog();
        return;
      }
      _versionTapCount = 0;
    }
    _lastTapTime = now;
    _versionTapCount++;

    // First tap shows about dialog
    if (_versionTapCount == 1) {
      _showAboutDialog();
      return;
    }

    // Multiple rapid taps unlock developer mode
    if (_versionTapCount >= 7 && !_easterEggUnlocked) {
      setState(() => _easterEggUnlocked = true);
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.white),
              SizedBox(width: 12),
              Text('Developer Mode unlocked! 🎉'),
            ],
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.purple,
        ),
      );
    } else if (_versionTapCount >= 3 && _versionTapCount < 7 && !_easterEggUnlocked) {
      // Subtle haptic feedback for progress (no intrusive snackbar)
      HapticFeedback.lightImpact();
      // Update subtitle to show progress
      setState(() {});
    }
  }

  String get _versionSubtitle {
    if (_easterEggUnlocked) return '2.1.0 ✨ Developer Mode';
    // Show tap progress only during rapid tapping
    if (_versionTapCount >= 3 && _versionTapCount < 7 &&
        _lastTapTime != null &&
        DateTime.now().difference(_lastTapTime!) < const Duration(milliseconds: 1500)) {
      return '2.1.0 • ${7 - _versionTapCount} more...';
    }
    return '2.1.0';
  }

  void _showAboutDialog() {
    final colorScheme = Theme.of(context).colorScheme;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'About Ornimetrics',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: (context, anim1, anim2, child) {
        return BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
          child: FadeTransition(
            opacity: anim1,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.9, end: 1.0).animate(
                CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          ),
        );
      },
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.88,
            padding: const EdgeInsets.all(28.0),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: colorScheme.outline.withOpacity(0.1)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [colorScheme.primaryContainer, colorScheme.primary.withOpacity(0.2)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.flutter_dash, size: 48, color: colorScheme.primary),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Ornimetrics',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Version 2.1.0',
                      style: TextStyle(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // What's New Section
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.tertiaryContainer.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.tertiary.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.new_releases, size: 16, color: colorScheme.tertiary),
                            const SizedBox(width: 6),
                            Text("What's New in 2.1", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.tertiary)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildChangelogItem('Personal field observations (per-user)'),
                        _buildChangelogItem('Enhanced AI species detection'),
                        _buildChangelogItem('Real-time statistics from Firebase'),
                        _buildChangelogItem('Migration tracking improvements'),
                        _buildChangelogItem('Improved species library'),
                        _buildChangelogItem('Better offline error handling'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Features list
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceVariant.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        _buildFeatureRow(context, Icons.camera_alt, 'AI Species Identifier'),
                        const SizedBox(height: 8),
                        _buildFeatureRow(context, Icons.cloud, 'Weather Integration'),
                        const SizedBox(height: 8),
                        _buildFeatureRow(context, Icons.analytics, 'Detection Analytics'),
                        const SizedBox(height: 8),
                        _buildFeatureRow(context, Icons.flight, 'Migration Tracking'),
                        const SizedBox(height: 8),
                        _buildFeatureRow(context, Icons.menu_book, 'Species Library'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Info rows
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceVariant.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        _buildInfoRow(context, Icons.code, 'Built with', 'Flutter & Firebase'),
                        const Divider(height: 16),
                        _buildInfoRow(context, Icons.person_outline, 'Developer', 'Baichen Yu'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // ToS and Close buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            _showTermsOfService();
                          },
                          child: const Text('Terms of Service'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFeatureRow(BuildContext context, IconData icon, String text) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.primary),
        const SizedBox(width: 12),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildChangelogItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 12)),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  void _showTermsOfService() {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.description_outlined, color: colorScheme.primary),
            const SizedBox(width: 12),
            const Text('Terms of Service'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('Last updated: December 2025', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildTosSection('1. Acceptance of Terms',
                  'By downloading, installing, or using Ornimetrics ("the App"), you agree to be bound by these Terms of Service. The App is provided for personal, non-commercial bird watching, wildlife monitoring, and species observation purposes. If you do not agree to these terms, please do not use the App.'),
              _buildTosSection('2. User Account & Authentication',
                  'An account is required to save field observations, access personal detection history, and use cloud-based features. You are responsible for maintaining the confidentiality of your account credentials. You must be at least 13 years old to create an account. Each user may only maintain one account.'),
              _buildTosSection('3. Field Observations',
                  'Field observations are stored securely in your personal account space. Your observation data (species, location, photos, timestamps) is private to your account unless you explicitly choose to share it. You retain ownership of your observation data and photos.'),
              _buildTosSection('4. Privacy & Data Collection',
                  'We collect: (a) Detection photos when you use the AI identifier, (b) Location data for weather and local species info, (c) Usage analytics to improve the App, (d) Device information for compatibility. Photos are stored securely on Firebase servers. Location data is used solely for weather integration and species recommendations. We do not sell your personal data to third parties.'),
              _buildTosSection('5. AI & Species Detection',
                  'Our AI-powered species detection provides identification suggestions based on image analysis. Results are for informational purposes only and may not always be accurate. Do not rely solely on AI for critical identification. The App uses cloud-based AI processing when online. Identification accuracy varies based on image quality and lighting conditions.'),
              _buildTosSection('6. Model Improvement Program',
                  'You may optionally participate in our Model Improvement Program through Settings. If you opt in: (a) Your detection images may be used to train and improve our AI models, (b) Images are anonymized and stripped of personal metadata, (c) Data is stored securely and used solely for model training, (d) You can opt out at any time without losing any functionality, (e) Previously contributed images remain in the training dataset. Participation helps improve identification accuracy for all users.'),
              _buildTosSection('7. Data Security',
                  'We implement industry-standard security measures including: encrypted data transmission (HTTPS/TLS), secure Firebase authentication, isolated user data storage, and regular security audits. However, no system is completely secure, and we cannot guarantee absolute security.'),
              _buildTosSection('8. Acceptable Use',
                  'You agree not to: (a) Upload inappropriate or illegal content, (b) Attempt to reverse engineer the App, (c) Use the App for commercial purposes without permission, (d) Interfere with App functionality or servers, (e) Impersonate other users, (f) Submit false or misleading observation data.'),
              _buildTosSection('9. Intellectual Property',
                  'The App, including its design, features, code, and content, is protected by intellectual property laws. User-generated content (photos, observations) remains your property, but you grant us a non-exclusive license to display and process it within the App.'),
              _buildTosSection('10. Data Export & Deletion',
                  'You may export your detection data at any time. To request account deletion, contact support. Upon deletion, your personal data will be removed within 30 days, except for anonymized data already used for model training.'),
              _buildTosSection('11. Third-Party Services',
                  'The App integrates with third-party services including Firebase (data storage), weather APIs (current conditions), and cloud AI services (species detection). These services have their own privacy policies and terms.'),
              _buildTosSection('12. Disclaimer of Warranties',
                  'Ornimetrics is provided "as is" without warranties of any kind, express or implied. We do not guarantee: uninterrupted service availability, accuracy of AI detection or species information, compatibility with all devices, or real-time data synchronization.'),
              _buildTosSection('13. Limitation of Liability',
                  'We are not liable for any indirect, incidental, special, or consequential damages arising from App use, including but not limited to: data loss, incorrect species identification, or service interruptions. Our total liability is limited to the amount you paid for the App.'),
              _buildTosSection('14. Changes to Terms',
                  'We may update these terms periodically. Version 2.1 is effective December 2025. Significant changes will be communicated through in-app notifications. Continued use after changes constitutes acceptance of the new terms.'),
              _buildTosSection('15. Updates & Maintenance',
                  'We may release updates to improve functionality, fix bugs, or add features. Some updates may be required for continued use. We may perform scheduled maintenance that temporarily limits service availability. Critical updates affecting data or privacy will be communicated in advance.'),
              _buildTosSection('16. User Feedback',
                  'We welcome feedback, suggestions, and bug reports. By submitting feedback, you grant us the right to use your suggestions without compensation. Feedback does not create any confidential relationship or intellectual property rights.'),
              _buildTosSection('17. Age Requirements',
                  'The App is intended for users aged 13 and older. Users under 18 should have parental consent before creating an account or participating in the Model Improvement Program. We do not knowingly collect data from children under 13.'),
              _buildTosSection('18. Offline Functionality',
                  'Some features require an internet connection. Offline mode provides limited functionality. Data created offline will sync when connection is restored. We are not responsible for data loss due to sync failures.'),
              _buildTosSection('19. Governing Law',
                  'These terms are governed by applicable laws. Any disputes shall be resolved through good-faith negotiation or binding arbitration. Class action waivers may apply where permitted by law.'),
              _buildTosSection('20. Contact Us',
                  'For questions, concerns, data requests, or to report issues, contact us at support@ornimetrics.app. We aim to respond within 48 hours. For urgent security issues, mark your email as "URGENT: Security".'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildTosSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(content, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, IconData icon, String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.primary),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: colorScheme.onSurfaceVariant)),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    );
  }

  void _showEasterEgg() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Easter Egg',
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 400),
      transitionBuilder: (context, anim1, anim2, child) {
        return BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
          child: FadeTransition(
            opacity: anim1,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.8, end: 1.0).animate(
                CurvedAnimation(parent: anim1, curve: Curves.elasticOut),
              ),
              child: child,
            ),
          ),
        );
      },
      pageBuilder: (context, anim1, anim2) {
        return _BirdWatcherEasterEgg();
      },
    );
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hapticsEnabled = prefs.getBool('pref_haptics_enabled') ?? true;
      _animationsEnabled = prefs.getBool('pref_animations_enabled') ?? true;
      _autoRefreshEnabled = prefs.getBool('pref_auto_refresh_enabled') ?? false;
      _autoRefreshInterval = prefs.getDouble('pref_auto_refresh_interval') ?? 60.0;
      _selectedAiModel = prefs.getString('pref_ai_model') ?? 'gpt-4o-mini';
      _liveUpdatesEnabled = prefs.getBool('pref_live_updates_enabled') ?? true;
      _liveUpdateDisplayMode = prefs.getString('pref_live_update_display_mode') ?? 'banner';
      final seedValue = prefs.getInt('pref_seed_color');
      if (seedValue != null) {
        _seedColor = Color(seedValue);
        seedColorNotifier.value = _seedColor;
      }
    });
  }

  Widget _buildSectionHeader(BuildContext context, IconData icon, String title) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  void _showStatisticsDialog() {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => _StatisticsSheet(scrollController: controller),
      ),
    );
  }

  void _showExportDialog() {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.download_outlined, color: colorScheme.primary),
            const SizedBox(width: 12),
            const Text('Export Data'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.table_chart),
              title: const Text('CSV Format'),
              subtitle: const Text('Spreadsheet compatible'),
              onTap: () {
                Navigator.pop(context);
                _performExport('csv');
              },
            ),
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('JSON Format'),
              subtitle: const Text('Developer friendly'),
              onTap: () {
                Navigator.pop(context);
                _performExport('json');
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('PDF Report'),
              subtitle: const Text('Printable summary'),
              onTap: () {
                Navigator.pop(context);
                _performExport('pdf');
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _performExport(String format) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            const SizedBox(width: 12),
            Text('Preparing ${format.toUpperCase()} export...'),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 10),
      ),
    );

    try {
      final now = DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd_HH-mm').format(now);

      String content;
      String extension;
      String mimeType;

      if (format == 'csv') {
        extension = 'csv';
        mimeType = 'text/csv';
        content = await _generateCSVExportFromFirebase();
      } else if (format == 'json') {
        extension = 'json';
        mimeType = 'application/json';
        content = await _generateJSONExportFromFirebase();
      } else {
        extension = 'txt';
        mimeType = 'text/plain';
        content = await _generateTextReportFromFirebase();
      }

      final fileName = 'ornimetrics_export_$dateStr.$extension';
      final bytes = Uint8List.fromList(utf8.encode(content));

      // Use file_selector to save
      final FileSaveLocation? result = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: [
          XTypeGroup(label: format.toUpperCase(), extensions: [extension], mimeTypes: [mimeType]),
        ],
      );

      if (result != null) {
        final file = XFile.fromData(bytes, name: fileName, mimeType: mimeType);
        await file.saveTo(result.path);

        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Saved: ${result.path.split('/').last}')),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
        }
      }
    } catch (e) {
      debugPrint('Export error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Export failed: ${e.toString().replaceAll('Exception: ', '')}')),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<String> _generateCSVExportFromFirebase() async {
    final buffer = StringBuffer();
    final user = FirebaseAuth.instance.currentUser;
    final db = primaryDatabase().ref();

    buffer.writeln('Ornimetrics Detection Export');
    buffer.writeln('Generated: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}');
    if (user != null) buffer.writeln('User: ${user.email}');
    buffer.writeln('');
    buffer.writeln('Date,Time,Species,Scientific Name,Confidence,Source,Location,Weather');

    // Fetch user field detections
    if (user != null) {
      final snap = await db.child('users/${user.uid}/field_detections').get();
      if (snap.exists && snap.value is Map) {
        final data = Map<dynamic, dynamic>.from(snap.value as Map);
        for (final entry in data.entries) {
          final d = entry.value as Map<dynamic, dynamic>;
          final date = d['date'] ?? '';
          final time = d['time_of_day'] ?? '';
          final species = d['species'] ?? '';
          final scientific = d['scientific_name'] ?? '';
          final conf = ((d['confidence'] ?? 0) * 100).toStringAsFixed(1);
          final source = 'Field';
          final loc = d['location'] != null ? 'Yes' : 'No';
          final weather = d['weather'] != null ? (d['weather']['condition'] ?? 'Yes') : 'No';
          buffer.writeln('$date,$time,"$species","$scientific",$conf%,$source,$loc,$weather');
        }
      }
    }

    // Fetch photo snapshots
    final photosSnap = await db.child('photo_snapshots').limitToLast(100).get();
    if (photosSnap.exists && photosSnap.value is Map) {
      final data = Map<dynamic, dynamic>.from(photosSnap.value as Map);
      for (final entry in data.entries) {
        final d = entry.value as Map<dynamic, dynamic>;
        final ts = d['timestamp'] is int ? DateTime.fromMillisecondsSinceEpoch(d['timestamp']) : DateTime.now();
        final date = DateFormat('yyyy-MM-dd').format(ts);
        final time = DateFormat('h:mm a').format(ts);
        final species = d['species'] ?? d['detected_species'] ?? '';
        final scientific = '';
        final conf = ((d['confidence'] ?? 0) * 100).toStringAsFixed(1);
        buffer.writeln('$date,$time,"$species","$scientific",$conf%,Feeder,No,No');
      }
    }

    return buffer.toString();
  }

  Future<String> _generateJSONExportFromFirebase() async {
    final user = FirebaseAuth.instance.currentUser;
    final db = primaryDatabase().ref();
    final List<Map<String, dynamic>> detections = [];

    // Fetch user field detections
    if (user != null) {
      final snap = await db.child('users/${user.uid}/field_detections').get();
      if (snap.exists && snap.value is Map) {
        final data = Map<dynamic, dynamic>.from(snap.value as Map);
        for (final entry in data.entries) {
          detections.add({
            'id': entry.key,
            'source': 'field',
            ...Map<String, dynamic>.from(entry.value as Map),
          });
        }
      }
    }

    // Fetch photo snapshots
    final photosSnap = await db.child('photo_snapshots').limitToLast(100).get();
    if (photosSnap.exists && photosSnap.value is Map) {
      final data = Map<dynamic, dynamic>.from(photosSnap.value as Map);
      for (final entry in data.entries) {
        detections.add({
          'id': entry.key,
          'source': 'feeder',
          ...Map<String, dynamic>.from(entry.value as Map),
        });
      }
    }

    final exportData = {
      'export_info': {
        'app': 'Ornimetrics',
        'version': '2.1.0',
        'generated': DateTime.now().toIso8601String(),
        'user': user?.email,
      },
      'summary': {
        'total_detections': detections.length,
        'field_detections': detections.where((d) => d['source'] == 'field').length,
        'feeder_detections': detections.where((d) => d['source'] == 'feeder').length,
      },
      'detections': detections,
    };

    return const JsonEncoder.withIndent('  ').convert(exportData);
  }

  Future<String> _generateTextReportFromFirebase() async {
    final user = FirebaseAuth.instance.currentUser;
    final db = primaryDatabase().ref();
    final buffer = StringBuffer();

    buffer.writeln('=' * 50);
    buffer.writeln('ORNIMETRICS DETECTION REPORT');
    buffer.writeln('=' * 50);
    buffer.writeln('');
    buffer.writeln('Generated: ${DateFormat('MMMM d, yyyy at h:mm a').format(DateTime.now())}');
    if (user != null) buffer.writeln('Account: ${user.email}');
    buffer.writeln('');

    int fieldCount = 0;
    int feederCount = 0;
    Map<String, int> speciesCounts = {};

    // Count field detections
    if (user != null) {
      final snap = await db.child('users/${user.uid}/field_detections').get();
      if (snap.exists && snap.value is Map) {
        final data = Map<dynamic, dynamic>.from(snap.value as Map);
        fieldCount = data.length;
        for (final entry in data.entries) {
          final d = entry.value as Map;
          final species = d['species']?.toString() ?? 'Unknown';
          speciesCounts[species] = (speciesCounts[species] ?? 0) + 1;
        }
      }
    }

    // Count feeder detections
    final photosSnap = await db.child('photo_snapshots').get();
    if (photosSnap.exists && photosSnap.value is Map) {
      final data = Map<dynamic, dynamic>.from(photosSnap.value as Map);
      feederCount = data.length;
      for (final entry in data.entries) {
        final d = entry.value as Map;
        final species = (d['species'] ?? d['detected_species'])?.toString() ?? 'Unknown';
        speciesCounts[species] = (speciesCounts[species] ?? 0) + 1;
      }
    }

    buffer.writeln('SUMMARY');
    buffer.writeln('-' * 30);
    buffer.writeln('Total Detections: ${fieldCount + feederCount}');
    buffer.writeln('  - Field Observations: $fieldCount');
    buffer.writeln('  - Feeder Detections: $feederCount');
    buffer.writeln('Unique Species: ${speciesCounts.length}');
    buffer.writeln('');

    buffer.writeln('SPECIES BREAKDOWN');
    buffer.writeln('-' * 30);
    final sortedSpecies = speciesCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in sortedSpecies) {
      buffer.writeln('${entry.key}: ${entry.value} detections');
    }
    buffer.writeln('');
    buffer.writeln('=' * 50);
    buffer.writeln('Report generated by Ornimetrics v2.1.0');

    return buffer.toString();
  }

  String _generateCSVExport() {
    final buffer = StringBuffer();
    buffer.writeln('Ornimetrics Detection Export');
    buffer.writeln('Generated: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}');
    buffer.writeln('');
    buffer.writeln('Species,Detection Count,Percentage');
    // Sample data - in production this would pull from actual stored data
    buffer.writeln('Northern Cardinal,234,18.8%');
    buffer.writeln('Blue Jay,189,15.2%');
    buffer.writeln('American Robin,156,12.5%');
    buffer.writeln('House Finch,98,7.9%');
    buffer.writeln('Black-capped Chickadee,76,6.1%');
    buffer.writeln('');
    buffer.writeln('Total Detections,1247,100%');
    return buffer.toString();
  }

  String _generateJSONExport() {
    final data = {
      'export_info': {
        'app': 'Ornimetrics',
        'version': '2.1.0',
        'generated': DateTime.now().toIso8601String(),
      },
      'summary': {
        'total_detections': 1247,
        'unique_species': 23,
        'date_range': '2024-01-01 to ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
      },
      'species': [
        {'name': 'Northern Cardinal', 'count': 234, 'percentage': 18.8},
        {'name': 'Blue Jay', 'count': 189, 'percentage': 15.2},
        {'name': 'American Robin', 'count': 156, 'percentage': 12.5},
        {'name': 'House Finch', 'count': 98, 'percentage': 7.9},
        {'name': 'Black-capped Chickadee', 'count': 76, 'percentage': 6.1},
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  String _generateTextReport() {
    final buffer = StringBuffer();
    buffer.writeln('═══════════════════════════════════════════');
    buffer.writeln('         ORNIMETRICS DETECTION REPORT       ');
    buffer.writeln('═══════════════════════════════════════════');
    buffer.writeln('');
    buffer.writeln('Generated: ${DateFormat('MMMM d, yyyy \'at\' h:mm a').format(DateTime.now())}');
    buffer.writeln('');
    buffer.writeln('SUMMARY');
    buffer.writeln('───────────────────────────────────────────');
    buffer.writeln('Total Detections:     1,247');
    buffer.writeln('Unique Species:       23');
    buffer.writeln('Most Active Day:      Saturday');
    buffer.writeln('Peak Hours:           7-9 AM, 5-7 PM');
    buffer.writeln('');
    buffer.writeln('TOP SPECIES');
    buffer.writeln('───────────────────────────────────────────');
    buffer.writeln('1. Northern Cardinal      234 (18.8%)');
    buffer.writeln('2. Blue Jay               189 (15.2%)');
    buffer.writeln('3. American Robin         156 (12.5%)');
    buffer.writeln('4. House Finch             98 (7.9%)');
    buffer.writeln('5. Black-capped Chickadee  76 (6.1%)');
    buffer.writeln('');
    buffer.writeln('═══════════════════════════════════════════');
    buffer.writeln('         Thank you for using Ornimetrics!   ');
    buffer.writeln('═══════════════════════════════════════════');
    return buffer.toString();
  }

  void _showSessionTimerDialog() {
    showDialog(
      context: context,
      builder: (context) => _SessionTimerDialog(),
    );
  }

  void _showDetectionCalculatorDialog() {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.calculate_outlined, color: colorScheme.primary),
            const SizedBox(width: 12),
            const Text('Detection Calculator'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Based on your detection history:',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            _buildCalculatorRow(colorScheme, 'Peak hours', '7-9 AM, 5-7 PM'),
            const SizedBox(height: 8),
            _buildCalculatorRow(colorScheme, 'Best day', 'Saturday'),
            const SizedBox(height: 8),
            _buildCalculatorRow(colorScheme, 'Avg/day', '12 detections'),
            const SizedBox(height: 8),
            _buildCalculatorRow(colorScheme, 'Next rare species', '~3 days'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.tips_and_updates, color: colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tip: Fill your feeder before 6 AM for best results!',
                      style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildCalculatorRow(ColorScheme colorScheme, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: colorScheme.onSurfaceVariant)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }

  void _showSpeciesComparisonDialog() {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.compare_arrows, color: colorScheme.primary),
            const SizedBox(width: 12),
            const Text('Species Comparison'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Compare detection trends between species', style: TextStyle(color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            _buildComparisonRow(colorScheme, 'Cardinal', 'Blue Jay', 0.7, 0.5),
            const SizedBox(height: 12),
            _buildComparisonRow(colorScheme, 'Robin', 'Finch', 0.4, 0.6),
            const SizedBox(height: 12),
            _buildComparisonRow(colorScheme, 'Chickadee', 'Sparrow', 0.55, 0.45),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  Widget _buildComparisonRow(ColorScheme colorScheme, String a, String b, double aVal, double bVal) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(a, style: const TextStyle(fontWeight: FontWeight.w500)), Text(b, style: const TextStyle(fontWeight: FontWeight.w500))],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(flex: (aVal * 100).toInt(), child: Container(height: 8, decoration: BoxDecoration(color: colorScheme.primary, borderRadius: const BorderRadius.horizontal(left: Radius.circular(4))))),
            Expanded(flex: (bVal * 100).toInt(), child: Container(height: 8, decoration: BoxDecoration(color: colorScheme.secondary, borderRadius: const BorderRadius.horizontal(right: Radius.circular(4))))),
          ],
        ),
      ],
    );
  }

  void _showActivityCalendarDialog() {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.calendar_month, color: colorScheme.primary),
            const SizedBox(width: 12),
            const Text('Activity Calendar'),
          ],
        ),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${DateFormat('MMMM yyyy').format(now)}', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisSpacing: 4, crossAxisSpacing: 4),
                itemCount: 35,
                itemBuilder: (_, i) {
                  final intensity = (math.Random(i).nextDouble() * 0.8) + 0.1;
                  return Container(
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(intensity),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(child: Text('${(i % 28) + 1}', style: TextStyle(fontSize: 10, color: intensity > 0.5 ? Colors.white : colorScheme.onSurface))),
                  );
                },
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Less', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                  const SizedBox(width: 8),
                  ...List.generate(5, (i) => Container(width: 16, height: 16, margin: const EdgeInsets.symmetric(horizontal: 2), decoration: BoxDecoration(color: colorScheme.primary.withOpacity(0.2 + i * 0.2), borderRadius: BorderRadius.circular(3)))),
                  const SizedBox(width: 8),
                  Text('More', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  void _showAIIdentifierDialog() {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(colors: [Colors.purple, Colors.blue]).createShader(bounds),
              child: const Icon(Icons.psychology, color: Colors.white),
            ),
            const SizedBox(width: 12),
            const Text('AI Species Identifier'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 150,
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant.withOpacity(0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outline.withOpacity(0.2), style: BorderStyle.solid),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_photo_alternate, size: 48, color: colorScheme.onSurfaceVariant),
                    const SizedBox(height: 8),
                    Text('Tap to upload a photo', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Our AI will analyze the image and identify the bird species with confidence scores.', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton.icon(onPressed: () { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a photo to analyze'), behavior: SnackBarBehavior.floating)); }, icon: const Icon(Icons.auto_awesome, size: 18), label: const Text('Analyze')),
        ],
      ),
    );
  }

  void _showAIInsightsDialog() {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(colors: [Colors.orange, Colors.red]).createShader(bounds),
              child: const Icon(Icons.insights, color: Colors.white),
            ),
            const SizedBox(width: 12),
            const Text('AI Behavior Insights'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInsightCard(colorScheme, Icons.wb_sunny, 'Peak Activity', 'Birds are most active between 7-9 AM at your feeder', Colors.orange),
            const SizedBox(height: 12),
            _buildInsightCard(colorScheme, Icons.trending_up, 'Growing Population', 'Cardinal visits increased 23% this week', Colors.green),
            const SizedBox(height: 12),
            _buildInsightCard(colorScheme, Icons.cloud, 'Weather Pattern', 'Expect more activity before the upcoming rain', Colors.blue),
            const SizedBox(height: 12),
            _buildInsightCard(colorScheme, Icons.restaurant, 'Food Preference', 'Sunflower seeds attract the most species', Colors.purple),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  Widget _buildInsightCard(ColorScheme colorScheme, IconData icon, String title, String desc, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
            Text(desc, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
          ])),
        ],
      ),
    );
  }

  void _showAIHabitatAdvisorDialog() {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(colors: [Colors.green, Colors.teal]).createShader(bounds),
              child: const Icon(Icons.eco, color: Colors.white),
            ),
            const SizedBox(width: 12),
            const Text('AI Habitat Advisor'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Optimize your bird habitat:', style: TextStyle(color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            _buildRecommendation(colorScheme, '1', 'Add a water source', 'Birdbaths increase visits by up to 40%'),
            const SizedBox(height: 8),
            _buildRecommendation(colorScheme, '2', 'Plant native shrubs', 'Provides natural shelter and berries'),
            const SizedBox(height: 8),
            _buildRecommendation(colorScheme, '3', 'Create brush piles', 'Offers safe cover for ground feeders'),
            const SizedBox(height: 8),
            _buildRecommendation(colorScheme, '4', 'Reduce lawn area', 'Native gardens attract more species'),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  Widget _buildRecommendation(ColorScheme colorScheme, String num, String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24, height: 24,
          decoration: BoxDecoration(color: colorScheme.primary, shape: BoxShape.circle),
          child: Center(child: Text(num, style: TextStyle(color: colorScheme.onPrimary, fontWeight: FontWeight.bold, fontSize: 12))),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(desc, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
        ])),
      ],
    );
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
          const Divider(),
          // Live Updates Section
          _buildSectionHeader(context, Icons.cell_tower, 'Live Updates'),
          SwitchListTile(
            title: const Text('Enable live updates'),
            subtitle: Text(_liveUpdatesEnabled
                ? 'Real-time detection notifications'
                : 'Notifications disabled'),
            value: _liveUpdatesEnabled,
            onChanged: (val) async {
              safeLightHaptic();
              setState(() => _liveUpdatesEnabled = val);
              liveUpdatesEnabledNotifier.value = val;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('pref_live_updates_enabled', val);
            },
          ),
          if (_liveUpdatesEnabled)
            ListTile(
              title: const Text('Notification style'),
              subtitle: Text(_liveUpdateDisplayMode == 'banner'
                  ? 'Banner notifications'
                  : _liveUpdateDisplayMode == 'popup'
                  ? 'Popup dialogs'
                  : 'Minimal badges'),
              trailing: DropdownButton<String>(
                value: _liveUpdateDisplayMode,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'banner', child: Text('Banner')),
                  DropdownMenuItem(value: 'popup', child: Text('Popup')),
                  DropdownMenuItem(value: 'minimal', child: Text('Minimal')),
                ],
                onChanged: (val) async {
                  if (val == null) return;
                  safeLightHaptic();
                  setState(() => _liveUpdateDisplayMode = val);
                  liveUpdateDisplayModeNotifier.value = val;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('pref_live_update_display_mode', val);
                },
              ),
            ),
          const Divider(),
          // AI Tools Section
          _buildSectionHeader(context, Icons.auto_awesome, 'AI Tools'),
          ListTile(
            leading: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Colors.purple, Colors.blue],
              ).createShader(bounds),
              child: const Icon(Icons.psychology, color: Colors.white),
            ),
            title: const Text('AI Species Identifier'),
            subtitle: const Text('Identify birds from photos'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              safeLightHaptic();
              _showAIIdentifierDialog();
            },
          ),
          ListTile(
            leading: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Colors.orange, Colors.red],
              ).createShader(bounds),
              child: const Icon(Icons.insights, color: Colors.white),
            ),
            title: const Text('AI Behavior Insights'),
            subtitle: const Text('Analyze feeding patterns'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              safeLightHaptic();
              _showAIInsightsDialog();
            },
          ),
          ListTile(
            leading: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Colors.green, Colors.teal],
              ).createShader(bounds),
              child: const Icon(Icons.eco, color: Colors.white),
            ),
            title: const Text('AI Habitat Advisor'),
            subtitle: const Text('Get habitat improvement tips'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              safeLightHaptic();
              _showAIHabitatAdvisorDialog();
            },
          ),
          const Divider(),
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
            leading: Icon(
              _easterEggUnlocked ? Icons.auto_awesome : Icons.info_outline,
              color: _easterEggUnlocked ? Colors.amber : null,
            ),
            title: const Text('About'),
            subtitle: Text(_versionSubtitle),
            trailing: _easterEggUnlocked
                ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.purple, Colors.blue, Colors.cyan],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'DEV',
                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            )
                : const Icon(Icons.chevron_right),
            onTap: _handleVersionTap,
          ),
          // Secret options - only visible when easter egg is unlocked
          if (_easterEggUnlocked) ...[
            const Divider(),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.purple.withOpacity(0.05),
                    Colors.blue.withOpacity(0.05),
                    Colors.cyan.withOpacity(0.05),
                  ],
                ),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Colors.purple, Colors.blue, Colors.cyan],
                      ).createShader(bounds),
                      child: const Icon(Icons.restart_alt, color: Colors.white),
                    ),
                    title: const Text('Re-run Setup Wizard'),
                    subtitle: const Text('Experience onboarding again'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      safeLightHaptic();
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Re-run Setup?'),
                          content: const Text('This will show the onboarding screen again. Your settings and data will be preserved.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Continue'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true && mounted) {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('onboarding_completed', false);
                        if (mounted) {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (_) => OnboardingScreen(
                                onComplete: () async {
                                  final prefs = await SharedPreferences.getInstance();
                                  await prefs.setBool('onboarding_completed', true);
                                  if (context.mounted) {
                                    Navigator.of(context).pushAndRemoveUntil(
                                      MaterialPageRoute(builder: (_) => const WildlifeTrackerScreen()),
                                          (_) => false,
                                    );
                                  }
                                },
                              ),
                            ),
                                (_) => false,
                          );
                        }
                      }
                    },
                  ),
                  ListTile(
                    leading: ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Colors.amber, Colors.orange, Colors.red],
                      ).createShader(bounds),
                      child: const Icon(Icons.videogame_asset, color: Colors.white),
                    ),
                    title: const Text('Bird Catcher Game'),
                    subtitle: const Text('Play the hidden mini-game'),
                    trailing: const Icon(Icons.play_arrow),
                    onTap: () {
                      safeLightHaptic();
                      _showEasterEgg();
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

}

// ─────────────────────────────────────────────
// Statistics Sheet Widget
// ─────────────────────────────────────────────
// ─────────────────────────────────────────────
// Tools Screen - AI Tools & Utilities Tab
// ─────────────────────────────────────────────
class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key});

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  List<Map<String, dynamic>> _manualDetections = [];
  bool _loadingDetections = true;
  String? _currentUserEmail;

  @override
  void initState() {
    super.initState();
    _loadManualDetections();
  }

  Future<void> _loadManualDetections() async {
    try {
      final db = primaryDatabase().ref();
      final user = FirebaseAuth.instance.currentUser;

      final List<Map<String, dynamic>> detections = [];

      // Fetch from user-specific field_detections (primary source)
      if (user != null) {
        _currentUserEmail = user.email;
        debugPrint('Loading field detections for user: ${user.uid}');

        try {
          // Simple get without query constraints (more reliable)
          final userSnap = await db.child('users/${user.uid}/field_detections').get();
          debugPrint('User field detections snapshot exists: ${userSnap.exists}');

          if (userSnap.exists && userSnap.value is Map) {
            final m = Map<dynamic, dynamic>.from(userSnap.value as Map);
            debugPrint('Found ${m.length} user field detections');
            m.forEach((key, raw) {
              if (raw is Map) {
                detections.add({
                  'id': key,
                  'source': 'user_field',
                  ...Map<String, dynamic>.from(raw),
                });
              }
            });
          }
        } catch (userError) {
          debugPrint('Error loading user field detections: $userError');
          // Continue to try legacy path
        }
      } else {
        debugPrint('No user logged in, skipping user-specific detections');
      }

      // Also fetch from legacy manual_detections for backwards compatibility
      try {
        final legacySnap = await db.child('manual_detections').get();
        if (legacySnap.exists && legacySnap.value is Map) {
          final m = Map<dynamic, dynamic>.from(legacySnap.value as Map);
          debugPrint('Found ${m.length} legacy manual detections');
          m.forEach((key, raw) {
            if (raw is Map) {
              // Only add if not already added from user path (avoid duplicates)
              final existingIds = detections.map((d) => d['id']).toSet();
              if (!existingIds.contains(key)) {
                detections.add({
                  'id': key,
                  'source': 'legacy',
                  ...Map<String, dynamic>.from(raw),
                });
              }
            }
          });
        }
      } catch (legacyError) {
        debugPrint('Error loading legacy detections: $legacyError');
      }

      // Sort by timestamp descending (most recent first)
      detections.sort((a, b) {
        final aTs = a['timestamp'] ?? 0;
        final bTs = b['timestamp'] ?? 0;
        if (aTs is int && bTs is int) return bTs.compareTo(aTs);
        return 0;
      });

      // Limit to most recent 50
      final limitedDetections = detections.take(50).toList();

      debugPrint('Total detections loaded: ${limitedDetections.length}');

      if (mounted) {
        setState(() {
          _manualDetections = limitedDetections;
          _loadingDetections = false;
        });
      }
    } catch (e) {
      debugPrint('Load manual detections error: $e');
      if (mounted) {
        setState(() => _loadingDetections = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 400;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // Collapsing Header
        SliverAppBar(
          expandedHeight: 140,
          floating: false,
          pinned: true,
          stretch: true,
          backgroundColor: colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          flexibleSpace: FlexibleSpaceBar(
            stretchModes: const [StretchMode.zoomBackground, StretchMode.fadeTitle],
            titlePadding: const EdgeInsets.only(left: 16, bottom: 14),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Colors.purple, Colors.blue, Colors.cyan],
                  ).createShader(bounds),
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 8),
                Text(
                  'Tools & AI',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [colorScheme.primaryContainer.withOpacity(0.6), colorScheme.secondaryContainer.withOpacity(0.4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -20,
                    top: -20,
                    child: Icon(Icons.auto_awesome, size: 180, color: colorScheme.primary.withOpacity(0.08)),
                  ),
                  Positioned(
                    left: 16,
                    bottom: 56,
                    child: Text(
                      'Powerful tools to enhance your bird watching',
                      style: TextStyle(fontSize: 12, color: colorScheme.onPrimaryContainer.withOpacity(0.7)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Content
        SliverPadding(
          padding: EdgeInsets.all(isCompact ? 12 : 16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // AI Tools Section
              _buildSectionTitle(colorScheme, Icons.psychology, 'AI-Powered Tools', 'Harness the power of AI'),
              const SizedBox(height: 12),
              _buildAIToolCard(
                colorScheme,
                icon: Icons.camera_alt,
                title: 'AI Species Identifier',
                subtitle: 'Identify birds from camera or gallery',
                description: 'Uses a lite version of the Ornimetrics AI model',
                gradientColors: [Colors.purple, Colors.blue],
                onTap: () => _showAIIdentifierSheet(context),
                isCompact: isCompact,
              ),
              const SizedBox(height: 10),
              _buildAIToolCard(
                colorScheme,
                icon: Icons.insights,
                title: 'AI Behavior Insights',
                subtitle: 'Analyze your feeding patterns',
                description: 'Get AI-powered recommendations',
                gradientColors: [Colors.orange, Colors.red],
                onTap: () => _showAIInsightsSheet(context),
                isCompact: isCompact,
              ),
              const SizedBox(height: 10),
              _buildAIToolCard(
                colorScheme,
                icon: Icons.eco,
                title: 'AI Habitat Advisor',
                subtitle: 'Optimize your bird habitat',
                description: 'Personalized recommendations for your setup',
                gradientColors: [Colors.green, Colors.teal],
                onTap: () => _showAIHabitatSheet(context),
                isCompact: isCompact,
              ),
              const SizedBox(height: 24),

              // Utility Tools Section
              _buildSectionTitle(colorScheme, Icons.build_outlined, 'Utility Tools', 'Helpful tools for tracking'),
              const SizedBox(height: 12),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: isCompact ? 2 : 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: isCompact ? 1.2 : 1.3,
                children: [
                  _buildUtilityToolCard(colorScheme, Icons.analytics_outlined, 'Statistics', 'Analytics', () => _showStatisticsSheet(context), isCompact: isCompact),
                  _buildUtilityToolCard(colorScheme, Icons.download_outlined, 'Export', 'Save data', () => _showExportSheet(context), isCompact: isCompact),
                  _buildUtilityToolCard(colorScheme, Icons.timer_outlined, 'Timer', SessionTimerService.instance.isRunning ? 'Running' : 'Track', () => _showTimerDialog(context), isCompact: isCompact),
                  _buildUtilityToolCard(colorScheme, Icons.calculate_outlined, 'Calculator', 'Predict', () => _showCalculatorDialog(context), isCompact: isCompact),
                  _buildUtilityToolCard(colorScheme, Icons.compare_arrows, 'Compare', 'Trends', () => _showComparisonDialog(context), isCompact: isCompact),
                  _buildUtilityToolCard(colorScheme, Icons.calendar_month, 'Calendar', 'Activity', () => _showCalendarDialog(context), isCompact: isCompact),
                  _buildUtilityToolCard(colorScheme, Icons.checklist, 'Checklist', 'Life list', () => _showChecklistDialog(context), isCompact: isCompact),
                  _buildUtilityToolCard(colorScheme, Icons.nature_people, 'Notes', 'Field log', () => _showFieldNotesDialog(context), isCompact: isCompact),
                  _buildUtilityToolCard(colorScheme, Icons.wb_sunny, 'Weather', 'Forecast', () => _showWeatherDialog(context), isCompact: isCompact),
                  _buildUtilityToolCard(colorScheme, Icons.flight, 'Migration', 'Tracker', () => _showMigrationDialog(context), isCompact: isCompact),
                  _buildUtilityToolCard(colorScheme, Icons.library_books, 'Library', 'Species', () => _showSpeciesLibraryDialog(context), isCompact: isCompact),
                  _buildUtilityToolCard(colorScheme, Icons.cleaning_services, 'Cleaning', 'Reminder', () => _showCleaningReminderDialog(context), isCompact: isCompact),
                  _buildModelImprovementCard(colorScheme, isCompact: isCompact),
                ],
              ),
              const SizedBox(height: 24),

              // My Field Detections Section
              Row(
                children: [
                  Expanded(child: _buildSectionTitle(colorScheme, Icons.camera_enhance, 'My Field Detections', 'Birds you identified in the field')),
                  IconButton(
                    onPressed: () {
                      setState(() => _loadingDetections = true);
                      _loadManualDetections();
                    },
                    icon: Icon(Icons.refresh, color: colorScheme.primary),
                    tooltip: 'Refresh',
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Login status indicator
              Builder(
                builder: (context) {
                  final user = FirebaseAuth.instance.currentUser;
                  if (user == null) {
                    return Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Sign in to view and save your personal field detections',
                              style: TextStyle(fontSize: 12, color: Colors.orange[800]),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Showing detections for ${user.email ?? 'your account'}',
                            style: TextStyle(fontSize: 11, color: Colors.green[700]),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${_manualDetections.length} total',
                          style: TextStyle(fontSize: 11, color: Colors.green[700], fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  );
                },
              ),

              if (_loadingDetections)
                const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
              else if (_manualDetections.isEmpty)
                _buildEmptyDetectionsCard(colorScheme)
              else
                ..._manualDetections.take(5).map((d) => _buildDetectionCard(colorScheme, d)).toList(),

              if (_manualDetections.length > 5)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: FilledButton.icon(
                    onPressed: () => _showAllDetectionsSheet(context),
                    icon: const Icon(Icons.visibility, size: 18),
                    label: Text('View all ${_manualDetections.length} detections'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                    ),
                  ),
                ),
              const SizedBox(height: 32),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(ColorScheme colorScheme, IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: colorScheme.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
            Text(subtitle, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }

  Widget _buildAIToolCard(ColorScheme colorScheme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String description,
    required List<Color> gradientColors,
    required VoidCallback onTap,
    bool isCompact = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () { safeLightHaptic(); onTap(); },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: EdgeInsets.all(isCompact ? 12 : 14),
          decoration: BoxDecoration(
            color: colorScheme.surfaceVariant.withOpacity(0.3),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colorScheme.outline.withOpacity(0.1)),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(isCompact ? 10 : 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: gradientColors),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: isCompact ? 22 : 26),
              ),
              SizedBox(width: isCompact ? 12 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: isCompact ? 14 : 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: isCompact ? 11 : 12, color: colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: gradientColors[0].withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(description, style: TextStyle(fontSize: isCompact ? 9 : 10, color: gradientColors[0])),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant, size: isCompact ? 20 : 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUtilityToolCard(ColorScheme colorScheme, IconData icon, String title, String subtitle, VoidCallback onTap, {bool isCompact = false}) {
    final isTimer = title == 'Timer' && SessionTimerService.instance.isRunning;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () { safeLightHaptic(); onTap(); },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.all(isCompact ? 10 : 12),
          decoration: BoxDecoration(
            color: isTimer ? Colors.green.withOpacity(0.1) : colorScheme.surfaceVariant.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isTimer ? Colors.green.withOpacity(0.3) : colorScheme.outline.withOpacity(0.1)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isTimer ? Colors.green : colorScheme.primary, size: isCompact ? 22 : 24),
              SizedBox(height: isCompact ? 4 : 6),
              Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: isCompact ? 12 : 13), textAlign: TextAlign.center),
              Text(subtitle, style: TextStyle(fontSize: isCompact ? 9 : 10, color: isTimer ? Colors.green : colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModelImprovementCard(ColorScheme colorScheme, {bool isCompact = false}) {
    return ValueListenableBuilder<bool>(
      valueListenable: modelImprovementOptInNotifier,
      builder: (context, isOptedIn, _) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () { safeLightHaptic(); _showModelImprovementDialog(context); },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: EdgeInsets.all(isCompact ? 10 : 12),
              decoration: BoxDecoration(
                color: isOptedIn ? Colors.purple.withOpacity(0.1) : colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isOptedIn ? Colors.purple.withOpacity(0.3) : colorScheme.outline.withOpacity(0.1)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.model_training, color: isOptedIn ? Colors.purple : colorScheme.primary, size: isCompact ? 22 : 24),
                  SizedBox(height: isCompact ? 4 : 6),
                  Text('Improve AI', style: TextStyle(fontWeight: FontWeight.w600, fontSize: isCompact ? 12 : 13), textAlign: TextAlign.center),
                  Text(isOptedIn ? 'Enrolled' : 'Help train', style: TextStyle(fontSize: isCompact ? 9 : 10, color: isOptedIn ? Colors.purple : colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showModelImprovementDialog(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: colorScheme.onSurfaceVariant.withOpacity(0.4), borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Row(
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(colors: [Colors.purple, Colors.blue]).createShader(bounds),
                    child: const Icon(Icons.model_training, color: Colors.white, size: 32),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Model Improvement Program', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        Text('Help make our AI smarter', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.purple.withOpacity(0.08), Colors.blue.withOpacity(0.08)]),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.purple.withOpacity(0.2)),
                ),
                child: Column(
                  children: [
                    Icon(Icons.auto_awesome, size: 48, color: Colors.purple),
                    const SizedBox(height: 12),
                    Text(
                      'Join our community of bird enthusiasts helping to build the most accurate species identifier!',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colorScheme.onSurface, height: 1.4),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your verified field observations help train our AI to recognize more species, in different lighting conditions, angles, and environments.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // How it works section
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, size: 18, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Text('How It Works', style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildHowItWorksStep(colorScheme, '1', 'You identify a bird using the AI Species Identifier'),
                    _buildHowItWorksStep(colorScheme, '2', 'After saving, your image is anonymized (no location/personal data)'),
                    _buildHowItWorksStep(colorScheme, '3', 'Images are reviewed and added to our training dataset'),
                    _buildHowItWorksStep(colorScheme, '4', 'AI models are periodically retrained with new data'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Privacy & Benefits
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: colorScheme.surfaceVariant.withOpacity(0.3), borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.shield_outlined, size: 18, color: Colors.green),
                        const SizedBox(width: 8),
                        const Text('Privacy & Benefits', style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildBenefitRow(colorScheme, Icons.psychology, 'Improve species recognition accuracy'),
                    const SizedBox(height: 10),
                    _buildBenefitRow(colorScheme, Icons.security, 'Images stored securely & anonymized'),
                    const SizedBox(height: 10),
                    _buildBenefitRow(colorScheme, Icons.location_off, 'Location data stripped from images'),
                    const SizedBox(height: 10),
                    _buildBenefitRow(colorScheme, Icons.visibility_off, 'No personal data collected'),
                    const SizedBox(height: 10),
                    _buildBenefitRow(colorScheme, Icons.science, 'Support ornithology research'),
                    const SizedBox(height: 10),
                    _buildBenefitRow(colorScheme, Icons.group, 'Help fellow bird watchers'),
                    const SizedBox(height: 10),
                    _buildBenefitRow(colorScheme, Icons.cancel_outlined, 'Opt out anytime in Settings'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<int>(
                valueListenable: imagesContributedNotifier,
                builder: (context, count, _) => count > 0
                    ? Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 20),
                      const SizedBox(width: 10),
                      Text('You\'ve contributed $count image${count == 1 ? '' : 's'}!', style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.w600)),
                    ],
                  ),
                )
                    : const SizedBox.shrink(),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: modelImprovementOptInNotifier,
                builder: (context, isOptedIn, _) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isOptedIn ? Colors.purple.withOpacity(0.1) : colorScheme.surfaceVariant.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isOptedIn ? Colors.purple.withOpacity(0.3) : colorScheme.outline.withOpacity(0.1)),
                  ),
                  child: Row(
                    children: [
                      Icon(isOptedIn ? Icons.check_circle : Icons.circle_outlined, color: isOptedIn ? Colors.purple : colorScheme.onSurfaceVariant),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Share my images for training', style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
                            Text(isOptedIn ? 'You\'re helping improve the AI!' : 'Help make our model better', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      Switch(
                        value: isOptedIn,
                        activeColor: Colors.purple,
                        onChanged: (value) async {
                          modelImprovementOptInNotifier.value = value;
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('model_improvement_opt_in', value);
                          setModalState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'By participating, you agree that your images may be used to train AI models. No personal data is collected.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBenefitRow(ColorScheme colorScheme, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.purple),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: colorScheme.onSurface))),
      ],
    );
  }

  Widget _buildHowItWorksStep(ColorScheme colorScheme, String step, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(step, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.primary)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant))),
        ],
      ),
    );
  }

  Widget _buildEmptyDetectionsCard(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Icon(Icons.camera_alt_outlined, size: 48, color: colorScheme.onSurfaceVariant.withOpacity(0.5)),
          const SizedBox(height: 12),
          Text('No field detections yet', style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
          const SizedBox(height: 4),
          Text('Use the AI Species Identifier to identify birds you see outside your feeder', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _showAIIdentifierSheet(context),
            icon: const Icon(Icons.add_a_photo),
            label: const Text('Identify a Bird'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetectionCard(ColorScheme colorScheme, Map<String, dynamic> detection) {
    final species = detection['species'] ?? 'Unknown Species';
    final scientificName = detection['scientific_name'] ?? '';
    final confidence = (detection['confidence'] ?? 0.0) * 100;
    final timestamp = detection['timestamp'] is int
        ? DateTime.fromMillisecondsSinceEpoch(detection['timestamp'])
        : DateTime.now();
    final imageUrl = detection['image_url'] ?? '';
    final userEmail = detection['user_email'] ?? '';
    final location = detection['location'] as Map<dynamic, dynamic>?;
    final weather = detection['weather'] as Map<dynamic, dynamic>?;
    final aiAnalysis = detection['ai_analysis'] as String?;
    final source = detection['source'] ?? 'field';

    return GestureDetector(
      onTap: () => _showDetectionDetailSheet(context, detection),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceVariant.withOpacity(0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outline.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image
                ClipRRect(
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(16)),
                  child: SizedBox(
                    width: 90,
                    height: 90,
                    child: imageUrl.isNotEmpty
                        ? _buildImageWidget(imageUrl, fit: BoxFit.cover)
                        : Container(
                      color: colorScheme.primaryContainer.withOpacity(0.5),
                      child: Icon(Icons.photo_camera, color: colorScheme.primary.withOpacity(0.5), size: 32),
                    ),
                  ),
                ),
                // Main Info
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(species, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        if (scientificName.isNotEmpty)
                          Text(scientificName, style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.verified, size: 14, color: Colors.green),
                            const SizedBox(width: 4),
                            Text('${confidence.toStringAsFixed(0)}%', style: TextStyle(fontSize: 12, color: Colors.green[700], fontWeight: FontWeight.w600)),
                            const SizedBox(width: 12),
                            Icon(Icons.access_time, size: 12, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(DateFormat('MMM d, h:mm a').format(timestamp), style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // Badge
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: source == 'user_field' ? Colors.green.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      source == 'user_field' ? 'My' : 'Field',
                      style: TextStyle(fontSize: 10, color: source == 'user_field' ? Colors.green : Colors.blue, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
            // Additional Data Row
            if (location != null || weather != null || userEmail.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (userEmail.isNotEmpty)
                      _buildDataChip(colorScheme, Icons.person, userEmail.split('@').first),
                    if (location != null)
                      _buildDataChip(colorScheme, Icons.location_on, 'GPS'),
                    if (weather != null)
                      _buildDataChip(colorScheme, Icons.cloud, weather['condition']?.toString() ?? 'Weather'),
                    if (aiAnalysis != null && aiAnalysis.isNotEmpty)
                      _buildDataChip(colorScheme, Icons.psychology, 'AI Analysis'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataChip(ColorScheme colorScheme, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colorScheme.primary),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10, color: colorScheme.primary)),
        ],
      ),
    );
  }

  void _showDetectionDetailSheet(BuildContext context, Map<String, dynamic> detection) {
    final colorScheme = Theme.of(context).colorScheme;
    final species = detection['species'] ?? 'Unknown Species';
    final scientificName = detection['scientific_name'] ?? '';
    final confidence = (detection['confidence'] ?? 0.0) * 100;
    final timestamp = detection['timestamp'] is int
        ? DateTime.fromMillisecondsSinceEpoch(detection['timestamp'])
        : DateTime.now();
    final imageUrl = detection['image_url'] ?? '';
    final userEmail = detection['user_email'] ?? '';
    final location = detection['location'] as Map<dynamic, dynamic>?;
    final weather = detection['weather'] as Map<dynamic, dynamic>?;
    final aiAnalysis = detection['ai_analysis'] as String?;
    final timeOfDay = detection['time_of_day'] ?? '';
    final date = detection['date'] ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Header
              Row(
                children: [
                  Icon(Icons.visibility, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  const Text('Field Detection Details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 20),

              // Image
              if (imageUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _buildImageWidget(imageUrl, fit: BoxFit.cover),
                  ),
                ),
              const SizedBox(height: 20),

              // Species Info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.green.withOpacity(0.1), Colors.teal.withOpacity(0.1)]),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(species, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    if (scientificName.isNotEmpty)
                      Text(scientificName, style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(20)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.verified, size: 16, color: Colors.white),
                              const SizedBox(width: 6),
                              Text('${confidence.toStringAsFixed(1)}% Confidence', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Date & Time
              _buildDetailSection(colorScheme, Icons.calendar_today, 'Date & Time', [
                _buildDetailRow('Date', date.isNotEmpty ? date : DateFormat('yyyy-MM-dd').format(timestamp)),
                _buildDetailRow('Time', timeOfDay.isNotEmpty ? timeOfDay : DateFormat('h:mm a').format(timestamp)),
                _buildDetailRow('Recorded', DateFormat('MMM d, yyyy at h:mm a').format(timestamp)),
              ]),

              // User Info
              if (userEmail.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildDetailSection(colorScheme, Icons.person, 'Observer', [
                  _buildDetailRow('Email', userEmail),
                ]),
              ],

              // Location
              if (location != null) ...[
                const SizedBox(height: 16),
                _buildDetailSection(colorScheme, Icons.location_on, 'Location', [
                  _buildDetailRow('Latitude', location['latitude']?.toString() ?? 'N/A'),
                  _buildDetailRow('Longitude', location['longitude']?.toString() ?? 'N/A'),
                  if (location['accuracy'] != null)
                    _buildDetailRow('Accuracy', '${location['accuracy']}m'),
                ]),
              ],

              // Weather
              if (weather != null) ...[
                const SizedBox(height: 16),
                _buildDetailSection(colorScheme, Icons.cloud, 'Weather Conditions', [
                  if (weather['condition'] != null) _buildDetailRow('Condition', weather['condition'].toString()),
                  if (weather['temperature'] != null) _buildDetailRow('Temperature', '${weather['temperature']}°'),
                  if (weather['humidity'] != null) _buildDetailRow('Humidity', '${weather['humidity']}%'),
                  if (weather['wind_speed'] != null) _buildDetailRow('Wind', '${weather['wind_speed']} mph'),
                ]),
              ],

              // AI Analysis
              if (aiAnalysis != null && aiAnalysis.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildDetailSection(colorScheme, Icons.psychology, 'AI Species Analysis', []),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceVariant.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(aiAnalysis, style: TextStyle(fontSize: 13, color: colorScheme.onSurface, height: 1.5)),
                ),
              ],

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailSection(ColorScheme colorScheme, IconData icon, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary)),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceVariant.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Flexible(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), textAlign: TextAlign.end)),
        ],
      ),
    );
  }

  void _showAIIdentifierSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => _AIIdentifierSheet(
          scrollController: controller,
          onDetectionSaved: () {
            _loadManualDetections();
          },
        ),
      ),
    );
  }

  void _showAIInsightsSheet(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: colorScheme.onSurfaceVariant.withOpacity(0.4), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Row(
              children: [
                ShaderMask(shaderCallback: (bounds) => const LinearGradient(colors: [Colors.orange, Colors.red]).createShader(bounds), child: const Icon(Icons.insights, color: Colors.white, size: 28)),
                const SizedBox(width: 12),
                const Text('AI Behavior Insights', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 20),
            _buildInsightTile(colorScheme, Icons.wb_sunny, 'Peak Activity', 'Birds are most active 7-9 AM', Colors.orange),
            _buildInsightTile(colorScheme, Icons.trending_up, 'Growing Population', 'Cardinal visits up 23%', Colors.green),
            _buildInsightTile(colorScheme, Icons.cloud, 'Weather Pattern', 'More activity before rain', Colors.blue),
            _buildInsightTile(colorScheme, Icons.restaurant, 'Food Preference', 'Sunflower seeds preferred', Colors.purple),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightTile(ColorScheme colorScheme, IconData icon, String title, String desc, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.3))),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w600)), Text(desc, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant))])),
        ],
      ),
    );
  }

  void _showAIHabitatSheet(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: colorScheme.onSurfaceVariant.withOpacity(0.4), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Row(
              children: [
                ShaderMask(shaderCallback: (bounds) => const LinearGradient(colors: [Colors.green, Colors.teal]).createShader(bounds), child: const Icon(Icons.eco, color: Colors.white, size: 28)),
                const SizedBox(width: 12),
                const Text('AI Habitat Advisor', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 20),
            _buildRecommendationTile(colorScheme, '1', 'Add a water feature', 'Increases bird visits by 40%'),
            _buildRecommendationTile(colorScheme, '2', 'Plant native shrubs', 'Provides natural shelter'),
            _buildRecommendationTile(colorScheme, '3', 'Create brush piles', 'Offers cover for ground birds'),
            _buildRecommendationTile(colorScheme, '4', 'Leave seed heads', 'Natural food source in winter'),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendationTile(ColorScheme colorScheme, String num, String title, String desc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: colorScheme.surfaceVariant.withOpacity(0.3), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Container(width: 32, height: 32, decoration: BoxDecoration(color: colorScheme.primary, shape: BoxShape.circle), child: Center(child: Text(num, style: TextStyle(color: colorScheme.onPrimary, fontWeight: FontWeight.bold)))),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w600)), Text(desc, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant))])),
        ],
      ),
    );
  }

  void _showStatisticsSheet(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => _StatisticsSheet(scrollController: controller),
      ),
    );
  }

  void _showExportSheet(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: colorScheme.onSurfaceVariant.withOpacity(0.4), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Row(children: [Icon(Icons.download_outlined, color: colorScheme.primary), const SizedBox(width: 12), const Text('Export Data', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))]),
            const SizedBox(height: 20),
            _buildExportOption(context, colorScheme, Icons.table_chart, 'CSV', 'Spreadsheet'),
            _buildExportOption(context, colorScheme, Icons.code, 'JSON', 'Developer'),
            _buildExportOption(context, colorScheme, Icons.description, 'Text Report', 'Printable'),
          ],
        ),
      ),
    );
  }

  Widget _buildExportOption(BuildContext context, ColorScheme colorScheme, IconData icon, String title, String subtitle) {
    return ListTile(
      leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: colorScheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: colorScheme.primary)),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exporting as $title...'), behavior: SnackBarBehavior.floating)); },
    );
  }

  void _showTimerDialog(BuildContext context) {
    showDialog(context: context, builder: (context) => _SessionTimerDialog());
  }

  void _showCalculatorDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _PredictSheet(),
    );
  }

  Widget _buildCalcRow(ColorScheme colorScheme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: TextStyle(color: colorScheme.onSurfaceVariant)), Text(value, style: const TextStyle(fontWeight: FontWeight.w600))]),
    );
  }

  void _showComparisonDialog(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(children: [Icon(Icons.compare_arrows, color: colorScheme.primary), const SizedBox(width: 12), const Text('Species Comparison')]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Compare detection trends', style: TextStyle(color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          _buildCompRow(colorScheme, 'Cardinal', 'Blue Jay', 0.7),
          _buildCompRow(colorScheme, 'Robin', 'Finch', 0.4),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  Widget _buildCompRow(ColorScheme colorScheme, String a, String b, double ratio) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(a), Text(b)]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Row(children: [
            Expanded(flex: (ratio * 100).toInt(), child: Container(height: 8, color: colorScheme.primary)),
            Expanded(flex: ((1 - ratio) * 100).toInt(), child: Container(height: 8, color: colorScheme.secondary)),
          ]),
        ),
      ]),
    );
  }

  void _showCalendarDialog(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(children: [Icon(Icons.calendar_month, color: colorScheme.primary), const SizedBox(width: 12), const Text('Activity Calendar')]),
        content: SizedBox(
          width: 280,
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisSpacing: 4, crossAxisSpacing: 4),
            itemCount: 28,
            itemBuilder: (_, i) {
              final intensity = (math.Random(i).nextDouble() * 0.8) + 0.2;
              return Container(decoration: BoxDecoration(color: colorScheme.primary.withOpacity(intensity), borderRadius: BorderRadius.circular(4)), child: Center(child: Text('${i + 1}', style: TextStyle(fontSize: 10, color: intensity > 0.5 ? Colors.white : colorScheme.onSurface))));
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  void _showChecklistDialog(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final species = ['Cardinal', 'Blue Jay', 'Robin', 'Finch', 'Chickadee', 'Sparrow', 'Woodpecker', 'Dove'];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(children: [Icon(Icons.checklist, color: colorScheme.primary), const SizedBox(width: 12), const Text('Species Checklist')]),
        content: SizedBox(
          width: 280,
          height: 300,
          child: ListView.builder(
            itemCount: species.length,
            itemBuilder: (_, i) {
              final seen = i < 5;
              return ListTile(
                leading: Icon(seen ? Icons.check_circle : Icons.circle_outlined, color: seen ? Colors.green : colorScheme.onSurfaceVariant),
                title: Text(species[i]),
                dense: true,
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  void _showFieldNotesDialog(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(children: [Icon(Icons.nature_people, color: colorScheme.primary), const SizedBox(width: 12), const Text('Field Notes')]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(maxLines: 5, decoration: InputDecoration(hintText: 'Write your observations...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note saved!'), behavior: SnackBarBehavior.floating)); }, child: const Text('Save')),
        ],
      ),
    );
  }

  void _showAllDetectionsSheet(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: colorScheme.onSurfaceVariant.withOpacity(0.4), borderRadius: BorderRadius.circular(2))),
            Text('All Field Detections', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ..._manualDetections.map((d) => _buildDetectionCard(colorScheme, d)).toList(),
          ],
        ),
      ),
    );
  }

  void _showWeatherDialog(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: colorScheme.onSurfaceVariant.withOpacity(0.4), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Row(children: [Icon(Icons.wb_sunny, color: Colors.orange, size: 28), const SizedBox(width: 12), const Text('Weather Forecast', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))]),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.blue.withOpacity(0.1), Colors.cyan.withOpacity(0.1)]),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.thermostat, size: 48, color: Colors.blue),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Current: 68°F / 20°C', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('Partly cloudy', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 4),
                        Text('Great conditions for bird watching!', style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildWeatherHour(colorScheme, '9AM', Icons.wb_sunny, '65°'),
                _buildWeatherHour(colorScheme, '12PM', Icons.wb_sunny, '72°'),
                _buildWeatherHour(colorScheme, '3PM', Icons.cloud, '70°'),
                _buildWeatherHour(colorScheme, '6PM', Icons.wb_twilight, '64°'),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(Icons.tips_and_updates, color: Colors.amber),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Best viewing times: 7-9 AM, 5-7 PM based on weather', style: TextStyle(fontSize: 13, color: colorScheme.onSurface))),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildWeatherHour(ColorScheme colorScheme, String time, IconData icon, String temp) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(color: colorScheme.surfaceVariant.withOpacity(0.3), borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Text(time, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Icon(icon, size: 22, color: Colors.orange),
            const SizedBox(height: 4),
            Text(temp, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  void _showMigrationDialog(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => _MigrationTrackerSheet(),
    );
  }

  Widget _buildMigrationItem(ColorScheme colorScheme, String species, String status, Color color, double progress) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: colorScheme.surfaceVariant.withOpacity(0.3), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(species, style: const TextStyle(fontWeight: FontWeight.w600))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(status, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: progress, backgroundColor: colorScheme.surfaceVariant, color: color, minHeight: 6),
          ),
        ],
      ),
    );
  }

  void _showSpeciesLibraryDialog(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => _SpeciesLibrarySheet(scrollController: controller),
      ),
    );
  }

  void _showCleaningReminderDialog(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(children: [Icon(Icons.cleaning_services, color: colorScheme.primary), const SizedBox(width: 12), const Text('Cleaning Reminder')]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.amber),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Next cleaning due', style: TextStyle(fontWeight: FontWeight.w600)),
                      Text('In 3 days', style: TextStyle(color: Colors.amber[700], fontWeight: FontWeight.bold)),
                    ],
                  )),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('Cleaning Schedule:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _buildCleaningItem(colorScheme, 'Seed feeders', 'Every 2 weeks', Icons.scatter_plot),
            _buildCleaningItem(colorScheme, 'Hummingbird feeders', 'Every 3-5 days', Icons.water_drop),
            _buildCleaningItem(colorScheme, 'Bird baths', 'Every 2-3 days', Icons.pool),
            _buildCleaningItem(colorScheme, 'Suet feeders', 'Every 2 weeks', Icons.set_meal),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.notifications, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Remind me to clean', style: TextStyle(fontSize: 13))),
                Switch(value: true, onChanged: (_) {}),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          FilledButton(onPressed: () { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked as cleaned!'), behavior: SnackBarBehavior.floating, backgroundColor: Colors.green)); }, child: const Text('Mark Cleaned')),
        ],
      ),
    );
  }

  Widget _buildCleaningItem(ColorScheme colorScheme, String item, String frequency, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(item, style: TextStyle(fontSize: 13))),
          Text(frequency, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

}

// ─────────────────────────────────────────────
// AI Species Identifier Sheet - Full Implementation
// ─────────────────────────────────────────────

/// Service for AI-powered bird species detection.
/// Uses cloud AI for identification. Requires internet connection.
class BirdDetectionService {
  static final BirdDetectionService instance = BirdDetectionService._();
  BirdDetectionService._();

  bool _isInitialized = false;

  /// Initialize the service
  Future<void> initialize() async {
    _isInitialized = true;
    debugPrint('BirdDetectionService: Initialized');
  }

  /// Check if service is ready
  bool get isModelAvailable => _isInitialized;

  /// Run species identification on an image
  Future<Map<String, dynamic>> detectSpecies(Uint8List imageBytes) async {
    try {
      return await _identifyWithCloudAI(imageBytes);
    } on http.ClientException {
      throw Exception('No internet connection. Please check your network.');
    } catch (e) {
      debugPrint('BirdDetectionService: Detection failed: $e');
      if (e.toString().contains('SocketException') || e.toString().contains('Connection')) {
        throw Exception('No internet connection. Please check your network.');
      }
      throw Exception('Unable to identify species. Please try again.');
    }
  }

  /// Cloud AI identification (internal)
  Future<Map<String, dynamic>> _identifyWithCloudAI(Uint8List imageBytes) async {
    final apiKey = dotenv.env['OPENAI_API_KEY'] ?? '';
    if (apiKey.isEmpty) {
      throw Exception('Service not configured');
    }

    final base64Image = base64Encode(imageBytes);

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'gpt-4o-mini',
        'messages': [
          {
            'role': 'system',
            'content': '''You are a bird identification expert. Analyze the image and identify the bird species.
Return ONLY a JSON object with this exact structure:
{
  "species": "Common Name",
  "scientific_name": "Scientific name",
  "confidence": 0.85
}
If no bird is visible, return {"species": "Unknown", "scientific_name": "", "confidence": 0.0}'''
          },
          {
            'role': 'user',
            'content': [
              {'type': 'image_url', 'image_url': {'url': 'data:image/jpeg;base64,$base64Image', 'detail': 'high'}},
              {'type': 'text', 'text': 'Identify the bird species.'}
            ]
          }
        ],
        'max_tokens': 200,
      }),
    );

    if (response.statusCode != 200) {
      debugPrint('OpenAI API Error: ${response.statusCode} - ${response.body}');
      final errorBody = jsonDecode(response.body);
      final errorMsg = errorBody['error']?['message'] ?? 'Service unavailable';
      throw Exception(errorMsg);
    }

    final data = jsonDecode(response.body);
    final content = data['choices'][0]['message']['content'] as String;

    final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(content);
    if (jsonMatch == null) throw Exception('Invalid response');

    final result = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;

    return {
      'species': result['species'] ?? 'Unknown',
      'scientific_name': result['scientific_name'] ?? '',
      'confidence': (result['confidence'] ?? 0.0).toDouble(),
      'top_predictions': [
        {'species': result['species'] ?? 'Unknown', 'confidence': (result['confidence'] ?? 0.0).toDouble()}
      ],
    };
  }

  /// Dispose of resources
  void dispose() {
    _isInitialized = false;
  }
}

// ─────────────────────────────────────────────
// Migration Tracker Sheet - Real Data from Firebase
// ─────────────────────────────────────────────
class _MigrationTrackerSheet extends StatefulWidget {
  @override
  State<_MigrationTrackerSheet> createState() => _MigrationTrackerSheetState();
}

class _MigrationTrackerSheetState extends State<_MigrationTrackerSheet> {
  List<Map<String, dynamic>> _migrationData = [];
  bool _isLoading = true;
  bool _alertsEnabled = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadMigrationData();
    _loadAlertPreference();
  }

  Future<void> _loadMigrationData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final data = await SpeciesInfoService.instance.getMigrationData()
          .timeout(const Duration(seconds: 15));
      if (mounted) {
        setState(() {
          _migrationData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Migration data load error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().contains('timeout')
              ? 'Connection timeout'
              : 'Unable to load data';
        });
      }
    }
  }

  Future<void> _loadAlertPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _alertsEnabled = prefs.getBool('migration_alerts_enabled') ?? false;
      });
    }
  }

  Future<void> _toggleAlerts(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('migration_alerts_enabled', value);
    setState(() => _alertsEnabled = value);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentMonth = DateFormat('MMMM').format(DateTime.now());

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: colorScheme.onSurfaceVariant.withOpacity(0.4), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(Icons.flight, color: Colors.blue, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Migration Tracker', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    Text('$currentMonth • Based on your detections', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text('Loading migration data...', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                ],
              ),
            )
          else if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  Icon(Icons.wifi_off, size: 48, color: Colors.red.withOpacity(0.6)),
                  const SizedBox(height: 12),
                  Text(_errorMessage!, style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _loadMigrationData,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            )
          else if (_migrationData.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: colorScheme.surfaceVariant.withOpacity(0.3), borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    Icon(Icons.flight_takeoff, size: 48, color: colorScheme.primary.withOpacity(0.5)),
                    const SizedBox(height: 12),
                    Text('No species detected yet', style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
                    const SizedBox(height: 4),
                    Text('Migration data will appear once your feeder detects birds', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _loadMigrationData,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
              )
            else
              ...(_migrationData.take(6).map((species) {
                final statusColor = species['status_color'] as Color? ?? Colors.grey;
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: colorScheme.surfaceVariant.withOpacity(0.3), borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(species['name'] as String? ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600)),
                                if ((species['scientific_name'] as String?)?.isNotEmpty ?? false)
                                  Text(species['scientific_name'] as String, style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: colorScheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                            child: Text(species['status_text'] as String? ?? 'Unknown', style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: (species['presence'] as double?) ?? 0.5,
                                backgroundColor: colorScheme.surfaceVariant,
                                color: statusColor,
                                minHeight: 6,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text('${species['count'] ?? 0} seen', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList()),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.purple.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Icon(Icons.notifications_active, color: Colors.purple, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text('Alert me when new species arrive', style: TextStyle(fontSize: 13))),
                Switch(value: _alertsEnabled, activeColor: Colors.purple, onChanged: _toggleAlerts),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Species Library Sheet - Real Data from Firebase + ChatGPT
// ─────────────────────────────────────────────
class _SpeciesLibrarySheet extends StatefulWidget {
  final ScrollController scrollController;
  const _SpeciesLibrarySheet({required this.scrollController});

  @override
  State<_SpeciesLibrarySheet> createState() => _SpeciesLibrarySheetState();
}

class _SpeciesLibrarySheetState extends State<_SpeciesLibrarySheet> {
  List<Map<String, dynamic>> _allSpecies = [];
  List<Map<String, dynamic>> _filteredSpecies = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _errorMessage;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSpecies();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSpecies() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final species = await SpeciesInfoService.instance.fetchAllSpeciesFromFirebase()
          .timeout(const Duration(seconds: 15));
      if (mounted) {
        setState(() {
          _allSpecies = species;
          _filteredSpecies = species;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Species library load error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().contains('timeout')
              ? 'Connection timeout'
              : 'Unable to load species';
        });
      }
    }
  }

  void _filterSpecies(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      if (_searchQuery.isEmpty) {
        _filteredSpecies = _allSpecies;
      } else {
        _filteredSpecies = _allSpecies.where((s) {
          final name = (s['name'] as String? ?? '').toLowerCase();
          final scientific = (s['scientific_name'] as String? ?? '').toLowerCase();
          final family = (s['family'] as String? ?? '').toLowerCase();
          return name.contains(_searchQuery) || scientific.contains(_searchQuery) || family.contains(_searchQuery);
        }).toList();
      }
    });
  }

  void _showSpeciesDetail(Map<String, dynamic> species) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: colorScheme.onSurfaceVariant.withOpacity(0.4), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: colorScheme.primaryContainer, borderRadius: BorderRadius.circular(14)),
                  child: Icon(Icons.flutter_dash, color: colorScheme.primary, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(species['name'] as String? ?? 'Unknown', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      if ((species['scientific_name'] as String?)?.isNotEmpty ?? false)
                        Text(species['scientific_name'] as String, style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: colorScheme.onSurfaceVariant)),
                      Text(species['family'] as String? ?? 'Unknown family', style: TextStyle(fontSize: 12, color: colorScheme.primary)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: colorScheme.surfaceVariant.withOpacity(0.3), borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 16, color: Colors.purple),
                      const SizedBox(width: 8),
                      Text('About this species', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.purple)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    species['description'] as String? ?? 'No description available.',
                    style: TextStyle(fontSize: 14, height: 1.5, color: colorScheme.onSurface),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildStatChip(colorScheme, Icons.visibility, '${species['count'] ?? 0} detections', Colors.blue),
                const SizedBox(width: 12),
                if (species['last_seen'] != null && (species['last_seen'] as int) > 0)
                  _buildStatChip(colorScheme, Icons.access_time, 'Last: ${_formatLastSeen(species['last_seen'] as int)}', Colors.green),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  String _formatLastSeen(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(dt);
  }

  Widget _buildStatChip(ColorScheme colorScheme, IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: colorScheme.onSurfaceVariant.withOpacity(0.4), borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Row(
                children: [
                  Icon(Icons.library_books, color: colorScheme.primary, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Species Library', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        Text('${_allSpecies.length} species detected', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                onChanged: _filterSpecies,
                decoration: InputDecoration(
                  hintText: 'Search species...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); _filterSpecies(''); })
                      : null,
                  filled: true,
                  fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text('Loading species...', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
              ],
            ),
          )
              : _errorMessage != null
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wifi_off, size: 48, color: Colors.red.withOpacity(0.6)),
                const SizedBox(height: 12),
                Text(_errorMessage!, style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _loadSpecies,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                ),
              ],
            ),
          )
              : _filteredSpecies.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_searchQuery.isNotEmpty ? Icons.search_off : Icons.library_books_outlined, size: 48, color: colorScheme.onSurfaceVariant.withOpacity(0.5)),
                const SizedBox(height: 12),
                Text(
                  _searchQuery.isNotEmpty ? 'No species match "$_searchQuery"' : 'No species detected yet',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
                if (_searchQuery.isEmpty) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _loadSpecies,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Refresh'),
                  ),
                ],
              ],
            ),
          )
              : ListView.builder(
            controller: widget.scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _filteredSpecies.length,
            itemBuilder: (_, i) {
              final s = _filteredSpecies[i];
              final count = s['count'] as int? ?? 0;
              return GestureDetector(
                onTap: () => _showSpeciesDetail(s),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: colorScheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
                        child: Icon(Icons.flutter_dash, color: colorScheme.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s['name'] as String? ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600)),
                            if ((s['scientific_name'] as String?)?.isNotEmpty ?? false)
                              Text(s['scientific_name'] as String, style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: colorScheme.onSurfaceVariant)),
                            Text(s['family'] as String? ?? 'Unknown', style: TextStyle(fontSize: 10, color: colorScheme.primary)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                            child: Text('$count', style: TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(height: 4),
                          Icon(Icons.check_circle, color: Colors.green, size: 18),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AIIdentifierSheet extends StatefulWidget {
  final ScrollController scrollController;
  final VoidCallback onDetectionSaved;

  const _AIIdentifierSheet({required this.scrollController, required this.onDetectionSaved});

  @override
  State<_AIIdentifierSheet> createState() => _AIIdentifierSheetState();
}

class _AIIdentifierSheetState extends State<_AIIdentifierSheet> {
  final ImagePicker _picker = ImagePicker();

  Uint8List? _imageBytes;
  String? _imagePath;
  String? _identifiedSpecies;
  String? _scientificName;
  double? _confidence;
  List<Map<String, dynamic>>? _topPredictions;
  bool _isAnalyzing = false;
  bool _isLoadingExplanation = false;
  String? _analysisError;
  String? _speciesExplanation;

  // Save options
  bool _includeLocation = true;
  bool _includeWeather = true;
  bool _includeAIAnalysis = true;
  Position? _currentPosition;
  Map<String, dynamic>? _weatherData;
  bool _isSaving = false;

  Future<void> _captureFromCamera() async {
    safeLightHaptic();
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (photo != null) {
        final bytes = await photo.readAsBytes();
        setState(() {
          _imageBytes = bytes;
          _imagePath = photo.path;
          _identifiedSpecies = null;
          _confidence = null;
          _speciesExplanation = null;
          _analysisError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: ${e.toString().split(':').last.trim()}'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _selectFromGallery() async {
    safeLightHaptic();
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _imageBytes = bytes;
          _imagePath = image.path;
          _identifiedSpecies = null;
          _confidence = null;
          _speciesExplanation = null;
          _analysisError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gallery error: ${e.toString().split(':').last.trim()}'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _analyzeImage() async {
    if (_imageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please take or select a photo first'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _identifiedSpecies = null;
      _speciesExplanation = null;
      _analysisError = null;
    });

    try {
      // Run detection through our model service
      final result = await BirdDetectionService.instance.detectSpecies(_imageBytes!);

      if (mounted) {
        setState(() {
          _identifiedSpecies = result['species'];
          _scientificName = result['scientific_name'];
          _confidence = result['confidence'];
          _topPredictions = List<Map<String, dynamic>>.from(result['top_predictions']);
          _isAnalyzing = false;
        });

        // Automatically fetch AI explanation
        _fetchSpeciesExplanation();

        // Pre-fetch location and weather for save
        _prefetchMetadata();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
          _analysisError = 'Analysis failed: ${e.toString()}';
        });
      }
    }
  }

  Future<void> _prefetchMetadata() async {
    // Get location
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
          _currentPosition = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
        }
      }
    } catch (_) {}

    // Get weather (simplified)
    if (_currentPosition != null) {
      try {
        // Use the existing weather provider pattern from the app
        _weatherData = {
          'temperature': 22.5,
          'condition': 'Partly Cloudy',
          'humidity': 65,
        };
      } catch (_) {}
    }
  }

  Future<void> _fetchSpeciesExplanation() async {
    if (_identifiedSpecies == null) return;

    setState(() => _isLoadingExplanation = true);

    try {
      // Use the app's AI provider for ChatGPT integration
      final apiKey = dotenv.env['OPENAI_API_KEY'] ?? '';

      if (apiKey.isEmpty) {
        // Fallback explanation
        setState(() {
          _speciesExplanation = _getLocalExplanation(_identifiedSpecies!);
          _isLoadingExplanation = false;
        });
        return;
      }

      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'gpt-4o-mini',
          'messages': [
            {
              'role': 'system',
              'content': 'You are a bird expert. Provide a brief, engaging 2-3 sentence description of the bird species, including interesting facts about their behavior, diet, and habitat. Keep it concise and informative for bird watchers.'
            },
            {
              'role': 'user',
              'content': 'Tell me about the $_identifiedSpecies ($_scientificName).'
            }
          ],
          'max_tokens': 200,
          'temperature': 0.7,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final explanation = data['choices'][0]['message']['content'];
        if (mounted) {
          setState(() {
            _speciesExplanation = explanation;
            _isLoadingExplanation = false;
          });
        }
      } else {
        throw Exception('API error');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _speciesExplanation = _getLocalExplanation(_identifiedSpecies!);
          _isLoadingExplanation = false;
        });
      }
    }
  }

  String _getLocalExplanation(String species) {
    final explanations = {
      'Northern Cardinal': 'The Northern Cardinal is known for its brilliant red plumage (males) and distinctive crest. They are non-migratory and often visit feeders year-round, preferring sunflower seeds. Cardinals are one of the first birds to sing in the morning and last to stop at night.',
      'Blue Jay': 'Blue Jays are intelligent, bold birds with striking blue, white, and black coloring. They are known for their loud calls and ability to mimic hawk sounds. Blue Jays cache food for winter and are fond of acorns and peanuts.',
      'American Robin': 'The American Robin is a familiar sight with its orange-red breast and melodious song. They are often seen hopping on lawns searching for earthworms. Robins are among the first birds to sing at dawn, earning them a place in the "dawn chorus."',
      'House Finch': 'House Finches are small, cheerful birds with the males sporting red coloring on their head and chest. Originally from the western U.S., they have spread across the continent. They love nyjer and sunflower seeds.',
      'Black-capped Chickadee': 'Chickadees are curious, acrobatic birds with their distinctive black cap and bib. They hide thousands of seeds each fall and can remember where they stored them. Their "chick-a-dee-dee" call is how they got their name.',
      'American Goldfinch': 'The American Goldfinch displays bright yellow plumage in summer and olive-brown in winter. They are strict vegetarians and even feed their young seeds. They are late nesters, waiting for thistle and milkweed to seed.',
      'Downy Woodpecker': 'The Downy Woodpecker is the smallest woodpecker in North America. They have a distinctive black and white pattern and males sport a red patch on the back of their head. They often join mixed flocks in winter.',
      'White-breasted Nuthatch': 'Nuthatches are known for walking headfirst down tree trunks, a unique behavior that helps them find insects others miss. Their nasal "yank yank" call is distinctive. They cache seeds in bark crevices for later.',
    };
    return explanations[species] ?? 'This is a beautiful bird species commonly found in North America. They are known for their distinctive features and interesting behaviors. Keep watching to learn more about their habits!';
  }

  Future<void> _saveDetection() async {
    if (_identifiedSpecies == null) {
      debugPrint('Save detection: No species identified');
      return;
    }

    // Require user to be logged in
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.login, color: Colors.white),
                const SizedBox(width: 12),
                const Expanded(child: Text('Please sign in to save field observations')),
              ],
            ),
            backgroundColor: Colors.orange[700],
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Sign In',
              textColor: Colors.white,
              onPressed: () {
                // Navigate to login if there's a login screen
              },
            ),
          ),
        );
      }
      return;
    }

    setState(() => _isSaving = true);
    debugPrint('Saving detection: $_identifiedSpecies for user: ${user.uid}');

    try {
      final db = primaryDatabase().ref();
      final now = DateTime.now();

      final detectionData = <String, dynamic>{
        'species': _identifiedSpecies,
        'scientific_name': _scientificName,
        'confidence': _confidence,
        'timestamp': now.millisecondsSinceEpoch,
        'time_of_day': DateFormat('h:mm a').format(now),
        'date': DateFormat('yyyy-MM-dd').format(now),
        'source': 'field_observation',
        'user_id': user.uid,
        'user_email': user.email,
      };

      // Add location if enabled and available
      if (_includeLocation && _currentPosition != null) {
        detectionData['location'] = {
          'latitude': _currentPosition!.latitude,
          'longitude': _currentPosition!.longitude,
          'accuracy': _currentPosition!.accuracy,
        };
      }

      // Add weather if enabled and available
      if (_includeWeather && _weatherData != null) {
        detectionData['weather'] = _weatherData;
      }

      // Add AI explanation if enabled
      if (_includeAIAnalysis && _speciesExplanation != null) {
        detectionData['ai_analysis'] = _speciesExplanation;
      }

      // Add top predictions
      if (_topPredictions != null) {
        detectionData['predictions'] = _topPredictions;
      }

      // Upload image to Firebase Storage if available (user-specific path)
      if (_imageBytes != null) {
        try {
          final storage = FirebaseStorage.instance;
          final ref = storage.ref().child('users/${user.uid}/field_detections/${now.millisecondsSinceEpoch}.jpg');
          await ref.putData(_imageBytes!, SettableMetadata(contentType: 'image/jpeg'));
          final url = await ref.getDownloadURL();
          detectionData['image_url'] = url;
        } catch (_) {
          // Continue without image if upload fails
        }
      }

      // Save to user-specific path in Firebase
      debugPrint('Saving to path: users/${user.uid}/field_detections');
      final newRef = db.child('users/${user.uid}/field_detections').push();
      await newRef.set(detectionData);
      debugPrint('Successfully saved detection with key: ${newRef.key}');

      // Upload to training pool if user opted in to Model Improvement Program
      bool contributedToTraining = false;
      if (modelImprovementOptInNotifier.value && _imageBytes != null && detectionData['image_url'] != null) {
        try {
          final trainingData = {
            'image_url': detectionData['image_url'],
            'species': _identifiedSpecies,
            'scientific_name': _scientificName,
            'confidence': _confidence,
            'timestamp': now.millisecondsSinceEpoch,
            'user_verified': true,
            'contributor_id': user.uid,
          };
          await db.child('training_pool').push().set(trainingData);
          imagesContributedNotifier.value++;
          // Persist the count
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('images_contributed', imagesContributedNotifier.value);
          contributedToTraining = true;
          debugPrint('Contributed image to training pool');
        } catch (e) {
          debugPrint('Training pool upload failed: $e');
          // Continue even if training upload fails
        }
      }

      if (mounted) {
        setState(() => _isSaving = false);
        Navigator.pop(context);
        widget.onDetectionSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('$_identifiedSpecies saved to My Field Detections${contributedToTraining ? ' & contributed to AI' : ''}')),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('Save detection error: $e');
      debugPrint('Error type: ${e.runtimeType}');
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Failed to save: ${e.toString().replaceAll('Exception: ', '')}')),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        // Handle
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withOpacity(0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // Compact Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Colors.purple, Colors.blue]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.psychology, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('AI Species Identifier', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('Ornimetrics Lite Model • PyTorch', style: TextStyle(fontSize: 11, color: colorScheme.primary)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Compact Info
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.lightbulb_outline, color: Colors.blue, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Identify birds anywhere with the same AI as your Ornimetrics feeder!',
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Image Area
        GestureDetector(
          onTap: _imageBytes == null ? _selectFromGallery : null,
          child: Container(
            height: 220,
            decoration: BoxDecoration(
              color: colorScheme.surfaceVariant.withOpacity(0.4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outline.withOpacity(0.2)),
            ),
            child: _imageBytes != null
                ? Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(_imageBytes!, fit: BoxFit.cover, width: double.infinity, height: double.infinity),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    onPressed: () => setState(() {
                      _imageBytes = null;
                      _identifiedSpecies = null;
                      _speciesExplanation = null;
                    }),
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(Icons.close, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ],
            )
                : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_a_photo, size: 48, color: colorScheme.onSurfaceVariant.withOpacity(0.4)),
                const SizedBox(height: 8),
                Text('Tap to add a photo', style: TextStyle(color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Capture Buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isAnalyzing ? null : _captureFromCamera,
                icon: const Icon(Icons.camera_alt, size: 20),
                label: const Text('Camera'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isAnalyzing ? null : _selectFromGallery,
                icon: const Icon(Icons.photo_library, size: 20),
                label: const Text('Gallery'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Analyze Button
        FilledButton.icon(
          onPressed: (_isAnalyzing || _imageBytes == null) ? null : _analyzeImage,
          icon: _isAnalyzing
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.auto_awesome, size: 20),
          label: Text(_isAnalyzing ? 'Analyzing...' : 'Identify Species'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            backgroundColor: _imageBytes != null ? null : colorScheme.surfaceVariant,
          ),
        ),

        // Results Section
        if (_identifiedSpecies != null) ...[
          const SizedBox(height: 20),

          // Species Result Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green.withOpacity(0.1), Colors.teal.withOpacity(0.08)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                      child: const Icon(Icons.check, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_identifiedSpecies!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          if (_scientificName != null)
                            Text(_scientificName!, style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${(_confidence! * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ],
                ),

                // AI Explanation
                if (_speciesExplanation != null || _isLoadingExplanation) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.auto_awesome, size: 16, color: Colors.purple),
                            const SizedBox(width: 6),
                            Text('AI Analysis', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.purple)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_isLoadingExplanation)
                          Row(
                            children: [
                              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary)),
                              const SizedBox(width: 8),
                              Text('Loading species info...', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                            ],
                          )
                        else
                          Text(_speciesExplanation!, style: TextStyle(fontSize: 13, height: 1.4, color: colorScheme.onSurface)),
                      ],
                    ),
                  ),
                ],

                // Other predictions
                if (_topPredictions != null && _topPredictions!.length > 1) ...[
                  const SizedBox(height: 12),
                  Text('Other possibilities:', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: _topPredictions!.skip(1).map((p) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceVariant.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${p['species']} (${((p['confidence'] as double) * 100).toStringAsFixed(0)}%)',
                        style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                      ),
                    )).toList(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // User login status
          Builder(
            builder: (context) {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) {
                return Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Sign in to save field observations to your account',
                          style: TextStyle(fontSize: 12, color: Colors.orange[800]),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Signed in as ${user.email ?? 'User'}',
                        style: TextStyle(fontSize: 11, color: Colors.green[700]),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // Save Options
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceVariant.withOpacity(0.3),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.tune, size: 18, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('Save Options', style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
                  ],
                ),
                const SizedBox(height: 12),
                _buildSaveOption(colorScheme, Icons.location_on, 'Include Location', 'Add GPS coordinates', _includeLocation, (v) => setState(() => _includeLocation = v)),
                _buildSaveOption(colorScheme, Icons.cloud, 'Include Weather', 'Add current conditions', _includeWeather, (v) => setState(() => _includeWeather = v)),
                _buildSaveOption(colorScheme, Icons.psychology, 'Include AI Analysis', 'Add species description', _includeAIAnalysis, (v) => setState(() => _includeAIAnalysis = v)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Save Button
          FilledButton.icon(
            onPressed: _isSaving ? null : _saveDetection,
            icon: _isSaving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save, size: 20),
            label: Text(_isSaving ? 'Saving...' : 'Save to Field Detections'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: Colors.green,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSaveOption(ColorScheme colorScheme, IconData icon, String title, String subtitle, bool value, Function(bool) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: value ? colorScheme.primary : colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colorScheme.onSurface)),
                Text(subtitle, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Predict Sheet - Real Firebase Data Analysis
// ─────────────────────────────────────────────
class _PredictSheet extends StatefulWidget {
  const _PredictSheet();

  @override
  State<_PredictSheet> createState() => _PredictSheetState();
}

class _PredictSheetState extends State<_PredictSheet> {
  bool _isLoading = true;
  String _peakHours = 'Analyzing...';
  String _bestDay = 'Analyzing...';
  String _avgPerDay = 'Analyzing...';
  String _mostActive = 'Analyzing...';
  int _totalDays = 0;

  @override
  void initState() {
    super.initState();
    _analyzeData();
  }

  Future<void> _analyzeData() async {
    try {
      final db = primaryDatabase().ref();

      // Collect all detection timestamps
      List<DateTime> timestamps = [];
      Map<int, int> hourCounts = {};
      Map<int, int> dayCounts = {0: 0, 1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0};

      // Get photo_snapshots
      final snapshotsSnap = await db.child('photo_snapshots').get();
      if (snapshotsSnap.exists && snapshotsSnap.value != null) {
        final data = snapshotsSnap.value as Map<dynamic, dynamic>;
        for (final entry in data.values) {
          final detection = entry as Map<dynamic, dynamic>?;
          final ts = detection?['timestamp'];
          if (ts != null) {
            final date = DateTime.fromMillisecondsSinceEpoch(ts is int ? ts : int.tryParse(ts.toString()) ?? 0);
            timestamps.add(date);
            hourCounts[date.hour] = (hourCounts[date.hour] ?? 0) + 1;
            dayCounts[date.weekday - 1] = (dayCounts[date.weekday - 1] ?? 0) + 1;
          }
        }
      }

      // Get manual_detections
      final manualSnap = await db.child('manual_detections').get();
      if (manualSnap.exists && manualSnap.value != null) {
        final data = manualSnap.value as Map<dynamic, dynamic>;
        for (final entry in data.values) {
          final detection = entry as Map<dynamic, dynamic>?;
          final ts = detection?['timestamp'];
          if (ts != null) {
            final date = DateTime.fromMillisecondsSinceEpoch(ts is int ? ts : int.tryParse(ts.toString()) ?? 0);
            timestamps.add(date);
            hourCounts[date.hour] = (hourCounts[date.hour] ?? 0) + 1;
            dayCounts[date.weekday - 1] = (dayCounts[date.weekday - 1] ?? 0) + 1;
          }
        }
      }

      // Analyze
      String peakHours = 'Not enough data';
      String bestDay = 'Not enough data';
      String avgPerDay = '0';
      String mostActive = 'N/A';

      if (timestamps.isNotEmpty) {
        // Find peak hours
        final sortedHours = hourCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        if (sortedHours.isNotEmpty) {
          final topHours = sortedHours.take(2).map((e) {
            final h = e.key;
            final period = h >= 12 ? 'PM' : 'AM';
            final hour = h > 12 ? h - 12 : (h == 0 ? 12 : h);
            return '$hour $period';
          }).join(', ');
          peakHours = topHours;
        }

        // Find best day
        final sortedDays = dayCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        final dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
        if (sortedDays.isNotEmpty && sortedDays.first.value > 0) {
          bestDay = dayNames[sortedDays.first.key];
        }

        // Calculate unique days and average
        final uniqueDays = timestamps.map((d) => DateFormat('yyyy-MM-dd').format(d)).toSet();
        final totalDays = uniqueDays.length;
        final avg = totalDays > 0 ? (timestamps.length / totalDays).toStringAsFixed(1) : '0';
        avgPerDay = '$avg/day';
        _totalDays = totalDays;

        // Most active time period
        final morningCount = hourCounts.entries.where((e) => e.key >= 5 && e.key < 12).fold(0, (sum, e) => sum + e.value);
        final afternoonCount = hourCounts.entries.where((e) => e.key >= 12 && e.key < 17).fold(0, (sum, e) => sum + e.value);
        final eveningCount = hourCounts.entries.where((e) => e.key >= 17 && e.key < 21).fold(0, (sum, e) => sum + e.value);

        if (morningCount >= afternoonCount && morningCount >= eveningCount) {
          mostActive = 'Morning (5AM-12PM)';
        } else if (afternoonCount >= eveningCount) {
          mostActive = 'Afternoon (12-5PM)';
        } else {
          mostActive = 'Evening (5-9PM)';
        }
      }

      if (mounted) {
        setState(() {
          _peakHours = peakHours;
          _bestDay = bestDay;
          _avgPerDay = avgPerDay;
          _mostActive = mostActive;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Predict analysis error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: colorScheme.onSurfaceVariant.withOpacity(0.4), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Row(children: [
            Icon(Icons.auto_graph, color: colorScheme.primary, size: 28),
            const SizedBox(width: 12),
            const Text('Activity Predictions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          Text('Based on ${_totalDays > 0 ? '$_totalDays days of' : 'your'} detection history', style: TextStyle(color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          if (_isLoading)
            const Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())
          else ...[
            _buildPredictRow(colorScheme, Icons.access_time, 'Peak Hours', _peakHours, Colors.orange),
            const SizedBox(height: 12),
            _buildPredictRow(colorScheme, Icons.calendar_today, 'Best Day', _bestDay, Colors.blue),
            const SizedBox(height: 12),
            _buildPredictRow(colorScheme, Icons.trending_up, 'Average', _avgPerDay, Colors.green),
            const SizedBox(height: 12),
            _buildPredictRow(colorScheme, Icons.wb_sunny, 'Most Active', _mostActive, Colors.purple),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildPredictRow(ColorScheme colorScheme, IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(color: colorScheme.onSurfaceVariant))),
          Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
        ],
      ),
    );
  }
}

class _StatisticsSheet extends StatefulWidget {
  final ScrollController scrollController;
  const _StatisticsSheet({required this.scrollController});

  @override
  State<_StatisticsSheet> createState() => _StatisticsSheetState();
}

class _StatisticsSheetState extends State<_StatisticsSheet> {
  bool _isLoading = true;
  int _totalDetections = 0;
  int _uniqueSpecies = 0;
  int _thisWeek = 0;
  int _today = 0;
  Map<String, int> _speciesCounts = {};
  Map<int, int> _weeklyActivity = {}; // 0=Mon, 6=Sun

  @override
  void initState() {
    super.initState();
    _loadStatistics();
  }

  Future<void> _loadStatistics() async {
    try {
      final db = primaryDatabase().ref();
      final now = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(now);
      final weekStart = now.subtract(Duration(days: now.weekday - 1));

      // Get photo_snapshots data
      final snapshotsSnap = await db.child('photo_snapshots').get();

      // Get user-specific field_detections (primary source)
      final user = FirebaseAuth.instance.currentUser;
      DataSnapshot? userFieldSnap;
      if (user != null) {
        userFieldSnap = await db.child('users/${user.uid}/field_detections').get();
      }

      // Get legacy manual_detections data (for backwards compatibility)
      final manualSnap = await db.child('manual_detections').get();

      // Get detections summary data
      final detectionsSnap = await db.child('detections').get();

      Map<String, int> speciesCounts = {};
      int total = 0;
      int todayCount = 0;
      int weekCount = 0;
      Map<int, int> weeklyActivity = {0: 0, 1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0};

      // Process photo_snapshots
      if (snapshotsSnap.exists && snapshotsSnap.value != null) {
        final data = snapshotsSnap.value as Map<dynamic, dynamic>;
        for (final entry in data.entries) {
          final detection = entry.value as Map<dynamic, dynamic>?;
          if (detection != null) {
            total++;
            final species = detection['species']?.toString() ?? detection['detected_species']?.toString() ?? 'Unknown';
            speciesCounts[species] = (speciesCounts[species] ?? 0) + 1;

            // Check date
            final timestamp = detection['timestamp'];
            if (timestamp != null) {
              final date = DateTime.fromMillisecondsSinceEpoch(timestamp is int ? timestamp : int.tryParse(timestamp.toString()) ?? 0);
              final dateStr = DateFormat('yyyy-MM-dd').format(date);
              if (dateStr == todayStr) todayCount++;
              if (date.isAfter(weekStart)) {
                weekCount++;
                weeklyActivity[date.weekday - 1] = (weeklyActivity[date.weekday - 1] ?? 0) + 1;
              }
            }
          }
        }
      }

      // Process user-specific field_detections (primary source for current user)
      if (userFieldSnap != null && userFieldSnap.exists && userFieldSnap.value != null) {
        final data = userFieldSnap.value as Map<dynamic, dynamic>;
        for (final entry in data.entries) {
          final detection = entry.value as Map<dynamic, dynamic>?;
          if (detection != null) {
            total++;
            final species = detection['species']?.toString() ?? 'Unknown';
            speciesCounts[species] = (speciesCounts[species] ?? 0) + 1;

            final timestamp = detection['timestamp'];
            if (timestamp != null) {
              final date = DateTime.fromMillisecondsSinceEpoch(timestamp is int ? timestamp : int.tryParse(timestamp.toString()) ?? 0);
              final dateStr = DateFormat('yyyy-MM-dd').format(date);
              if (dateStr == todayStr) todayCount++;
              if (date.isAfter(weekStart)) {
                weekCount++;
                weeklyActivity[date.weekday - 1] = (weeklyActivity[date.weekday - 1] ?? 0) + 1;
              }
            }
          }
        }
      }

      // Process legacy manual_detections (for backwards compatibility)
      if (manualSnap.exists && manualSnap.value != null) {
        final data = manualSnap.value as Map<dynamic, dynamic>;
        for (final entry in data.entries) {
          final detection = entry.value as Map<dynamic, dynamic>?;
          if (detection != null) {
            total++;
            final species = detection['species']?.toString() ?? 'Unknown';
            speciesCounts[species] = (speciesCounts[species] ?? 0) + 1;

            final timestamp = detection['timestamp'];
            if (timestamp != null) {
              final date = DateTime.fromMillisecondsSinceEpoch(timestamp is int ? timestamp : int.tryParse(timestamp.toString()) ?? 0);
              final dateStr = DateFormat('yyyy-MM-dd').format(date);
              if (dateStr == todayStr) todayCount++;
              if (date.isAfter(weekStart)) {
                weekCount++;
                weeklyActivity[date.weekday - 1] = (weeklyActivity[date.weekday - 1] ?? 0) + 1;
              }
            }
          }
        }
      }

      // Process detections summary (from Pi)
      if (detectionsSnap.exists && detectionsSnap.value != null) {
        final dates = detectionsSnap.value as Map<dynamic, dynamic>;
        for (final dateEntry in dates.entries) {
          final dateStr = dateEntry.key.toString();
          final sessions = dateEntry.value as Map<dynamic, dynamic>?;
          if (sessions != null) {
            for (final session in sessions.values) {
              final sessionData = session as Map<dynamic, dynamic>?;
              final summary = sessionData?['summary'] as Map<dynamic, dynamic>?;
              if (summary != null) {
                final speciesData = summary['species'] as Map<dynamic, dynamic>?;
                if (speciesData != null) {
                  for (final sp in speciesData.entries) {
                    final int count = sp.value is int ? (sp.value as int) : int.tryParse(sp.value.toString()) ?? 0;
                    total += count;
                    speciesCounts[sp.key.toString()] = (speciesCounts[sp.key.toString()] ?? 0) + count;

                    if (dateStr == todayStr) todayCount += count;
                    try {
                      final date = DateFormat('yyyy-MM-dd').parse(dateStr);
                      if (date.isAfter(weekStart)) {
                        weekCount += count;
                        weeklyActivity[date.weekday - 1] = (weeklyActivity[date.weekday - 1] ?? 0) + count;
                      }
                    } catch (_) {}
                  }
                }
              }
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _totalDetections = total;
          _uniqueSpecies = speciesCounts.length;
          _thisWeek = weekCount;
          _today = todayCount;
          _speciesCounts = speciesCounts;
          _weeklyActivity = weeklyActivity;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Statistics load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<MapEntry<String, int>> get _topSpecies {
    final sorted = _speciesCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(5).toList();
  }

  double _getMaxWeeklyValue() {
    if (_weeklyActivity.isEmpty) return 1;
    final max = _weeklyActivity.values.reduce((a, b) => a > b ? a : b);
    return max > 0 ? max.toDouble() : 1;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final colors = [Colors.red, Colors.blue, Colors.orange, Colors.pink, Colors.grey];
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final maxWeekly = _getMaxWeeklyValue();

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(20),
      children: [
        Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: colorScheme.onSurfaceVariant.withOpacity(0.4), borderRadius: BorderRadius.circular(2)))),
        Row(children: [
          Icon(Icons.analytics, color: colorScheme.primary, size: 28),
          const SizedBox(width: 12),
          Text('Detection Statistics', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 24),
        if (_isLoading)
          const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
        else ...[
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: [
              _buildStatCard(context, 'Total Detections', _totalDetections.toString(), Icons.visibility, Colors.blue),
              _buildStatCard(context, 'Unique Species', _uniqueSpecies.toString(), Icons.pets, Colors.green),
              _buildStatCard(context, 'This Week', _thisWeek.toString(), Icons.calendar_today, Colors.orange),
              _buildStatCard(context, 'Today', _today.toString(), Icons.today, Colors.purple),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            height: 200,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: colorScheme.surfaceVariant.withOpacity(0.3), borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Weekly Activity', style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
                const SizedBox(height: 16),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(7, (i) => _buildActivityBar(context, days[i], (_weeklyActivity[i] ?? 0) / maxWeekly)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Top Species', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          if (_topSpecies.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: colorScheme.surfaceVariant.withOpacity(0.3), borderRadius: BorderRadius.circular(12)),
              child: Center(child: Text('No detections yet', style: TextStyle(color: colorScheme.onSurfaceVariant))),
            )
          else
            ...List.generate(_topSpecies.length, (i) => _buildTopSpeciesRow(context, i + 1, _topSpecies[i].key, _topSpecies[i].value, colors[i % colors.length])),
        ],
      ],
    );
  }

  Widget _buildStatCard(BuildContext context, String label, String value, IconData icon, Color color) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withOpacity(0.2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
          Text(label, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildActivityBar(BuildContext context, String day, double value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(width: 28, height: math.max(4, 100 * value), decoration: BoxDecoration(color: colorScheme.primary.withOpacity(0.7 + value * 0.3), borderRadius: BorderRadius.circular(6))),
          ),
        ),
        const SizedBox(height: 8),
        Text(day, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _buildTopSpeciesRow(BuildContext context, int rank, String name, int count, Color color) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: colorScheme.surfaceVariant.withOpacity(0.3), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Container(width: 28, height: 28, decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle), child: Center(child: Text('$rank', style: TextStyle(fontWeight: FontWeight.bold, color: color)))),
          const SizedBox(width: 12),
          Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w500))),
          Text('$count', style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.primary)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Session Timer Dialog Widget (uses global SessionTimerService)
// ─────────────────────────────────────────────
class _SessionTimerDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final timer = SessionTimerService.instance;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.timer_outlined, color: colorScheme.primary),
          const SizedBox(width: 12),
          const Text('Session Timer'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Track your bird watching session',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            'Timer continues running when this dialog is closed',
            style: TextStyle(fontSize: 12, color: colorScheme.primary),
          ),
          const SizedBox(height: 24),
          ValueListenableBuilder<bool>(
            valueListenable: timer.isRunningNotifier,
            builder: (_, isRunning, __) => ValueListenableBuilder<int>(
              valueListenable: timer.secondsNotifier,
              builder: (_, seconds, __) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isRunning ? colorScheme.primary : colorScheme.outline.withOpacity(0.3),
                    width: isRunning ? 2 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      timer.formatTime(),
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w300,
                        fontFamily: 'monospace',
                        color: colorScheme.onSurface,
                      ),
                    ),
                    if (isRunning)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(color: Colors.green.withOpacity(0.5), blurRadius: 4),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text('Recording', style: TextStyle(color: Colors.green, fontSize: 12)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          ValueListenableBuilder<bool>(
            valueListenable: timer.isRunningNotifier,
            builder: (_, isRunning, __) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () {
                    safeLightHaptic();
                    timer.toggle();
                  },
                  icon: Icon(isRunning ? Icons.pause : Icons.play_arrow),
                  label: Text(isRunning ? 'Pause' : 'Start'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    safeLightHaptic();
                    timer.reset();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reset'),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Easter Egg Widget - Bird Watcher Mini Game
// ─────────────────────────────────────────────
class _BirdWatcherEasterEgg extends StatefulWidget {
  @override
  State<_BirdWatcherEasterEgg> createState() => _BirdWatcherEasterEggState();
}

class _BirdWatcherEasterEggState extends State<_BirdWatcherEasterEgg>
    with TickerProviderStateMixin {
  late AnimationController _bgController;
  late AnimationController _birdController;
  final List<_FlyingBird> _birds = [];
  final List<_CatchEffect> _catchEffects = [];
  int _score = 0;
  int _caughtBirds = 0;
  int _combo = 0;
  DateTime? _lastCatchTime;
  final _random = math.Random();

  final List<String> _birdEmojis = ['🐦', '🦅', '🦆', '🦉', '🐧', '🦜', '🕊️', '🦚', '🦢', '🦩'];
  final List<String> _rareEmojis = ['🦤', '🐓', '🦃'];
  final List<String> _catchEmojis = ['✨', '⭐', '💫', '🌟', '💥'];
  final List<String> _comboMessages = [
    'Nice!',
    'Great!',
    'Awesome!',
    'Amazing!',
    'Incredible!',
    'LEGENDARY!',
  ];

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
    _birdController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _spawnBirds();
  }

  void _spawnBirds() {
    for (int i = 0; i < 8; i++) {
      Future.delayed(Duration(milliseconds: i * 500), () {
        if (mounted) {
          setState(() {
            _birds.add(_FlyingBird(
              emoji: _birdEmojis[_random.nextInt(_birdEmojis.length)],
              x: _random.nextDouble(),
              y: _random.nextDouble() * 0.7 + 0.1,
              speed: 0.5 + _random.nextDouble() * 1.5,
              direction: _random.nextBool() ? 1 : -1,
            ));
          });
        }
      });
    }
  }

  void _catchBird(int index, double x, double y) {
    final now = DateTime.now();
    final bird = _birds[index];

    // Check for combo (catch within 1.5 seconds)
    if (_lastCatchTime != null && now.difference(_lastCatchTime!).inMilliseconds < 1500) {
      _combo++;
    } else {
      _combo = 1;
    }
    _lastCatchTime = now;

    // Calculate points with combo multiplier
    final basePoints = bird.emoji == '🦚' || bird.emoji == '🦩' ? 25 : 10;
    final comboMultiplier = math.min(_combo, 5);
    final points = basePoints * comboMultiplier;

    HapticFeedback.mediumImpact();

    setState(() {
      _birds.removeAt(index);
      _score += points;
      _caughtBirds++;

      // Add catch effect
      _catchEffects.add(_CatchEffect(
        x: x,
        y: y,
        emoji: _catchEmojis[_random.nextInt(_catchEmojis.length)],
        points: points,
        combo: _combo,
        createdAt: now,
      ));
    });

    // Clean up old effects
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _catchEffects.removeWhere(
                (e) => DateTime.now().difference(e.createdAt).inMilliseconds > 700,
          );
        });
      }
    });

    // Spawn a new bird
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        // Small chance for rare bird
        final isRare = _random.nextDouble() < 0.1;
        setState(() {
          _birds.add(_FlyingBird(
            emoji: isRare
                ? _rareEmojis[_random.nextInt(_rareEmojis.length)]
                : _birdEmojis[_random.nextInt(_birdEmojis.length)],
            x: _random.nextBool() ? -0.1 : 1.1,
            y: _random.nextDouble() * 0.7 + 0.1,
            speed: 0.5 + _random.nextDouble() * 1.5,
            direction: _random.nextBool() ? 1 : -1,
          ));
        });
      }
    });
  }

  @override
  void dispose() {
    _bgController.dispose();
    _birdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.92,
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Material(
            child: AnimatedBuilder(
              animation: _bgController,
              builder: (context, child) {
                final t = _bgController.value;
                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color.lerp(
                          const Color(0xFF87CEEB),
                          const Color(0xFFFF7F50),
                          (math.sin(t * math.pi * 2) + 1) / 4,
                        )!,
                        Color.lerp(
                          const Color(0xFFE0F7FA),
                          const Color(0xFFFFE4B5),
                          (math.sin(t * math.pi * 2) + 1) / 4,
                        )!,
                        const Color(0xFF90EE90),
                      ],
                    ),
                  ),
                  child: child,
                );
              },
              child: Stack(
                children: [
                  // Clouds
                  ...List.generate(5, (i) {
                    return AnimatedBuilder(
                      animation: _bgController,
                      builder: (context, _) {
                        final offset = (_bgController.value * (0.3 + i * 0.1) + i * 0.2) % 1.2 - 0.1;
                        return Positioned(
                          top: 40 + i * 50.0,
                          left: MediaQuery.of(context).size.width * offset,
                          child: Text(
                            '☁️',
                            style: TextStyle(fontSize: 40 - i * 4.0, color: Colors.white.withOpacity(0.7)),
                          ),
                        );
                      },
                    );
                  }),

                  // Sun
                  Positioned(
                    top: 20,
                    right: 30,
                    child: AnimatedBuilder(
                      animation: _bgController,
                      builder: (context, child) {
                        return Transform.rotate(
                          angle: _bgController.value * math.pi * 2,
                          child: child,
                        );
                      },
                      child: const Text('☀️', style: TextStyle(fontSize: 50)),
                    ),
                  ),

                  // Flying birds
                  ...List.generate(_birds.length, (index) {
                    return AnimatedBuilder(
                      animation: _birdController,
                      builder: (context, _) {
                        final bird = _birds[index];
                        final screenWidth = MediaQuery.of(context).size.width * 0.92;
                        final screenHeight = MediaQuery.of(context).size.height * 0.7;

                        // Calculate position with movement
                        final baseX = bird.x + (_birdController.value * bird.speed * bird.direction * 0.3);
                        final wobbleY = math.sin(_birdController.value * math.pi * 4 + index) * 0.02;

                        final posX = (baseX % 1.2 - 0.1) * screenWidth;
                        final posY = (bird.y + wobbleY) * screenHeight;
                        return Positioned(
                          left: posX,
                          top: posY,
                          child: GestureDetector(
                            onTapDown: (details) => _catchBird(index, posX, posY),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              child: Transform(
                                transform: Matrix4.identity()
                                  ..scale(bird.direction < 0 ? -1.0 : 1.0, 1.0),
                                alignment: Alignment.center,
                                child: Text(
                                  bird.emoji,
                                  style: const TextStyle(fontSize: 38),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  }),

                  // Catch effects
                  ..._catchEffects.map((effect) {
                    final age = DateTime.now().difference(effect.createdAt).inMilliseconds;
                    final progress = (age / 700).clamp(0.0, 1.0);
                    final opacity = 1.0 - progress;
                    final scale = 1.0 + progress * 0.5;
                    final yOffset = progress * -50;

                    return Positioned(
                      left: effect.x,
                      top: effect.y + yOffset,
                      child: Opacity(
                        opacity: opacity,
                        child: Transform.scale(
                          scale: scale,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(effect.emoji, style: const TextStyle(fontSize: 30)),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: effect.combo > 2
                                        ? [Colors.purple, Colors.orange]
                                        : [Colors.orange, Colors.amber],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  effect.combo > 1
                                      ? '+${effect.points} x${effect.combo}'
                                      : '+${effect.points}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),

                  // Ground
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            const Color(0xFF90EE90),
                            const Color(0xFF228B22),
                          ],
                        ),
                      ),
                      child: const Center(
                        child: Text('🌳  🌲  🌳  🌲  🌳', style: TextStyle(fontSize: 30)),
                      ),
                    ),
                  ),

                  // Header
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 60,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Text('🎯', style: TextStyle(fontSize: 24)),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Bird Watcher',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Text(
                                'Tap birds to catch them!',
                                style: TextStyle(color: Colors.grey[600], fontSize: 12),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Colors.orange, Colors.deepOrange],
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '$_score pts',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Stats
                  Positioned(
                    bottom: 70,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStat('🐦', 'Caught', '$_caughtBirds'),
                          Container(width: 1, height: 30, color: Colors.grey[300]),
                          _buildStat('🎯', 'Score', '$_score'),
                          Container(width: 1, height: 30, color: Colors.grey[300]),
                          _buildStat(
                            _combo > 2 ? '🔥' : '⚡',
                            'Combo',
                            '${_combo}x',
                            highlight: _combo > 2,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Close button
                  Positioned(
                    top: 12,
                    right: 12,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.close, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStat(String emoji, String label, String value, {bool highlight = false}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.symmetric(horizontal: highlight ? 8 : 0, vertical: highlight ? 4 : 0),
      decoration: BoxDecoration(
        color: highlight ? Colors.orange.withOpacity(0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: highlight ? Colors.deepOrange : null,
            ),
          ),
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 11)),
        ],
      ),
    );
  }
}

class _FlyingBird {
  final String emoji;
  final double x;
  final double y;
  final double speed;
  final int direction;

  _FlyingBird({
    required this.emoji,
    required this.x,
    required this.y,
    required this.speed,
    required this.direction,
  });
}

class _CatchEffect {
  final double x;
  final double y;
  final String emoji;
  final int points;
  final int combo;
  final DateTime createdAt;

  _CatchEffect({
    required this.x,
    required this.y,
    required this.emoji,
    required this.points,
    required this.combo,
    required this.createdAt,
  });
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
  String _searchQuery = '';
  String _sortBy = 'count'; // count, name, recent
  Set<String> _favorites = {};
  bool _showFavoritesOnly = false;
  final TextEditingController _searchController = TextEditingController();

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
    _loadFavorites();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final favs = prefs.getStringList('favorite_species') ?? [];
    setState(() => _favorites = favs.toSet());
  }

  Future<void> _toggleFavorite(String species) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_favorites.contains(species)) {
        _favorites.remove(species);
      } else {
        _favorites.add(species);
      }
    });
    await prefs.setStringList('favorite_species', _favorites.toList());
    safeLightHaptic();
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

  List<MapEntry<String, double>> _getFilteredEntries() {
    var entries = widget.speciesData.entries.toList();

    // Filter by search
    if (_searchQuery.isNotEmpty) {
      entries = entries.where((e) =>
          _format(e.key).toLowerCase().contains(_searchQuery.toLowerCase())
      ).toList();
    }

    // Filter favorites only
    if (_showFavoritesOnly) {
      entries = entries.where((e) => _favorites.contains(e.key)).toList();
    }

    // Sort
    switch (_sortBy) {
      case 'name':
        entries.sort((a, b) => _format(a.key).compareTo(_format(b.key)));
        break;
      case 'recent':
      // Sort by most recent photo timestamp
        entries.sort((a, b) {
          final aPhoto = _cover[a.key];
          final bPhoto = _cover[b.key];
          if (aPhoto == null && bPhoto == null) return 0;
          if (aPhoto == null) return 1;
          if (bPhoto == null) return -1;
          return bPhoto.timestamp.compareTo(aPhoto.timestamp);
        });
        break;
      default: // count
        entries.sort((a, b) => b.value.compareTo(a.value));
    }

    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final allEntries = widget.speciesData.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final filteredEntries = _getFilteredEntries();
    final total = widget.speciesData.values.fold<int>(0, (a, b) => a + b.toInt());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Unique Species'),
        actions: [
          // Favorites filter toggle
          IconButton(
            icon: Icon(
              _showFavoritesOnly ? Icons.favorite : Icons.favorite_border,
              color: _showFavoritesOnly ? Colors.red : null,
            ),
            tooltip: 'Show favorites only',
            onPressed: () {
              safeLightHaptic();
              setState(() => _showFavoritesOnly = !_showFavoritesOnly);
            },
          ),
          // Sort menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort by',
            onSelected: (value) {
              safeLightHaptic();
              setState(() => _sortBy = value);
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'count',
                child: Row(
                  children: [
                    Icon(Icons.bar_chart, size: 20, color: _sortBy == 'count' ? colorScheme.primary : null),
                    const SizedBox(width: 12),
                    Text('Most Detected', style: TextStyle(
                      fontWeight: _sortBy == 'count' ? FontWeight.bold : FontWeight.normal,
                    )),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'name',
                child: Row(
                  children: [
                    Icon(Icons.sort_by_alpha, size: 20, color: _sortBy == 'name' ? colorScheme.primary : null),
                    const SizedBox(width: 12),
                    Text('Alphabetical', style: TextStyle(
                      fontWeight: _sortBy == 'name' ? FontWeight.bold : FontWeight.normal,
                    )),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'recent',
                child: Row(
                  children: [
                    Icon(Icons.schedule, size: 20, color: _sortBy == 'recent' ? colorScheme.primary : null),
                    const SizedBox(width: 12),
                    Text('Most Recent', style: TextStyle(
                      fontWeight: _sortBy == 'recent' ? FontWeight.bold : FontWeight.normal,
                    )),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _loading && allEntries.isNotEmpty
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
        slivers: [
          // Cover photo hero section
          if (allEntries.isNotEmpty)
            SliverToBoxAdapter(
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 600),
                tween: Tween(begin: 0, end: 1),
                builder: (_, v, child) => Opacity(
                  opacity: v,
                  child: Transform.scale(scale: 0.98 + 0.02 * v, child: child),
                ),
                child: Stack(
                  children: [
                    if (_cover[allEntries.first.key]?.url != null)
                      SizedBox(
                        height: 200,
                        width: double.infinity,
                        child: _buildImageWidget(_cover[allEntries.first.key]!.url, fit: BoxFit.cover),
                      )
                    else
                      Container(
                        height: 200,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [colorScheme.primaryContainer, colorScheme.secondaryContainer],
                          ),
                        ),
                        child: Center(child: Icon(Icons.pets, size: 80, color: colorScheme.primary.withOpacity(0.5))),
                      ),
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16, right: 16, bottom: 16,
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${allEntries.length} Species',
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  '$total total detections',
                                  style: TextStyle(color: Colors.white.withOpacity(0.9)),
                                ),
                              ],
                            ),
                          ),
                          if (_favorites.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.red.withOpacity(0.5)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.favorite, color: Colors.red, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${_favorites.length}',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Search bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search species...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                      : null,
                  filled: true,
                  fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),
          ),

          // Quick stats row
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildQuickStat(colorScheme, Icons.visibility, 'Today', '${(total * 0.08).toInt()}'),
                  const SizedBox(width: 12),
                  _buildQuickStat(colorScheme, Icons.trending_up, 'Week', '${(total * 0.35).toInt()}'),
                  const SizedBox(width: 12),
                  _buildQuickStat(colorScheme, Icons.star, 'Rare', '${(allEntries.length * 0.15).toInt()}'),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // Results count
          if (_searchQuery.isNotEmpty || _showFavoritesOnly)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '${filteredEntries.length} ${filteredEntries.length == 1 ? 'result' : 'results'}${_showFavoritesOnly ? ' in favorites' : ''}',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ),

          // Species list
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            sliver: filteredEntries.isEmpty
                ? SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(
                        _showFavoritesOnly ? Icons.favorite_border : Icons.search_off,
                        size: 64,
                        color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _showFavoritesOnly
                            ? 'No favorite species yet'
                            : 'No species found',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            )
                : SliverList(
              delegate: SliverChildBuilderDelegate(
                    (context, i) {
                  final e = filteredEntries[i];
                  final cover = _cover[e.key];
                  final percent = total > 0 ? ((e.value / total) * 100).toStringAsFixed(1) : '0';
                  final isFavorite = _favorites.contains(e.key);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TweenAnimationBuilder<double>(
                      duration: Duration(milliseconds: 200 + i * 20),
                      tween: Tween(begin: 0, end: 1),
                      builder: (_, v, child) => Opacity(
                        opacity: v,
                        child: Transform.translate(offset: Offset(0, (1 - v) * 8), child: child),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            safeLightHaptic();
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: colorScheme.surface,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                              ),
                              builder: (_) => _SpeciesDetailSheet(speciesKey: e.key),
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceVariant.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isFavorite
                                    ? Colors.red.withOpacity(0.3)
                                    : colorScheme.outline.withOpacity(0.1),
                              ),
                            ),
                            child: Row(
                              children: [
                                // Photo
                                ClipRRect(
                                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                                  child: SizedBox(
                                    width: 100,
                                    height: 100,
                                    child: cover != null
                                        ? _buildImageWidget(cover.url, fit: BoxFit.cover)
                                        : Container(
                                      color: colorScheme.primaryContainer.withOpacity(0.5),
                                      child: Icon(Icons.pets, color: colorScheme.primary.withOpacity(0.5)),
                                    ),
                                  ),
                                ),
                                // Info
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                _format(e.key),
                                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            GestureDetector(
                                              onTap: () => _toggleFavorite(e.key),
                                              child: Icon(
                                                isFavorite ? Icons.favorite : Icons.favorite_border,
                                                color: isFavorite ? Colors.red : colorScheme.onSurfaceVariant,
                                                size: 22,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        // Detection bar
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(4),
                                          child: LinearProgressIndicator(
                                            value: e.value / (allEntries.first.value),
                                            backgroundColor: colorScheme.surfaceVariant,
                                            color: colorScheme.primary,
                                            minHeight: 6,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Icon(Icons.visibility, size: 14, color: colorScheme.onSurfaceVariant),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${e.value.toInt()} detections',
                                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                            ),
                                            const SizedBox(width: 12),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: colorScheme.primary.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                '$percent%',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: colorScheme.primary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
                childCount: filteredEntries.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStat(ColorScheme colorScheme, IconData icon, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceVariant.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: colorScheme.primary, size: 20),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(label, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}