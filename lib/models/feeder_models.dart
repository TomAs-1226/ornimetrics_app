/// Data models for Ornimetrics OS integration
/// Includes Bluetooth commands, API responses, and Firebase data structures

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
// REST API MODELS
// ============================================================================

/// System status from GET /api/status
class FeederSystemStatus {
  final SystemInfo system;
  final HardwareInfo hardware;
  final DetectionInfo detection;

  const FeederSystemStatus({
    required this.system,
    required this.hardware,
    required this.detection,
  });

  factory FeederSystemStatus.fromJson(Map<String, dynamic> json) {
    return FeederSystemStatus(
      system: SystemInfo.fromJson(json['system'] ?? {}),
      hardware: HardwareInfo.fromJson(json['hardware'] ?? {}),
      detection: DetectionInfo.fromJson(json['detection'] ?? {}),
    );
  }
}

class SystemInfo {
  final int uptimeSeconds;
  final String deviceId;
  final String version;
  final bool accountLinked;

  const SystemInfo({
    required this.uptimeSeconds,
    required this.deviceId,
    required this.version,
    required this.accountLinked,
  });

  factory SystemInfo.fromJson(Map<String, dynamic> json) {
    return SystemInfo(
      uptimeSeconds: json['uptime_seconds'] ?? 0,
      deviceId: json['device_id'] ?? '',
      version: json['version'] ?? '1.0.0',
      accountLinked: json['account_linked'] ?? false,
    );
  }

  String get formattedUptime {
    final hours = uptimeSeconds ~/ 3600;
    final minutes = (uptimeSeconds % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
}

class HardwareInfo {
  final bool depthCameraAvailable;
  final bool hailoAvailable;
  final String mode;

  const HardwareInfo({
    required this.depthCameraAvailable,
    required this.hailoAvailable,
    required this.mode,
  });

  factory HardwareInfo.fromJson(Map<String, dynamic> json) {
    return HardwareInfo(
      depthCameraAvailable: json['depth_camera_available'] ?? false,
      hailoAvailable: json['hailo_available'] ?? false,
      mode: json['mode'] ?? 'Standard Mode',
    );
  }
}

class DetectionInfo {
  final bool active;
  final double fps;
  final int totalDetections;

  const DetectionInfo({
    required this.active,
    required this.fps,
    required this.totalDetections,
  });

  factory DetectionInfo.fromJson(Map<String, dynamic> json) {
    return DetectionInfo(
      active: json['active'] ?? false,
      fps: (json['fps'] as num?)?.toDouble() ?? 0.0,
      totalDetections: json['total_detections'] ?? 0,
    );
  }
}

/// Detection statistics from GET /api/stats
class FeederStats {
  final int totalDetections;
  final Map<String, int> speciesCounts;
  final int uniqueIndividuals;
  final int detectionsToday;
  final DateTime? lastDetectionTime;

  const FeederStats({
    required this.totalDetections,
    required this.speciesCounts,
    required this.uniqueIndividuals,
    required this.detectionsToday,
    this.lastDetectionTime,
  });

  factory FeederStats.fromJson(Map<String, dynamic> json) {
    final species = <String, int>{};
    final speciesData = json['species_counts'];
    if (speciesData is Map) {
      speciesData.forEach((key, value) {
        species[key.toString()] = (value as num?)?.toInt() ?? 0;
      });
    }

    DateTime? lastDetection;
    if (json['last_detection_time'] != null) {
      try {
        lastDetection = DateTime.parse(json['last_detection_time']);
      } catch (_) {}
    }

    return FeederStats(
      totalDetections: json['total_detections'] ?? 0,
      speciesCounts: species,
      uniqueIndividuals: json['unique_individuals'] ?? 0,
      detectionsToday: json['detections_today'] ?? 0,
      lastDetectionTime: lastDetection,
    );
  }

  int get speciesCount => speciesCounts.length;
}

/// Individual bird from GET /api/individuals
class FeederIndividual {
  final int id;
  final String species;
  final String name;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final int visitCount;
  final double confidence;
  final String? thumbnailUrl;

  const FeederIndividual({
    required this.id,
    required this.species,
    required this.name,
    required this.firstSeen,
    required this.lastSeen,
    required this.visitCount,
    required this.confidence,
    this.thumbnailUrl,
  });

  factory FeederIndividual.fromJson(Map<String, dynamic> json) {
    return FeederIndividual(
      id: json['id'] ?? 0,
      species: json['species'] ?? 'Unknown',
      name: json['name'] ?? 'Bird #${json['id'] ?? 0}',
      firstSeen: _parseDateTime(json['first_seen']),
      lastSeen: _parseDateTime(json['last_seen']),
      visitCount: json['visit_count'] ?? 0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      thumbnailUrl: json['thumbnail_url'],
    );
  }

  String get formattedSpecies => species.replaceAll('_', ' ');

  Color get confidenceColor {
    if (confidence >= 0.9) return Colors.green;
    if (confidence >= 0.7) return Colors.orange;
    return Colors.red;
  }
}

/// Detection event from GET /api/recent_detections
class FeederDetection {
  final DateTime timestamp;
  final String species;
  final double confidence;
  final int? individualId;
  final List<int>? bbox;
  final bool has3d;
  final String? imageUrl;

  const FeederDetection({
    required this.timestamp,
    required this.species,
    required this.confidence,
    this.individualId,
    this.bbox,
    required this.has3d,
    this.imageUrl,
  });

  factory FeederDetection.fromJson(Map<String, dynamic> json) {
    List<int>? parsedBbox;
    if (json['bbox'] is List) {
      parsedBbox = (json['bbox'] as List).map((e) => (e as num).toInt()).toList();
    }

    return FeederDetection(
      timestamp: _parseDateTime(json['timestamp']),
      species: json['species'] ?? 'Unknown',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      individualId: json['individual_id'],
      bbox: parsedBbox,
      has3d: json['has_3d'] ?? false,
      imageUrl: json['image_url'],
    );
  }

  String get formattedSpecies => species.replaceAll('_', ' ');

  Color get confidenceColor {
    if (confidence >= 0.9) return Colors.green;
    if (confidence >= 0.7) return Colors.orange;
    return Colors.red;
  }
}

/// Training status from GET /api/training/status
class TrainingStatus {
  final bool trainingEnabled;
  final bool isTraining;
  final bool nightModeActive;
  final TrainingProgress trainingProgress;
  final bool datasetReady;
  final Map<String, int> speciesCounts;
  final DateTime? lastTrainingTime;

  const TrainingStatus({
    required this.trainingEnabled,
    required this.isTraining,
    required this.nightModeActive,
    required this.trainingProgress,
    required this.datasetReady,
    required this.speciesCounts,
    this.lastTrainingTime,
  });

  factory TrainingStatus.fromJson(Map<String, dynamic> json) {
    final species = <String, int>{};
    final speciesData = json['species_counts'];
    if (speciesData is Map) {
      speciesData.forEach((key, value) {
        species[key.toString()] = (value as num?)?.toInt() ?? 0;
      });
    }

    DateTime? lastTraining;
    if (json['last_training_time'] != null) {
      try {
        lastTraining = DateTime.parse(json['last_training_time']);
      } catch (_) {}
    }

    return TrainingStatus(
      trainingEnabled: json['training_enabled'] ?? false,
      isTraining: json['is_training'] ?? false,
      nightModeActive: json['night_mode_active'] ?? false,
      trainingProgress: TrainingProgress.fromJson(json['training_status'] ?? {}),
      datasetReady: json['dataset_ready'] ?? false,
      speciesCounts: species,
      lastTrainingTime: lastTraining,
    );
  }
}

class TrainingProgress {
  final String status;
  final double progress;
  final String message;

  const TrainingProgress({
    required this.status,
    required this.progress,
    required this.message,
  });

  factory TrainingProgress.fromJson(Map<String, dynamic> json) {
    return TrainingProgress(
      status: json['status'] ?? 'idle',
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      message: json['message'] ?? '',
    );
  }

  bool get isIdle => status == 'idle';
  bool get isRunning => status == 'training' || status == 'running';
  bool get isComplete => status == 'complete' || status == 'completed';
  bool get hasError => status == 'error' || status == 'failed';
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
