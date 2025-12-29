import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  final ValueNotifier<Position?> position = ValueNotifier<Position?>(null);
  final ValueNotifier<LocationPermission> permission =
      ValueNotifier<LocationPermission>(LocationPermission.denied);
  final ValueNotifier<bool> isTracking = ValueNotifier<bool>(false);

  StreamSubscription<Position>? _positionStream;
  DateTime? _lastUpdate;

  /// Minimum interval between position updates (to avoid excessive updates)
  static const Duration _minUpdateInterval = Duration(seconds: 2);

  Future<void> ensureReady() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      permission.value = LocationPermission.deniedForever;
      return;
    }

    var status = await Geolocator.checkPermission();
    if (status == LocationPermission.denied) {
      status = await Geolocator.requestPermission();
    }

    permission.value = status;

    if (status == LocationPermission.denied ||
        status == LocationPermission.deniedForever) {
      return;
    }

    // Quick win: get cached location immediately for fast UI update
    final cachedPos = await Geolocator.getLastKnownPosition();
    if (cachedPos != null) {
      position.value = cachedPos;
    }

    // Get fresh position with lower accuracy first for speed
    try {
      final quickPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 3),
      );
      position.value = quickPos;
    } catch (_) {
      // Fall back to high accuracy if medium fails
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 8),
        );
        position.value = pos;
      } catch (_) {
        // Keep cached position if available
      }
    }
  }

  /// Start continuous location tracking for live updates
  Future<void> startTracking({
    LocationAccuracy accuracy = LocationAccuracy.high,
    int distanceFilter = 10,
  }) async {
    if (_positionStream != null) return; // Already tracking

    await ensureReady();

    if (permission.value == LocationPermission.denied ||
        permission.value == LocationPermission.deniedForever) {
      return;
    }

    isTracking.value = true;

    final locationSettings = AppleSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
      activityType: ActivityType.fitness,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
    );

    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (pos) {
        final now = DateTime.now();
        if (_lastUpdate == null ||
            now.difference(_lastUpdate!) >= _minUpdateInterval) {
          position.value = pos;
          _lastUpdate = now;
        }
      },
      onError: (e) {
        debugPrint('Location stream error: $e');
      },
    );
  }

  /// Stop continuous location tracking
  void stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    isTracking.value = false;
  }

  Future<Position?> currentPosition({bool forceUpdate = false}) async {
    if (!forceUpdate && position.value != null) return position.value;

    await ensureReady();
    return position.value;
  }

  /// Get a quick position update (uses cached if recent, else fetches new)
  Future<Position?> getQuickPosition() async {
    // If we have a recent position (within 30 seconds), use it
    if (position.value != null) {
      final age = DateTime.now().difference(position.value!.timestamp);
      if (age.inSeconds < 30) {
        return position.value;
      }
    }

    // Try cached first
    final cached = await Geolocator.getLastKnownPosition();
    if (cached != null) {
      position.value = cached;
      return cached;
    }

    // Quick fetch with timeout
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 3),
      );
      position.value = pos;
      return pos;
    } catch (_) {
      return position.value;
    }
  }

  void dispose() {
    stopTracking();
    position.dispose();
    permission.dispose();
    isTracking.dispose();
  }
}
