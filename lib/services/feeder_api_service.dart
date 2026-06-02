/// REST API client for the on-device Ornimetrics feeder (Raspberry Pi 5 +
/// Hailo-8), port 5000 on the LAN. Endpoints follow `docs/API.md`.
///
/// This is the single source of live feeder state for the UI: screens bind to
/// the [ValueNotifier]s here. The SSE push channel ([FeederEventsService])
/// feeds new sightings / welfare alerts back in via [ingestSighting] /
/// [ingestWelfareAlert].

library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/feeder_models.dart';

const Duration kApiTimeout = Duration(seconds: 8);
const Duration kCurrentPollInterval = Duration(milliseconds: 1500);

/// Connection state used by the UI for banners / retry affordances.
enum FeederConnection { unknown, connecting, online, offline }

class FeederApiService {
  static final FeederApiService instance = FeederApiService._();
  FeederApiService._();

  // ---- Live state notifiers (UI binds to these) ----------------------------
  final ValueNotifier<FeederConnection> connection =
      ValueNotifier(FeederConnection.unknown);
  final ValueNotifier<bool> isConnected = ValueNotifier(false);
  final ValueNotifier<CurrentState?> current = ValueNotifier(null);
  final ValueNotifier<FeederStatus?> status = ValueNotifier(null);
  final ValueNotifier<FeederStatsCounters?> stats = ValueNotifier(null);
  final ValueNotifier<FeederSummary?> summary = ValueNotifier(null);
  final ValueNotifier<List<SpeciesLifeEntry>> lifeList = ValueNotifier(const []);
  final ValueNotifier<List<Sighting>> sightings = ValueNotifier(const []);
  final ValueNotifier<List<WelfareAlert>> welfareAlerts = ValueNotifier(const []);
  final ValueNotifier<List<AudioHeard>> audioHeard = ValueNotifier(const []);
  final ValueNotifier<List<FeederIndividual>> individuals = ValueNotifier(const []);
  final ValueNotifier<String?> errorMessage = ValueNotifier(null);
  final ValueNotifier<DateTime?> lastUpdated = ValueNotifier(null);

  // ---- Internal ------------------------------------------------------------
  String? _baseUrl;
  Timer? _currentTimer;
  bool _demoMode = false;
  int _consecutiveFailures = 0;
  final http.Client _client = http.Client();

  /// Number of consecutive failed calls before we surface "offline". This stops
  /// a single transient timeout from flipping the whole UI to offline.
  static const int _offlineThreshold = 3;

  String? get baseUrl => _baseUrl;
  bool get hasDevice => _baseUrl != null;

  /// In demo mode the service serves canned data and never touches the network
  /// (so it never flips to "offline").
  bool get isDemoMode => _demoMode;

  /// A paired device is the built-in demo if it has the demo id or the demo IP.
  static bool isDemoFeeder(PairedFeeder f) =>
      f.deviceId.startsWith('demo') || f.staticIp == '192.168.1.200';

  void setBaseUrl(String baseUrl) {
    _baseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    debugPrint('FeederApiService: base URL = $_baseUrl');
  }

  void setFromPairedFeeder(PairedFeeder feeder) => setBaseUrl(feeder.apiBaseUrl);

  String? get mjpegStreamUrl => _baseUrl == null ? null : '$_baseUrl/video_feed';
  String? get snapshotUrl => _baseUrl == null ? null : '$_baseUrl/api/snapshot';

  // ---- Generic GET ---------------------------------------------------------
  Future<dynamic> _getJson(String path) async {
    if (_baseUrl == null) {
      errorMessage.value = 'No feeder configured';
      return null;
    }
    final response =
        await _client.get(Uri.parse('$_baseUrl$path')).timeout(kApiTimeout);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    return jsonDecode(response.body);
  }

  void _markOnline() {
    _consecutiveFailures = 0;
    isConnected.value = true;
    connection.value = FeederConnection.online;
    errorMessage.value = null;
    lastUpdated.value = DateTime.now();
  }

  void _markOffline(Object e) {
    isConnected.value = false;
    errorMessage.value = _formatError(e);
    // Only flip the UI to offline after a few consecutive failures so a single
    // transient timeout doesn't strand us there; any success resets the streak.
    _consecutiveFailures++;
    if (_consecutiveFailures >= _offlineThreshold) {
      connection.value = FeederConnection.offline;
    }
    debugPrint('FeederApiService: $e (streak $_consecutiveFailures)');
  }

  // ---- Endpoints -----------------------------------------------------------

  /// `GET /api/current` — live AI output.
  Future<CurrentState?> getCurrent() async {
    try {
      final json = await _getJson('/api/current');
      if (json == null) return null;
      final state = CurrentState.fromJson(json as Map<String, dynamic>);
      current.value = state;
      _markOnline();
      return state;
    } catch (e) {
      _markOffline(e);
      return null;
    }
  }

  /// `GET /api/status` — hardware / mode.
  Future<FeederStatus?> getStatus() async {
    try {
      final json = await _getJson('/api/status');
      if (json == null) return null;
      final s = FeederStatus.fromJson(json as Map<String, dynamic>);
      status.value = s;
      _markOnline();
      return s;
    } catch (e) {
      _markOffline(e);
      return null;
    }
  }

  /// `GET /api/stats` — counters.
  Future<FeederStatsCounters?> getStats() async {
    try {
      final json = await _getJson('/api/stats');
      if (json == null) return null;
      final s = FeederStatsCounters.fromJson(json as Map<String, dynamic>);
      stats.value = s;
      return s;
    } catch (e) {
      debugPrint('FeederApiService: getStats $e');
      return null;
    }
  }

  /// `GET /api/summary` — home digest.
  Future<FeederSummary?> getSummary() async {
    try {
      final json = await _getJson('/api/summary');
      if (json == null) return null;
      final s = FeederSummary.fromJson(json as Map<String, dynamic>);
      summary.value = s;
      _markOnline();
      return s;
    } catch (e) {
      _markOffline(e);
      return null;
    }
  }

  /// `GET /api/species/summary` — life-list.
  Future<List<SpeciesLifeEntry>> getSpeciesSummary() async {
    try {
      final json = await _getJson('/api/species/summary');
      final list = (json?['species'] as List?) ?? const [];
      final result = list
          .whereType<Map>()
          .map((e) => SpeciesLifeEntry.fromJson(e.cast<String, dynamic>()))
          .toList();
      lifeList.value = result;
      return result;
    } catch (e) {
      debugPrint('FeederApiService: getSpeciesSummary $e');
      return lifeList.value;
    }
  }

  /// `GET /api/sightings/recent` — activity feed.
  Future<List<Sighting>> getSightingsRecent({int limit = 50}) async {
    try {
      final json = await _getJson('/api/sightings/recent?limit=$limit');
      final list = (json?['sightings'] as List?) ?? const [];
      final result = list
          .whereType<Map>()
          .map((e) => Sighting.fromJson(e.cast<String, dynamic>()))
          .toList();
      sightings.value = result;
      return result;
    } catch (e) {
      debugPrint('FeederApiService: getSightingsRecent $e');
      return sightings.value;
    }
  }

  /// `GET /api/individual/<id>` — one bird's profile + health trend.
  /// [id] is like `#3`; the `#` is URL-encoded as `%23`.
  Future<IndividualProfile?> getIndividual(String id) async {
    if (_demoMode) return _demoProfile(id);
    try {
      final encoded = Uri.encodeComponent(id); // '#3' -> '%233'
      final json = await _getJson('/api/individual/$encoded');
      if (json == null) return null;
      return IndividualProfile.fromJson(json as Map<String, dynamic>);
    } catch (e) {
      debugPrint('FeederApiService: getIndividual $e');
      return null;
    }
  }

  /// `GET /api/welfare/alerts` — screening flags.
  Future<List<WelfareAlert>> getWelfareAlerts({int limit = 50}) async {
    try {
      final json = await _getJson('/api/welfare/alerts?limit=$limit');
      final list = (json?['alerts'] as List?) ?? const [];
      final result = list
          .whereType<Map>()
          .map((e) => WelfareAlert.fromJson(e.cast<String, dynamic>()))
          .toList();
      welfareAlerts.value = result;
      return result;
    } catch (e) {
      debugPrint('FeederApiService: getWelfareAlerts $e');
      return welfareAlerts.value;
    }
  }

  /// `GET /api/audio/recent` — birds heard via the mic.
  Future<List<AudioHeard>> getAudioRecent() async {
    try {
      final json = await _getJson('/api/audio/recent');
      final list = (json?['heard'] as List?) ?? const [];
      final result = list
          .whereType<Map>()
          .map((e) => AudioHeard.fromJson(e.cast<String, dynamic>()))
          .toList();
      audioHeard.value = result;
      return result;
    } catch (e) {
      debugPrint('FeederApiService: getAudioRecent $e');
      return audioHeard.value;
    }
  }

  /// `GET /api/individuals` — recently-seen individuals (id -> info map).
  Future<List<FeederIndividual>> getIndividuals() async {
    try {
      final json = await _getJson('/api/individuals');
      final result = <FeederIndividual>[];
      // The server may return either a list (`{individuals:[{id,...}]}`) or a
      // map keyed by id (`{individuals:{"#3":{...}}}` / bare `{"#3":{...}}`).
      final inner = (json is Map && json['individuals'] != null)
          ? json['individuals']
          : json;
      if (inner is List) {
        for (final e in inner) {
          if (e is Map) {
            final m = e.cast<String, dynamic>();
            final id = (m['id'] ?? m['individual'] ?? '').toString();
            result.add(FeederIndividual.fromId(id, m));
          }
        }
      } else if (inner is Map) {
        inner.forEach((key, value) {
          if (value is Map) {
            result.add(
                FeederIndividual.fromId(key.toString(), value.cast<String, dynamic>()));
          }
        });
      }
      individuals.value = result;
      return result;
    } catch (e) {
      debugPrint('FeederApiService: getIndividuals $e');
      return individuals.value;
    }
  }

  // ---- Teach (self-improving loop) ----------------------------------------

  Future<bool> _postTeach(Map<String, dynamic> body) async {
    if (_baseUrl == null) return false;
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/api/teach'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(kApiTimeout);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return json['ok'] == true || json['stored'] == true;
      }
      return false;
    } catch (e) {
      errorMessage.value = 'Teach failed: ${_formatError(e)}';
      debugPrint('FeederApiService: teach $e');
      return false;
    }
  }

  /// Name an individual (applied live).
  Future<bool> teachName({required String individual, required String name}) =>
      _postTeach({'kind': 'name', 'individual': individual, 'name': name});

  /// Correct a species for an individual.
  Future<bool> teachSpecies({required String individual, required String species}) =>
      _postTeach({'kind': 'species', 'individual': individual, 'species': species});

  /// File a user-reported note / flag on an individual.
  Future<bool> teachFlag({required String individual, required String note}) =>
      _postTeach({'kind': 'flag', 'individual': individual, 'note': note});

  // ---- Controls ------------------------------------------------------------

  /// `POST /api/control/detection` with `{enabled}`.
  Future<bool?> setDetectionEnabled(bool enabled) async {
    if (_baseUrl == null) return null;
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/api/control/detection'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'enabled': enabled}),
          )
          .timeout(kApiTimeout);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        await getStatus();
        return json['enabled'] as bool? ?? enabled;
      }
      return null;
    } catch (e) {
      debugPrint('FeederApiService: setDetectionEnabled $e');
      return null;
    }
  }

  /// `POST /api/control/reset_db`.
  Future<bool> resetDatabase() async {
    if (_baseUrl == null) return false;
    try {
      final response = await _client
          .post(Uri.parse('$_baseUrl/api/control/reset_db'))
          .timeout(kApiTimeout);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('FeederApiService: resetDatabase $e');
      return false;
    }
  }

  // ---- SSE ingestion (called by FeederEventsService) -----------------------

  /// Prepend a pushed sighting to the feed (deduped on ts+species).
  void ingestSighting(Sighting s) {
    final list = List<Sighting>.from(sightings.value);
    final dup = list.isNotEmpty &&
        list.first.ts == s.ts &&
        list.first.species == s.species;
    if (!dup) {
      list.insert(0, s);
      sightings.value = list.take(200).toList();
    }
    lastUpdated.value = DateTime.now();
  }

  /// Prepend a pushed welfare alert.
  void ingestWelfareAlert(WelfareAlert a) {
    final list = List<WelfareAlert>.from(welfareAlerts.value);
    final dup = list.isNotEmpty &&
        list.first.ts == a.ts &&
        list.first.individual == a.individual;
    if (!dup) {
      list.insert(0, a);
      welfareAlerts.value = list.take(200).toList();
    }
  }

  // ---- Polling for the live "current" snapshot -----------------------------

  void startCurrentPolling({Duration interval = kCurrentPollInterval}) {
    if (_currentTimer != null || _demoMode) return;
    getCurrent();
    _currentTimer = Timer.periodic(interval, (_) => getCurrent());
  }

  void stopCurrentPolling() {
    _currentTimer?.cancel();
    _currentTimer = null;
  }

  // ---- Bulk refresh (history + status) -------------------------------------

  Future<void> refreshAll() async {
    if (_demoMode) {
      connection.value = FeederConnection.online;
      lastUpdated.value = DateTime.now();
      return;
    }
    connection.value = FeederConnection.connecting;
    await Future.wait([
      getSummary(),
      getStatus(),
      getStats(),
      getSpeciesSummary(),
      getSightingsRecent(),
      getWelfareAlerts(),
      getAudioRecent(),
      getIndividuals(),
    ]);
    lastUpdated.value = DateTime.now();
  }

  String _formatError(Object error) {
    final message = error.toString();
    if (message.contains('SocketException')) {
      return 'Can\'t reach the feeder — check you\'re on the same network';
    }
    if (message.contains('TimeoutException')) return 'Connection timed out';
    if (message.contains('Connection refused')) return 'Feeder isn\'t responding';
    return message.replaceFirst('Exception: ', '');
  }

  /// Synthesize a demo profile (with a health trend) for the demo feeder.
  IndividualProfile _demoProfile(String id) {
    final match = individuals.value.where((e) => e.id == id);
    final bird = match.isNotEmpty ? match.first : null;
    final now = DateTime.now();
    double ep(Duration ago) => now.subtract(ago).millisecondsSinceEpoch / 1000.0;
    final seed = id.hashCode.abs();
    final trend = List.generate(8, (i) {
      final base = 0.6 + ((seed >> i) & 3) * 0.25;
      final spike = i == 6 ? 1.4 : 0.0;
      return DistressPoint(ts: ep(Duration(days: 8 - i)), z: base + spike);
    });
    return IndividualProfile(
      id: id,
      name: bird?.name,
      species: bird?.species ?? 'Northern_Cardinal',
      display: bird?.display ?? 'Northern Cardinal',
      count: 40 + (seed % 120),
      firstSeen: now.subtract(Duration(days: 20 + seed % 30)),
      lastSeen: bird?.lastSeen ?? now.subtract(const Duration(hours: 2)),
      lastDistressZ: trend.last.z,
      distressTrend: trend,
    );
  }

  /// Quick reachability check against a base URL (e.g. for manual IP setup).
  /// Returns the parsed status on success, null otherwise.
  Future<FeederStatus?> probe(String baseUrl) async {
    final normalized =
        baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    try {
      final response = await _client
          .get(Uri.parse('$normalized/api/status'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;
      return FeederStatus.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('FeederApiService: probe $e');
      return null;
    }
  }

  /// Serve canned demo data without any network access.
  void enableDemo() {
    _demoMode = true;
    _consecutiveFailures = 0;
    stopCurrentPolling();
    double ep(Duration ago) =>
        DateTime.now().subtract(ago).millisecondsSinceEpoch / 1000.0;

    status.value = const FeederStatus(
      backend: 'Hailo',
      detectionEnabled: true,
      has3d: true,
      hasHailo: true,
      hasIndividualId: true,
      mode: 'Full 3D Mode',
      uptime: 86400,
    );
    stats.value = const FeederStatsCounters(
      fps: 15.3,
      totalDetections: 247,
      totalEnrollments: 23,
      totalTriggers: 5,
      uptimeSeconds: 86400,
    );
    summary.value = FeederSummary(
      speciesCount: 7,
      individualsCount: 23,
      totalSightings: 247,
      welfareAlerts24h: 1,
      uptimeSeconds: 86400,
      ts: ep(Duration.zero),
      topSpecies: const [
        TopSpecies(species: 'Northern_Cardinal', display: 'Northern Cardinal', count: 68),
        TopSpecies(species: 'Blue_Jay', display: 'Blue Jay', count: 45),
        TopSpecies(species: 'House_Finch', display: 'House Finch', count: 38),
        TopSpecies(species: 'American_Robin', display: 'American Robin', count: 32),
        TopSpecies(species: 'Black_Capped_Chickadee', display: 'Black-capped Chickadee', count: 28),
      ],
    );
    lifeList.value = [
      SpeciesLifeEntry(species: 'Northern_Cardinal', display: 'Northern Cardinal', count: 68, firstSeen: DateTime.now().subtract(const Duration(days: 45)), lastSeen: DateTime.now().subtract(const Duration(minutes: 12))),
      SpeciesLifeEntry(species: 'Blue_Jay', display: 'Blue Jay', count: 45, firstSeen: DateTime.now().subtract(const Duration(days: 30)), lastSeen: DateTime.now().subtract(const Duration(hours: 1, minutes: 35))),
      SpeciesLifeEntry(species: 'House_Finch', display: 'House Finch', count: 38, firstSeen: DateTime.now().subtract(const Duration(days: 15)), lastSeen: DateTime.now().subtract(const Duration(hours: 1, minutes: 10))),
      SpeciesLifeEntry(species: 'American_Robin', display: 'American Robin', count: 32, firstSeen: DateTime.now().subtract(const Duration(days: 22)), lastSeen: DateTime.now().subtract(const Duration(hours: 4))),
      SpeciesLifeEntry(species: 'Black_Capped_Chickadee', display: 'Black-capped Chickadee', count: 28, firstSeen: DateTime.now().subtract(const Duration(days: 12)), lastSeen: DateTime.now().subtract(const Duration(minutes: 28))),
      SpeciesLifeEntry(species: 'Mourning_Dove', display: 'Mourning Dove', count: 21, firstSeen: DateTime.now().subtract(const Duration(days: 18)), lastSeen: DateTime.now().subtract(const Duration(hours: 2, minutes: 5))),
      SpeciesLifeEntry(species: 'Downy_Woodpecker', display: 'Downy Woodpecker', count: 15, firstSeen: DateTime.now().subtract(const Duration(days: 9)), lastSeen: DateTime.now().subtract(const Duration(hours: 3, minutes: 15))),
    ];
    individuals.value = [
      FeederIndividual(id: '#1', name: 'Rusty', species: 'Northern_Cardinal', lastSeen: DateTime.now().subtract(const Duration(hours: 2)), canDispense: true),
      FeederIndividual(id: '#2', name: 'Screamer', species: 'Blue_Jay', lastSeen: DateTime.now().subtract(const Duration(hours: 5))),
      FeederIndividual(id: '#3', species: 'Northern_Cardinal', lastSeen: DateTime.now().subtract(const Duration(minutes: 45))),
      FeederIndividual(id: '#4', species: 'House_Finch', lastSeen: DateTime.now().subtract(const Duration(hours: 1))),
      FeederIndividual(id: '#5', name: 'Zippy', species: 'Black_Capped_Chickadee', lastSeen: DateTime.now().subtract(const Duration(minutes: 30))),
    ];
    sightings.value = [
      Sighting(ts: ep(const Duration(minutes: 12)), species: 'Northern_Cardinal', display: 'Northern Cardinal', confidence: 0.94, individual: '#1', distressed: false),
      Sighting(ts: ep(const Duration(minutes: 28)), species: 'Black_Capped_Chickadee', display: 'Black-capped Chickadee', confidence: 0.89, individual: '#5', distressed: false),
      Sighting(ts: ep(const Duration(minutes: 45)), species: 'Northern_Cardinal', display: 'Northern Cardinal', confidence: 0.91, individual: '#3', distressed: false),
      Sighting(ts: ep(const Duration(hours: 1, minutes: 10)), species: 'House_Finch', display: 'House Finch', confidence: 0.86, individual: '#4', distressed: false),
      Sighting(ts: ep(const Duration(hours: 1, minutes: 35)), species: 'Blue_Jay', display: 'Blue Jay', confidence: 0.93, individual: '#2', distressed: false),
      Sighting(ts: ep(const Duration(hours: 2, minutes: 5)), species: 'Mourning_Dove', display: 'Mourning Dove', confidence: 0.78, distressed: false),
      Sighting(ts: ep(const Duration(hours: 2, minutes: 40)), species: 'American_Robin', display: 'American Robin', confidence: 0.71, distressZ: 2.4, distressed: true),
      Sighting(ts: ep(const Duration(hours: 3, minutes: 15)), species: 'Downy_Woodpecker', display: 'Downy Woodpecker', confidence: 0.82, distressed: false),
    ];
    welfareAlerts.value = [
      WelfareAlert(ts: ep(const Duration(hours: 2, minutes: 40)), species: 'American_Robin', display: 'American Robin', distressZ: 2.4),
    ];
    audioHeard.value = [
      AudioHeard(ts: ep(const Duration(minutes: 3)), species: 'Song Sparrow', confidence: 0.61),
      AudioHeard(ts: ep(const Duration(minutes: 9)), species: 'American Goldfinch', confidence: 0.55),
      AudioHeard(ts: ep(const Duration(minutes: 21)), species: 'Northern Cardinal', confidence: 0.72),
    ];
    current.value = CurrentState(
      species: 'Northern_Cardinal_ID_852',
      speciesDisplay: 'Northern Cardinal',
      speciesConfidence: 0.94,
      individual: '#1',
      individualName: 'Rusty',
      welfare: const WelfareInfo(distressZ: 0.4, distressed: false),
      audio: const AudioSnapshot(detections: [AudioDetection(species: 'Song Sparrow', confidence: 0.61)]),
      totalDetections: 247,
      backend: 'Hailo',
      hasHailo: true,
      ts: ep(Duration.zero),
    );
    isConnected.value = true;
    connection.value = FeederConnection.online;
    lastUpdated.value = DateTime.now();
  }

  void clear() {
    stopCurrentPolling();
    _demoMode = false;
    _consecutiveFailures = 0;
    _baseUrl = null;
    connection.value = FeederConnection.unknown;
    isConnected.value = false;
    current.value = null;
    status.value = null;
    stats.value = null;
    summary.value = null;
    lifeList.value = const [];
    sightings.value = const [];
    welfareAlerts.value = const [];
    audioHeard.value = const [];
    individuals.value = const [];
    errorMessage.value = null;
    lastUpdated.value = null;
  }
}
