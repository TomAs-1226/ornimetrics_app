/// Firebase service for Ornimetrics OS cloud data synchronization
/// Handles real-time listeners for detections, individuals, and statistics

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/feeder_models.dart';

class FeederFirebaseService {
  static final FeederFirebaseService instance = FeederFirebaseService._();
  FeederFirebaseService._();

  // State notifiers
  final ValueNotifier<bool> isListening = ValueNotifier(false);
  final ValueNotifier<List<FirebaseDetection>> detections = ValueNotifier([]);
  final ValueNotifier<List<FirebaseIndividual>> individuals = ValueNotifier([]);
  final ValueNotifier<FirebaseDailyStats?> todayStats = ValueNotifier(null);
  final ValueNotifier<List<FirebaseDailyStats>> weeklyStats = ValueNotifier([]);
  final ValueNotifier<String?> errorMessage = ValueNotifier(null);
  final ValueNotifier<DateTime?> lastSync = ValueNotifier(null);

  // Subscription management
  StreamSubscription<QuerySnapshot>? _detectionsSubscription;
  StreamSubscription<QuerySnapshot>? _individualsSubscription;
  StreamSubscription<DocumentSnapshot>? _todayStatsSubscription;

  // Current configuration
  String? _userId;
  String? _deviceId;

  /// Get Firestore instance
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  /// Get current user ID
  String? get currentUserId => FirebaseAuth.instance.currentUser?.uid;

  /// Initialize service with device
  void initialize({required String userId, required String deviceId}) {
    _userId = userId;
    _deviceId = deviceId;
    debugPrint('FeederFirebaseService: Initialized for user=$userId, device=$deviceId');
  }

  /// Get base path for feeder data
  String get _basePath {
    if (_userId == null || _deviceId == null) {
      throw Exception('Service not initialized');
    }
    return 'users/$_userId/feeders/$_deviceId';
  }

  /// Start listening to all collections
  Future<void> startListening() async {
    if (_userId == null || _deviceId == null) {
      errorMessage.value = 'Service not initialized';
      return;
    }

    try {
      errorMessage.value = null;
      isListening.value = true;

      await Future.wait([
        _listenToDetections(),
        _listenToIndividuals(),
        _listenToTodayStats(),
      ]);

      lastSync.value = DateTime.now();
    } catch (e) {
      errorMessage.value = 'Failed to start listening: ${e.toString()}';
      debugPrint('FeederFirebaseService: Start listening error: $e');
    }
  }

  /// Stop all listeners
  void stopListening() {
    _detectionsSubscription?.cancel();
    _detectionsSubscription = null;

    _individualsSubscription?.cancel();
    _individualsSubscription = null;

    _todayStatsSubscription?.cancel();
    _todayStatsSubscription = null;

    isListening.value = false;
  }

  /// Listen to detections collection
  Future<void> _listenToDetections() async {
    final detectionsRef = _firestore
        .collection('$_basePath/detections')
        .orderBy('timestamp', descending: true)
        .limit(100);

    _detectionsSubscription = detectionsRef.snapshots().listen(
      (snapshot) {
        final list = snapshot.docs.map((doc) {
          return FirebaseDetection.fromJson(doc.id, doc.data());
        }).toList();
        detections.value = list;
        lastSync.value = DateTime.now();
      },
      onError: (error) {
        debugPrint('FeederFirebaseService: Detections listener error: $error');
        errorMessage.value = 'Detection sync error';
      },
    );
  }

  /// Listen to individuals collection
  Future<void> _listenToIndividuals() async {
    final individualsRef = _firestore
        .collection('$_basePath/individuals')
        .orderBy('last_seen', descending: true);

    _individualsSubscription = individualsRef.snapshots().listen(
      (snapshot) {
        final list = snapshot.docs.map((doc) {
          return FirebaseIndividual.fromJson(doc.id, doc.data());
        }).toList();
        individuals.value = list;
      },
      onError: (error) {
        debugPrint('FeederFirebaseService: Individuals listener error: $error');
      },
    );
  }

  /// Listen to today's statistics
  Future<void> _listenToTodayStats() async {
    final today = _formatDate(DateTime.now());
    final todayRef = _firestore.doc('$_basePath/statistics/daily/$today');

    _todayStatsSubscription = todayRef.snapshots().listen(
      (snapshot) {
        if (snapshot.exists && snapshot.data() != null) {
          todayStats.value = FirebaseDailyStats.fromJson(
            snapshot.id,
            snapshot.data()!,
          );
        } else {
          todayStats.value = null;
        }
      },
      onError: (error) {
        debugPrint('FeederFirebaseService: Today stats listener error: $error');
      },
    );
  }

  /// Fetch weekly statistics
  Future<List<FirebaseDailyStats>> fetchWeeklyStats() async {
    if (_userId == null || _deviceId == null) {
      errorMessage.value = 'Service not initialized';
      return [];
    }

    try {
      final now = DateTime.now();
      final weekAgo = now.subtract(const Duration(days: 7));
      final startDate = _formatDate(weekAgo);

      final statsRef = _firestore
          .collection('$_basePath/statistics/daily')
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: startDate)
          .orderBy(FieldPath.documentId, descending: true);

      final snapshot = await statsRef.get();
      final list = snapshot.docs.map((doc) {
        return FirebaseDailyStats.fromJson(doc.id, doc.data());
      }).toList();

      weeklyStats.value = list;
      return list;
    } catch (e) {
      errorMessage.value = 'Failed to fetch weekly stats';
      debugPrint('FeederFirebaseService: Weekly stats error: $e');
      return [];
    }
  }

  /// Fetch detections for a specific species
  Future<List<FirebaseDetection>> fetchDetectionsBySpecies(String species) async {
    if (_userId == null || _deviceId == null) {
      return [];
    }

    try {
      final detectionsRef = _firestore
          .collection('$_basePath/detections')
          .where('species', isEqualTo: species)
          .orderBy('timestamp', descending: true)
          .limit(50);

      final snapshot = await detectionsRef.get();
      return snapshot.docs.map((doc) {
        return FirebaseDetection.fromJson(doc.id, doc.data());
      }).toList();
    } catch (e) {
      debugPrint('FeederFirebaseService: Fetch by species error: $e');
      return [];
    }
  }

  /// Fetch detections for a specific individual
  Future<List<FirebaseDetection>> fetchDetectionsByIndividual(int individualId) async {
    if (_userId == null || _deviceId == null) {
      return [];
    }

    try {
      final detectionsRef = _firestore
          .collection('$_basePath/detections')
          .where('individual_id', isEqualTo: individualId)
          .orderBy('timestamp', descending: true)
          .limit(50);

      final snapshot = await detectionsRef.get();
      return snapshot.docs.map((doc) {
        return FirebaseDetection.fromJson(doc.id, doc.data());
      }).toList();
    } catch (e) {
      debugPrint('FeederFirebaseService: Fetch by individual error: $e');
      return [];
    }
  }

  /// Get individual by ID
  Future<FirebaseIndividual?> getIndividual(int id) async {
    if (_userId == null || _deviceId == null) {
      return null;
    }

    try {
      final query = _firestore
          .collection('$_basePath/individuals')
          .where('id', isEqualTo: id)
          .limit(1);

      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) return null;

      final doc = snapshot.docs.first;
      return FirebaseIndividual.fromJson(doc.id, doc.data());
    } catch (e) {
      debugPrint('FeederFirebaseService: Get individual error: $e');
      return null;
    }
  }

  /// Get statistics for date range
  Future<List<FirebaseDailyStats>> fetchStatsForRange(DateTime start, DateTime end) async {
    if (_userId == null || _deviceId == null) {
      return [];
    }

    try {
      final startDate = _formatDate(start);
      final endDate = _formatDate(end);

      final statsRef = _firestore
          .collection('$_basePath/statistics/daily')
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: startDate)
          .where(FieldPath.documentId, isLessThanOrEqualTo: endDate)
          .orderBy(FieldPath.documentId);

      final snapshot = await statsRef.get();
      return snapshot.docs.map((doc) {
        return FirebaseDailyStats.fromJson(doc.id, doc.data());
      }).toList();
    } catch (e) {
      debugPrint('FeederFirebaseService: Fetch stats range error: $e');
      return [];
    }
  }

  /// Get aggregate statistics
  Future<Map<String, int>> getAggregateSpeciesCounts() async {
    final stats = await fetchWeeklyStats();
    final counts = <String, int>{};

    for (final stat in stats) {
      stat.speciesBreakdown.forEach((species, count) {
        counts[species] = (counts[species] ?? 0) + count;
      });
    }

    return counts;
  }

  /// Check if data exists for the current device
  Future<bool> hasData() async {
    if (_userId == null || _deviceId == null) {
      return false;
    }

    try {
      final detectionsRef = _firestore
          .collection('$_basePath/detections')
          .limit(1);

      final snapshot = await detectionsRef.get();
      return snapshot.docs.isNotEmpty;
    } catch (e) {
      debugPrint('FeederFirebaseService: Check data error: $e');
      return false;
    }
  }

  /// Format date as YYYY-MM-DD
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Clear all state and stop listening
  void clear() {
    stopListening();
    _userId = null;
    _deviceId = null;
    detections.value = [];
    individuals.value = [];
    todayStats.value = null;
    weeklyStats.value = [];
    errorMessage.value = null;
    lastSync.value = null;
  }

  /// Dispose of resources
  void dispose() {
    clear();
    isListening.dispose();
    detections.dispose();
    individuals.dispose();
    todayStats.dispose();
    weeklyStats.dispose();
    errorMessage.dispose();
    lastSync.dispose();
  }
}

/// Extension for convenient computed properties
extension FeederFirebaseServiceExtensions on FeederFirebaseService {
  /// Get total detections today
  int get totalDetectionsToday => todayStats.value?.totalDetections ?? 0;

  /// Get unique individuals today
  int get uniqueIndividualsToday => todayStats.value?.uniqueIndividuals ?? 0;

  /// Get total known individuals
  int get totalKnownIndividuals => individuals.value.length;

  /// Get total species detected
  int get totalSpecies {
    final species = <String>{};
    for (final detection in detections.value) {
      species.add(detection.species);
    }
    return species.length;
  }

  /// Get most active species
  String? get mostActiveSpecies {
    final counts = <String, int>{};
    for (final detection in detections.value) {
      counts[detection.species] = (counts[detection.species] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;

    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  /// Get recent species list
  List<String> get recentSpecies {
    final species = <String>[];
    final seen = <String>{};
    for (final detection in detections.value) {
      if (!seen.contains(detection.species)) {
        seen.add(detection.species);
        species.add(detection.species);
        if (species.length >= 5) break;
      }
    }
    return species;
  }
}
