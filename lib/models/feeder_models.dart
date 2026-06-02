/// Data models for Ornimetrics OS integration.
///
/// The REST models in this file follow the real feeder contract documented in
/// `docs/API.md` (the on-device Raspberry Pi 5 + Hailo-8 HTTP API on port 5000).
/// Bluetooth onboarding, Firebase and paired-device models are unchanged.

library;

import 'package:flutter/material.dart';

// ============================================================================
// BLUETOOTH MODELS
// ============================================================================

/// Represents a discovered Ornimetrics device via Bluetooth
class OrnimetricsDevice {
  final String id;
  final String name;
  final String? hostname;
  final int rssi;
  final bool isConnectable;

  const OrnimetricsDevice({
    required this.id,
    required this.name,
    this.hostname,
    this.rssi = 0,
    this.isConnectable = true,
  });

  String get displayName => name.replaceFirst('Ornimetrics-', '');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrnimetricsDevice && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Welcome message received when connecting to a device
class DeviceWelcome {
  final String deviceId;
  final String deviceName;
  final String version;
  final bool requiresPairing;

  const DeviceWelcome({
    required this.deviceId,
    required this.deviceName,
    required this.version,
    required this.requiresPairing,
  });

  factory DeviceWelcome.fromJson(Map<String, dynamic> json) {
    return DeviceWelcome(
      deviceId: json['device_id'] ?? '',
      deviceName: json['device_name'] ?? 'Unknown Device',
      version: json['version'] ?? '1.0.0',
      requiresPairing: json['requires_pairing'] ?? true,
    );
  }
}

/// Pairing session information
class PairingSession {
  final String sessionToken;
  final String deviceId;

  const PairingSession({
    required this.sessionToken,
    required this.deviceId,
  });

  factory PairingSession.fromJson(Map<String, dynamic> json) {
    return PairingSession(
      sessionToken: json['session_token'] ?? '',
      deviceId: json['device_id'] ?? '',
    );
  }
}

/// Device status response
class FeederDeviceStatus {
  final String deviceId;
  final String deviceName;
  final String version;
  final bool accountLinked;
  final bool wifiConfigured;
  final String? staticIp;
  final StreamingInfo? streaming;

  const FeederDeviceStatus({
    required this.deviceId,
    required this.deviceName,
    required this.version,
    required this.accountLinked,
    required this.wifiConfigured,
    this.staticIp,
    this.streaming,
  });

  factory FeederDeviceStatus.fromJson(Map<String, dynamic> json) {
    return FeederDeviceStatus(
      deviceId: json['device_id'] ?? '',
      deviceName: json['device_name'] ?? 'Unknown Device',
      version: json['version'] ?? '1.0.0',
      accountLinked: json['account_linked'] ?? false,
      wifiConfigured: json['wifi_configured'] ?? false,
      staticIp: json['static_ip'],
      streaming: json['streaming'] != null
          ? StreamingInfo.fromJson(json['streaming'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'device_name': deviceName,
        'version': version,
        'account_linked': accountLinked,
        'wifi_configured': wifiConfigured,
        'static_ip': staticIp,
        if (streaming != null) 'streaming': streaming!.toJson(),
      };
}

/// Streaming URLs
class StreamingInfo {
  final bool enabled;
  final String? mjpegUrl;
  final String? rtspUrl;

  const StreamingInfo({
    required this.enabled,
    this.mjpegUrl,
    this.rtspUrl,
  });

  factory StreamingInfo.fromJson(Map<String, dynamic> json) {
    return StreamingInfo(
      enabled: json['enabled'] ?? false,
      mjpegUrl: json['mjpeg_url'],
      rtspUrl: json['rtsp_url'],
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        if (mjpegUrl != null) 'mjpeg_url': mjpegUrl,
        if (rtspUrl != null) 'rtsp_url': rtspUrl,
      };
}

/// WiFi configuration result
class WifiConfigResult {
  final bool success;
  final String ssid;
  final String? staticIp;
  final String? errorMessage;

  const WifiConfigResult({
    required this.success,
    required this.ssid,
    this.staticIp,
    this.errorMessage,
  });

  factory WifiConfigResult.fromJson(Map<String, dynamic> json) {
    final type = json['type'] ?? '';
    return WifiConfigResult(
      success: type == 'wifi_configured',
      ssid: json['ssid'] ?? '',
      staticIp: json['static_ip'],
      errorMessage: type == 'error' ? json['message'] : null,
    );
  }
}

// ============================================================================
// REST API MODELS  (real contract — see docs/API.md)
// ============================================================================

/// Turn a raw class name (e.g. `Carolina_Chickadee_ID_811`) into a clean
/// display string. Strips the `_ID_<n>` suffix and replaces underscores.
String cleanSpeciesName(String? raw) {
  if (raw == null || raw.isEmpty) return 'Unknown';
  // Remove a trailing _ID_<digits> suffix.
  final stripped = raw.replaceAll(RegExp(r'_ID_\d+$'), '');
  return stripped.replaceAll('_', ' ').trim();
}

/// Live AI output from `GET /api/current` — drives the main screen.
class CurrentState {
  final String? species; // raw class, null if no bird right now
  final String? speciesDisplay; // clean display name
  final double? speciesConfidence;
  final String? individual; // gallery id like "#3"
  final String? individualName; // custom name if set, else the id
  final WelfareInfo welfare;
  final AudioSnapshot audio;
  final int totalDetections;
  final String backend;
  final bool hasHailo;
  final double ts;

  const CurrentState({
    this.species,
    this.speciesDisplay,
    this.speciesConfidence,
    this.individual,
    this.individualName,
    required this.welfare,
    required this.audio,
    required this.totalDetections,
    required this.backend,
    required this.hasHailo,
    required this.ts,
  });

  factory CurrentState.fromJson(Map<String, dynamic> json) {
    return CurrentState(
      species: json['species'] as String?,
      speciesDisplay: json['species_display'] as String?,
      speciesConfidence: (json['species_confidence'] as num?)?.toDouble(),
      individual: json['individual'] as String?,
      individualName: json['individual_name'] as String?,
      welfare: WelfareInfo.fromJson(json['welfare'] as Map<String, dynamic>? ?? const {}),
      audio: AudioSnapshot.fromJson(json['audio'] as Map<String, dynamic>? ?? const {}),
      totalDetections: (json['total_detections'] as num?)?.toInt() ?? 0,
      backend: json['backend'] as String? ?? 'Unknown',
      hasHailo: json['has_hailo'] as bool? ?? false,
      ts: (json['ts'] as num?)?.toDouble() ?? 0,
    );
  }

  /// True when there is a bird in frame right now.
  bool get hasBird => species != null;

  /// Best display name for the current species.
  String get displaySpecies =>
      speciesDisplay ?? (species != null ? cleanSpeciesName(species) : 'No bird');

  /// Best display name for the current individual (custom name else id).
  String? get displayIndividual => individualName ?? individual;
}

/// Welfare screening info — a flag for a human, never a diagnosis.
class WelfareInfo {
  final double? distressZ;
  final bool distressed;

  const WelfareInfo({this.distressZ, required this.distressed});

  factory WelfareInfo.fromJson(Map<String, dynamic> json) {
    return WelfareInfo(
      distressZ: (json['distress_z'] as num?)?.toDouble(),
      distressed: json['distressed'] as bool? ?? false,
    );
  }
}

/// Audio snapshot embedded in `/api/current`.
class AudioSnapshot {
  final String? ts;
  final List<AudioDetection> detections;

  const AudioSnapshot({this.ts, required this.detections});

  factory AudioSnapshot.fromJson(Map<String, dynamic> json) {
    final list = (json['detections'] as List?) ?? const [];
    return AudioSnapshot(
      ts: json['ts'] as String?,
      detections: list
          .whereType<Map>()
          .map((e) => AudioDetection.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }
}

class AudioDetection {
  final String species;
  final double confidence;

  const AudioDetection({required this.species, required this.confidence});

  factory AudioDetection.fromJson(Map<String, dynamic> json) {
    return AudioDetection(
      species: json['species'] as String? ?? 'Unknown',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Hardware/mode from `GET /api/status`.
class FeederStatus {
  final String backend;
  final bool detectionEnabled;
  final bool has3d;
  final bool hasHailo;
  final bool hasIndividualId;
  final String mode;
  final double uptime;

  const FeederStatus({
    required this.backend,
    required this.detectionEnabled,
    required this.has3d,
    required this.hasHailo,
    required this.hasIndividualId,
    required this.mode,
    required this.uptime,
  });

  factory FeederStatus.fromJson(Map<String, dynamic> json) {
    return FeederStatus(
      backend: json['backend'] as String? ?? 'Unknown',
      detectionEnabled: json['detection_enabled'] as bool? ?? false,
      has3d: json['has_3d'] as bool? ?? false,
      hasHailo: json['has_hailo'] as bool? ?? false,
      hasIndividualId: json['has_individual_id'] as bool? ?? false,
      mode: json['mode'] as String? ?? 'Standard',
      uptime: (json['uptime'] as num?)?.toDouble() ?? 0,
    );
  }

  String get formattedUptime => _formatDuration(uptime);
}

/// Counters from `GET /api/stats`.
class FeederStatsCounters {
  final double fps;
  final int totalDetections;
  final int totalEnrollments;
  final int totalTriggers;
  final double uptimeSeconds;

  const FeederStatsCounters({
    required this.fps,
    required this.totalDetections,
    required this.totalEnrollments,
    required this.totalTriggers,
    required this.uptimeSeconds,
  });

  factory FeederStatsCounters.fromJson(Map<String, dynamic> json) {
    return FeederStatsCounters(
      fps: (json['fps'] as num?)?.toDouble() ?? 0,
      totalDetections: (json['total_detections'] as num?)?.toInt() ?? 0,
      totalEnrollments: (json['total_enrollments'] as num?)?.toInt() ?? 0,
      totalTriggers: (json['total_triggers'] as num?)?.toInt() ?? 0,
      uptimeSeconds: (json['uptime_seconds'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Home digest from `GET /api/summary`.
class FeederSummary {
  final int speciesCount;
  final int individualsCount;
  final int totalSightings;
  final int welfareAlerts24h;
  final List<TopSpecies> topSpecies;
  final double uptimeSeconds;
  final double ts;

  const FeederSummary({
    required this.speciesCount,
    required this.individualsCount,
    required this.totalSightings,
    required this.welfareAlerts24h,
    required this.topSpecies,
    required this.uptimeSeconds,
    required this.ts,
  });

  factory FeederSummary.fromJson(Map<String, dynamic> json) {
    final top = (json['top_species'] as List?) ?? const [];
    return FeederSummary(
      speciesCount: (json['species_count'] as num?)?.toInt() ?? 0,
      individualsCount: (json['individuals_count'] as num?)?.toInt() ?? 0,
      totalSightings: (json['total_sightings'] as num?)?.toInt() ?? 0,
      welfareAlerts24h: (json['welfare_alerts_24h'] as num?)?.toInt() ?? 0,
      topSpecies: top
          .whereType<Map>()
          .map((e) => TopSpecies.fromJson(e.cast<String, dynamic>()))
          .toList(),
      uptimeSeconds: (json['uptime_seconds'] as num?)?.toDouble() ?? 0,
      ts: (json['ts'] as num?)?.toDouble() ?? 0,
    );
  }

  String get formattedUptime => _formatDuration(uptimeSeconds);
}

class TopSpecies {
  final String species;
  final String display;
  final int count;

  const TopSpecies({required this.species, required this.display, required this.count});

  factory TopSpecies.fromJson(Map<String, dynamic> json) {
    return TopSpecies(
      species: json['species'] as String? ?? '',
      display: json['display'] as String? ?? cleanSpeciesName(json['species'] as String?),
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One entry of the life-list from `GET /api/species/summary`.
class SpeciesLifeEntry {
  final String species;
  final String display;
  final int count;
  final DateTime? firstSeen;
  final DateTime? lastSeen;

  const SpeciesLifeEntry({
    required this.species,
    required this.display,
    required this.count,
    this.firstSeen,
    this.lastSeen,
  });

  factory SpeciesLifeEntry.fromJson(Map<String, dynamic> json) {
    return SpeciesLifeEntry(
      species: json['species'] as String? ?? '',
      display: json['display'] as String? ?? cleanSpeciesName(json['species'] as String?),
      count: (json['count'] as num?)?.toInt() ?? 0,
      firstSeen: _dtFromEpoch(json['first_seen']),
      lastSeen: _dtFromEpoch(json['last_seen']),
    );
  }
}

/// A visit-level sighting from `GET /api/sightings/recent` and the SSE
/// `sighting` event.
class Sighting {
  final double ts;
  final String species;
  final String display;
  final double? confidence;
  final String? individual;
  final double? distressZ;
  final bool distressed;

  const Sighting({
    required this.ts,
    required this.species,
    required this.display,
    this.confidence,
    this.individual,
    this.distressZ,
    required this.distressed,
  });

  factory Sighting.fromJson(Map<String, dynamic> json) {
    return Sighting(
      ts: (json['ts'] as num?)?.toDouble() ?? 0,
      species: json['species'] as String? ?? '',
      display: json['display'] as String? ?? cleanSpeciesName(json['species'] as String?),
      confidence: (json['confidence'] as num?)?.toDouble(),
      individual: json['individual'] as String?,
      distressZ: (json['distress_z'] as num?)?.toDouble(),
      distressed: json['distressed'] as bool? ?? false,
    );
  }

  DateTime get dateTime => _dtFromEpoch(ts) ?? DateTime.now();
  String get displayName => display.isNotEmpty ? display : cleanSpeciesName(species);
}

/// One bird's profile + health trend from `GET /api/individual/<id>`.
class IndividualProfile {
  final String id;
  final String? name;
  final String species;
  final String display;
  final int count;
  final DateTime? firstSeen;
  final DateTime? lastSeen;
  final double? lastDistressZ;
  final List<DistressPoint> distressTrend;

  const IndividualProfile({
    required this.id,
    this.name,
    required this.species,
    required this.display,
    required this.count,
    this.firstSeen,
    this.lastSeen,
    this.lastDistressZ,
    required this.distressTrend,
  });

  factory IndividualProfile.fromJson(Map<String, dynamic> json) {
    final trend = (json['distress_trend'] as List?) ?? const [];
    return IndividualProfile(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String?,
      species: json['species'] as String? ?? '',
      display: json['display'] as String? ?? cleanSpeciesName(json['species'] as String?),
      count: (json['count'] as num?)?.toInt() ?? 0,
      firstSeen: _dtFromEpoch(json['first_seen']),
      lastSeen: _dtFromEpoch(json['last_seen']),
      lastDistressZ: (json['last_distress_z'] as num?)?.toDouble(),
      distressTrend: trend
          .whereType<Map>()
          .map((e) => DistressPoint.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }

  String get displayName => (name != null && name!.isNotEmpty) ? name! : id;
}

class DistressPoint {
  final double ts;
  final double z;

  const DistressPoint({required this.ts, required this.z});

  factory DistressPoint.fromJson(Map<String, dynamic> json) {
    return DistressPoint(
      ts: (json['ts'] as num?)?.toDouble() ?? 0,
      z: (json['z'] as num?)?.toDouble() ?? 0,
    );
  }

  DateTime get dateTime => _dtFromEpoch(ts) ?? DateTime.now();
}

/// A welfare screening flag from `GET /api/welfare/alerts` and the SSE
/// `welfare_alert` event.
class WelfareAlert {
  final double ts;
  final String species;
  final String display;
  final String? individual;
  final double? distressZ;

  const WelfareAlert({
    required this.ts,
    required this.species,
    required this.display,
    this.individual,
    this.distressZ,
  });

  factory WelfareAlert.fromJson(Map<String, dynamic> json) {
    return WelfareAlert(
      ts: (json['ts'] as num?)?.toDouble() ?? 0,
      species: json['species'] as String? ?? '',
      display: json['display'] as String? ?? cleanSpeciesName(json['species'] as String?),
      individual: json['individual'] as String?,
      distressZ: (json['distress_z'] as num?)?.toDouble(),
    );
  }

  DateTime get dateTime => _dtFromEpoch(ts) ?? DateTime.now();
  String get displayName => display.isNotEmpty ? display : cleanSpeciesName(species);
}

/// A bird heard via the mic from `GET /api/audio/recent`.
class AudioHeard {
  final double ts;
  final String species;
  final double confidence;

  const AudioHeard({required this.ts, required this.species, required this.confidence});

  factory AudioHeard.fromJson(Map<String, dynamic> json) {
    return AudioHeard(
      ts: _epochSeconds(json['ts']),
      species: json['species'] as String? ?? 'Unknown',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    );
  }

  DateTime get dateTime => _dtFromEpoch(ts) ?? DateTime.now();
}

/// A recently-seen individual from `GET /api/individuals` (id -> info map).
class FeederIndividual {
  final String id;
  final String? name;
  final String species;
  final DateTime? lastSeen;
  final bool canDispense;
  final String? reason;

  const FeederIndividual({
    required this.id,
    this.name,
    required this.species,
    this.lastSeen,
    this.canDispense = false,
    this.reason,
  });

  factory FeederIndividual.fromId(String id, Map<String, dynamic> json) {
    return FeederIndividual(
      id: id,
      name: json['name'] as String?,
      species: json['species'] as String? ?? '',
      lastSeen: _dtFromEpoch(json['last_seen']),
      canDispense: json['can_dispense'] as bool? ?? false,
      reason: json['reason'] as String?,
    );
  }

  String get display => cleanSpeciesName(species);
  String get displayName => (name != null && name!.isNotEmpty) ? name! : id;

  Color confidenceColor(ColorScheme scheme) => scheme.primary;
}

// ============================================================================
// FIREBASE MODELS
// ============================================================================

/// Firebase detection document
class FirebaseDetection {
  final String id;
  final DateTime timestamp;
  final String species;
  final double yoloConfidence;
  final int? individualId;
  final double? individualConfidence;
  final List<int>? bbox;
  final bool has3d;
  final String? imageUrl;
  final String? pointcloudUrl;
  final OrnimetricsOSMetadata? metadata;

  const FirebaseDetection({
    required this.id,
    required this.timestamp,
    required this.species,
    required this.yoloConfidence,
    this.individualId,
    this.individualConfidence,
    this.bbox,
    required this.has3d,
    this.imageUrl,
    this.pointcloudUrl,
    this.metadata,
  });

  factory FirebaseDetection.fromJson(String id, Map<String, dynamic> json) {
    List<int>? parsedBbox;
    if (json['bbox'] is List) {
      parsedBbox = (json['bbox'] as List).map((e) => (e as num).toInt()).toList();
    }

    return FirebaseDetection(
      id: id,
      timestamp: _parseDateTime(json['timestamp']),
      species: json['species'] ?? 'Unknown',
      yoloConfidence: (json['yolo_confidence'] as num?)?.toDouble() ?? 0.0,
      individualId: json['individual_id'],
      individualConfidence: (json['individual_confidence'] as num?)?.toDouble(),
      bbox: parsedBbox,
      has3d: json['has_3d'] ?? false,
      imageUrl: json['image_url'],
      pointcloudUrl: json['pointcloud_url'],
      metadata: json['_ornimetrics_os'] != null
          ? OrnimetricsOSMetadata.fromJson(json['_ornimetrics_os'])
          : null,
    );
  }

  String get formattedSpecies => species.replaceAll('_', ' ');
}

/// Firebase individual document
class FirebaseIndividual {
  final String id;
  final int numericId;
  final String species;
  final String name;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final int visitCount;
  final double averageConfidence;

  const FirebaseIndividual({
    required this.id,
    required this.numericId,
    required this.species,
    required this.name,
    required this.firstSeen,
    required this.lastSeen,
    required this.visitCount,
    required this.averageConfidence,
  });

  factory FirebaseIndividual.fromJson(String id, Map<String, dynamic> json) {
    return FirebaseIndividual(
      id: id,
      numericId: json['id'] ?? 0,
      species: json['species'] ?? 'Unknown',
      name: json['name'] ?? 'Bird #${json['id'] ?? 0}',
      firstSeen: _parseDateTime(json['first_seen']),
      lastSeen: _parseDateTime(json['last_seen']),
      visitCount: json['visit_count'] ?? 0,
      averageConfidence: (json['average_confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }

  String get formattedSpecies => species.replaceAll('_', ' ');
}

/// Firebase daily statistics document
class FirebaseDailyStats {
  final String date;
  final int totalDetections;
  final int uniqueIndividuals;
  final Map<String, int> speciesBreakdown;
  final String? busiestHour;
  final int peakDetections;

  const FirebaseDailyStats({
    required this.date,
    required this.totalDetections,
    required this.uniqueIndividuals,
    required this.speciesBreakdown,
    this.busiestHour,
    required this.peakDetections,
  });

  factory FirebaseDailyStats.fromJson(String id, Map<String, dynamic> json) {
    final species = <String, int>{};
    final speciesData = json['species_breakdown'];
    if (speciesData is Map) {
      speciesData.forEach((key, value) {
        species[key.toString()] = (value as num?)?.toInt() ?? 0;
      });
    }

    return FirebaseDailyStats(
      date: json['date'] ?? id,
      totalDetections: json['total_detections'] ?? 0,
      uniqueIndividuals: json['unique_individuals'] ?? 0,
      speciesBreakdown: species,
      busiestHour: json['busiest_hour'],
      peakDetections: json['peak_detections'] ?? 0,
    );
  }
}

/// Metadata included with Firebase detections
class OrnimetricsOSMetadata {
  final String version;
  final String deviceId;
  final String feederName;

  const OrnimetricsOSMetadata({
    required this.version,
    required this.deviceId,
    required this.feederName,
  });

  factory OrnimetricsOSMetadata.fromJson(Map<String, dynamic> json) {
    return OrnimetricsOSMetadata(
      version: json['version'] ?? '1.0.0',
      deviceId: json['device_id'] ?? '',
      feederName: json['feeder_name'] ?? 'Ornimetrics Feeder',
    );
  }
}

// ============================================================================
// PAIRED DEVICE STORAGE
// ============================================================================

/// Locally stored paired device information
class PairedFeeder {
  final String deviceId;
  final String deviceName;
  final String feederName;
  final String staticIp;
  final String version;
  final DateTime pairedAt;
  final String userId;

  const PairedFeeder({
    required this.deviceId,
    required this.deviceName,
    required this.feederName,
    required this.staticIp,
    required this.version,
    required this.pairedAt,
    required this.userId,
  });

  factory PairedFeeder.fromJson(Map<String, dynamic> json) {
    return PairedFeeder(
      deviceId: json['device_id'] ?? '',
      deviceName: json['device_name'] ?? 'Unknown Device',
      feederName: json['feeder_name'] ?? 'My Feeder',
      staticIp: json['static_ip'] ?? '192.168.1.200',
      version: json['version'] ?? '1.0.0',
      pairedAt: _parseDateTime(json['paired_at']),
      userId: json['user_id'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'device_name': deviceName,
        'feeder_name': feederName,
        'static_ip': staticIp,
        'version': version,
        'paired_at': pairedAt.toIso8601String(),
        'user_id': userId,
      };

  String get apiBaseUrl => 'http://$staticIp:5000';
  String get mjpegStreamUrl => 'http://$staticIp:5000/video_feed';
  String get rtspStreamUrl => 'rtsp://$staticIp:8554/ornimetrics/stream';
}

// ============================================================================
// BLUETOOTH COMMAND TYPES
// ============================================================================

enum BluetoothCommandType {
  pair,
  linkAccount,
  configureWifi,
  updateSettings,
  getStatus,
}

enum SetupStep {
  scanning,
  connecting,
  pairing,
  linkingAccount,
  configuringWifi,
  verifying,
  complete,
}

extension SetupStepExtension on SetupStep {
  String get title {
    switch (this) {
      case SetupStep.scanning:
        return 'Scanning';
      case SetupStep.connecting:
        return 'Connecting';
      case SetupStep.pairing:
        return 'Pairing';
      case SetupStep.linkingAccount:
        return 'Linking Account';
      case SetupStep.configuringWifi:
        return 'WiFi Setup';
      case SetupStep.verifying:
        return 'Verifying';
      case SetupStep.complete:
        return 'Complete';
    }
  }

  String get description {
    switch (this) {
      case SetupStep.scanning:
        return 'Looking for nearby Ornimetrics feeders...';
      case SetupStep.connecting:
        return 'Establishing Bluetooth connection...';
      case SetupStep.pairing:
        return 'Securing connection with device...';
      case SetupStep.linkingAccount:
        return 'Linking device to your account...';
      case SetupStep.configuringWifi:
        return 'Configuring WiFi network...';
      case SetupStep.verifying:
        return 'Verifying device connectivity...';
      case SetupStep.complete:
        return 'Setup complete!';
    }
  }

  int get stepIndex {
    switch (this) {
      case SetupStep.scanning:
        return 0;
      case SetupStep.connecting:
        return 1;
      case SetupStep.pairing:
        return 2;
      case SetupStep.linkingAccount:
        return 3;
      case SetupStep.configuringWifi:
        return 4;
      case SetupStep.verifying:
        return 5;
      case SetupStep.complete:
        return 6;
    }
  }
}

// ============================================================================
// HELPERS
// ============================================================================

DateTime _parseDateTime(dynamic value) {
  if (value == null) return DateTime.now();
  if (value is DateTime) return value;
  if (value is String) {
    try {
      return DateTime.parse(value);
    } catch (_) {}
  }
  if (value is int) {
    if (value > 100000000000) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return DateTime.fromMillisecondsSinceEpoch(value * 1000);
  }
  return DateTime.now();
}

/// Coerce an epoch value (seconds or millis, int/double/String) to seconds.
double _epochSeconds(dynamic value) {
  if (value is num) {
    final d = value.toDouble();
    return d > 1e12 ? d / 1000.0 : d; // millis -> seconds
  }
  if (value is String) {
    final parsed = double.tryParse(value);
    if (parsed != null) return parsed > 1e12 ? parsed / 1000.0 : parsed;
    final dt = DateTime.tryParse(value);
    if (dt != null) return dt.millisecondsSinceEpoch / 1000.0;
  }
  return 0;
}

/// Parse an epoch (seconds or millis) or ISO string into a [DateTime].
DateTime? _dtFromEpoch(dynamic value) {
  if (value == null) return null;
  if (value is String) {
    final dt = DateTime.tryParse(value);
    if (dt != null) return dt;
    final parsed = double.tryParse(value);
    if (parsed != null) {
      return DateTime.fromMillisecondsSinceEpoch(
          (parsed > 1e12 ? parsed : parsed * 1000).round());
    }
    return null;
  }
  if (value is num) {
    final d = value.toDouble();
    if (d <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch((d > 1e12 ? d : d * 1000).round());
  }
  return null;
}

String _formatDuration(double seconds) {
  final s = seconds.round();
  final days = s ~/ 86400;
  final hours = (s % 86400) ~/ 3600;
  final minutes = (s % 3600) ~/ 60;
  if (days > 0) return '${days}d ${hours}h';
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m';
  return '${s}s';
}
