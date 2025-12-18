import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  final ValueNotifier<Position?> position = ValueNotifier<Position?>(null);
  final ValueNotifier<LocationPermission> permission = ValueNotifier<LocationPermission>(LocationPermission.denied);

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

    if (status == LocationPermission.denied || status == LocationPermission.deniedForever) {
      return;
    }

    Position? pos;

    // Quick win: try cached location first.
    pos = await Geolocator.getLastKnownPosition();

    // If no cached reading, fetch a fresh, time-limited reading to avoid ANRs.
    pos ??= await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 8),
    );

    position.value = pos;
  }

  Future<Position?> currentPosition({bool forceUpdate = false}) async {
    if (!forceUpdate && position.value != null) return position.value;

    await ensureReady();
    return position.value;
  }
}
