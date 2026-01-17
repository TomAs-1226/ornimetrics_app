/// REST API service for Ornimetrics OS feeder local network communication
/// Handles status, stats, individuals, detections, and training endpoints

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/feeder_models.dart';

const Duration kApiTimeout = Duration(seconds: 10);
const Duration kPollingInterval = Duration(seconds: 5);

class FeederApiService {
  static final FeederApiService instance = FeederApiService._();
  FeederApiService._();

  // State notifiers
  final ValueNotifier<bool> isConnected = ValueNotifier(false);
  final ValueNotifier<bool> isPolling = ValueNotifier(false);
  final ValueNotifier<FeederSystemStatus?> systemStatus = ValueNotifier(null);
  final ValueNotifier<FeederStats?> stats = ValueNotifier(null);
  final ValueNotifier<List<FeederIndividual>> individuals = ValueNotifier([]);
  final ValueNotifier<List<FeederDetection>> recentDetections = ValueNotifier([]);
  final ValueNotifier<TrainingStatus?> trainingStatus = ValueNotifier(null);
  final ValueNotifier<String?> errorMessage = ValueNotifier(null);
  final ValueNotifier<DateTime?> lastUpdated = ValueNotifier(null);

  // Internal state
  String? _baseUrl;
  Timer? _pollingTimer;
  final http.Client _client = http.Client();

  /// Set the base URL for API calls
  void setBaseUrl(String baseUrl) {
    _baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    debugPrint('FeederApiService: Base URL set to $_baseUrl');
  }

  /// Set from paired feeder
  void setFromPairedFeeder(PairedFeeder feeder) {
    setBaseUrl(feeder.apiBaseUrl);
  }

  /// Check if the feeder is reachable
  Future<bool> checkConnection() async {
    if (_baseUrl == null) {
      errorMessage.value = 'No device configured';
      return false;
    }

    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/api/status'))
          .timeout(kApiTimeout);

      isConnected.value = response.statusCode == 200;
      errorMessage.value = null;
      return isConnected.value;
    } catch (e) {
      isConnected.value = false;
      errorMessage.value = 'Connection failed: ${_formatError(e)}';
      debugPrint('FeederApiService: Connection check failed: $e');
      return false;
    }
  }

  /// Get system status
  Future<FeederSystemStatus?> getStatus() async {
    if (_baseUrl == null) {
      errorMessage.value = 'No device configured';
      return null;
    }

    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/api/status'))
          .timeout(kApiTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final status = FeederSystemStatus.fromJson(json);
        systemStatus.value = status;
        isConnected.value = true;
        lastUpdated.value = DateTime.now();
        errorMessage.value = null;
        return status;
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      isConnected.value = false;
      errorMessage.value = 'Failed to get status: ${_formatError(e)}';
      debugPrint('FeederApiService: Get status error: $e');
      return null;
    }
  }

  /// Get detection statistics
  Future<FeederStats?> getStats() async {
    if (_baseUrl == null) {
      errorMessage.value = 'No device configured';
      return null;
    }

    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/api/stats'))
          .timeout(kApiTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final feederStats = FeederStats.fromJson(json);
        stats.value = feederStats;
        errorMessage.value = null;
        return feederStats;
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      errorMessage.value = 'Failed to get stats: ${_formatError(e)}';
      debugPrint('FeederApiService: Get stats error: $e');
      return null;
    }
  }

  /// Get known individuals
  Future<List<FeederIndividual>> getIndividuals() async {
    if (_baseUrl == null) {
      errorMessage.value = 'No device configured';
      return [];
    }

    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/api/individuals'))
          .timeout(kApiTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final individualsData = json['individuals'] as List? ?? [];
        final result = individualsData
            .map((e) => FeederIndividual.fromJson(e))
            .toList();
        individuals.value = result;
        errorMessage.value = null;
        return result;
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      errorMessage.value = 'Failed to get individuals: ${_formatError(e)}';
      debugPrint('FeederApiService: Get individuals error: $e');
      return [];
    }
  }

  /// Get recent detections
  Future<List<FeederDetection>> getRecentDetections({
    int limit = 50,
    String? species,
    int? individualId,
  }) async {
    if (_baseUrl == null) {
      errorMessage.value = 'No device configured';
      return [];
    }

    try {
      final params = <String, String>{};
      params['limit'] = limit.toString();
      if (species != null) params['species'] = species;
      if (individualId != null) params['individual_id'] = individualId.toString();

      final uri = Uri.parse('$_baseUrl/api/recent_detections').replace(queryParameters: params);
      final response = await _client.get(uri).timeout(kApiTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final detectionsData = json['detections'] as List? ?? [];
        final result = detectionsData
            .map((e) => FeederDetection.fromJson(e))
            .toList();
        recentDetections.value = result;
        errorMessage.value = null;
        return result;
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      errorMessage.value = 'Failed to get detections: ${_formatError(e)}';
      debugPrint('FeederApiService: Get detections error: $e');
      return [];
    }
  }

  /// Get training status
  Future<TrainingStatus?> getTrainingStatus() async {
    if (_baseUrl == null) {
      errorMessage.value = 'No device configured';
      return null;
    }

    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/api/training/status'))
          .timeout(kApiTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final status = TrainingStatus.fromJson(json);
        trainingStatus.value = status;
        errorMessage.value = null;
        return status;
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      errorMessage.value = 'Failed to get training status: ${_formatError(e)}';
      debugPrint('FeederApiService: Get training status error: $e');
      return null;
    }
  }

  /// Start training manually
  Future<bool> startTraining() async {
    if (_baseUrl == null) {
      errorMessage.value = 'No device configured';
      return false;
    }

    try {
      final response = await _client
          .post(Uri.parse('$_baseUrl/api/training/start'))
          .timeout(kApiTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        errorMessage.value = null;
        // Refresh training status
        await getTrainingStatus();
        return json['success'] == true;
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      errorMessage.value = 'Failed to start training: ${_formatError(e)}';
      debugPrint('FeederApiService: Start training error: $e');
      return false;
    }
  }

  /// Rollback to previous model
  Future<bool> rollbackTraining() async {
    if (_baseUrl == null) {
      errorMessage.value = 'No device configured';
      return false;
    }

    try {
      final response = await _client
          .post(Uri.parse('$_baseUrl/api/training/rollback'))
          .timeout(kApiTimeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        errorMessage.value = null;
        // Refresh training status
        await getTrainingStatus();
        return json['success'] == true;
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      errorMessage.value = 'Failed to rollback: ${_formatError(e)}';
      debugPrint('FeederApiService: Rollback error: $e');
      return false;
    }
  }

  /// Refresh all data
  Future<void> refreshAll() async {
    try {
      await Future.wait([
        getStatus(),
        getStats(),
        getIndividuals(),
        getRecentDetections(),
        getTrainingStatus(),
      ]);
      lastUpdated.value = DateTime.now();
    } catch (e) {
      debugPrint('FeederApiService: Refresh all error: $e');
    }
  }

  /// Start polling for updates
  void startPolling({Duration interval = kPollingInterval}) {
    if (isPolling.value) return;

    isPolling.value = true;
    _pollingTimer = Timer.periodic(interval, (_) async {
      await refreshAll();
    });
    debugPrint('FeederApiService: Polling started (interval: ${interval.inSeconds}s)');
  }

  /// Stop polling
  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    isPolling.value = false;
    debugPrint('FeederApiService: Polling stopped');
  }

  /// Format error message for display
  String _formatError(dynamic error) {
    final message = error.toString();
    if (message.contains('SocketException')) {
      return 'Cannot reach feeder - check network connection';
    }
    if (message.contains('TimeoutException')) {
      return 'Connection timed out';
    }
    if (message.contains('Connection refused')) {
      return 'Feeder is not responding';
    }
    return message.split(':').last.trim();
  }

  /// Clear all state
  void clear() {
    stopPolling();
    _baseUrl = null;
    isConnected.value = false;
    systemStatus.value = null;
    stats.value = null;
    individuals.value = [];
    recentDetections.value = [];
    trainingStatus.value = null;
    errorMessage.value = null;
    lastUpdated.value = null;
  }

  /// Dispose of resources
  void dispose() {
    stopPolling();
    _client.close();
    isConnected.dispose();
    isPolling.dispose();
    systemStatus.dispose();
    stats.dispose();
    individuals.dispose();
    recentDetections.dispose();
    trainingStatus.dispose();
    errorMessage.dispose();
    lastUpdated.dispose();
  }
}

/// Extension for convenient access
extension FeederApiServiceExtensions on FeederApiService {
  /// Get streaming URLs for current device
  String? get mjpegStreamUrl {
    if (_baseUrl == null) return null;
    return '$_baseUrl/video_feed';
  }

  /// Get RTSP URL (requires parsing from status)
  String? get rtspStreamUrl {
    final status = systemStatus.value;
    return status?.streaming?.rtspUrl;
  }

  /// Check if 3D camera is available
  bool get has3DCamera {
    return systemStatus.value?.hardware.depthCameraAvailable ?? false;
  }

  /// Check if Hailo accelerator is available
  bool get hasHailoAccelerator {
    return systemStatus.value?.hardware.hailoAvailable ?? false;
  }

  /// Get current mode string
  String get currentMode {
    return systemStatus.value?.hardware.mode ?? 'Unknown';
  }

  /// Get detection FPS
  double get detectionFps {
    return systemStatus.value?.detection.fps ?? 0.0;
  }

  /// Is detection active
  bool get isDetectionActive {
    return systemStatus.value?.detection.active ?? false;
  }
}
