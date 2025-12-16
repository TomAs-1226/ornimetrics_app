import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/notification_models.dart';
import '../models/weather_models.dart';
import 'notifications_service.dart';

class MaintenanceEngineState {
  final DateTime? lastWeatherTrigger;
  final DateTime? lastUsageTrigger;
  final String? lastWeatherReason;
  final String? lastUsageReason;
  final WeatherSnapshot? lastWeatherSeen;
  final double? lastUsageScore;

  const MaintenanceEngineState({
    this.lastWeatherTrigger,
    this.lastUsageTrigger,
    this.lastWeatherReason,
    this.lastUsageReason,
    this.lastWeatherSeen,
    this.lastUsageScore,
  });

  MaintenanceEngineState copyWith({
    DateTime? lastWeatherTrigger,
    DateTime? lastUsageTrigger,
    String? lastWeatherReason,
    String? lastUsageReason,
    WeatherSnapshot? lastWeatherSeen,
    double? lastUsageScore,
  }) {
    return MaintenanceEngineState(
      lastWeatherTrigger: lastWeatherTrigger ?? this.lastWeatherTrigger,
      lastUsageTrigger: lastUsageTrigger ?? this.lastUsageTrigger,
      lastWeatherReason: lastWeatherReason ?? this.lastWeatherReason,
      lastUsageReason: lastUsageReason ?? this.lastUsageReason,
      lastWeatherSeen: lastWeatherSeen ?? this.lastWeatherSeen,
      lastUsageScore: lastUsageScore ?? this.lastUsageScore,
    );
  }
}

/// Applies weather + usage heuristics to decide when to nudge cleaning.
class MaintenanceRulesEngine {
  MaintenanceRulesEngine._();

  static final MaintenanceRulesEngine instance = MaintenanceRulesEngine._();

  final ValueNotifier<MaintenanceEngineState> state =
      ValueNotifier<MaintenanceEngineState>(const MaintenanceEngineState());

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    DateTime? parseTs(String? raw) {
      if (raw == null) return null;
      try {
        return DateTime.parse(raw);
      } catch (_) {
        return null;
      }
    }

    final lastWeatherTs = parseTs(prefs.getString('maint_last_weather_ts'));
    final lastUsageTs = parseTs(prefs.getString('maint_last_usage_ts'));
    final lastWeatherReason = prefs.getString('maint_last_weather_reason');
    final lastUsageReason = prefs.getString('maint_last_usage_reason');
    state.value = state.value.copyWith(
      lastWeatherTrigger: lastWeatherTs,
      lastUsageTrigger: lastUsageTs,
      lastWeatherReason: lastWeatherReason,
      lastUsageReason: lastUsageReason,
    );
  }

  Future<void> _persist({
    DateTime? lastWeather,
    DateTime? lastUsage,
    String? weatherReason,
    String? usageReason,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (lastWeather != null) {
      await prefs.setString('maint_last_weather_ts', lastWeather.toIso8601String());
    }
    if (lastUsage != null) {
      await prefs.setString('maint_last_usage_ts', lastUsage.toIso8601String());
    }
    if (weatherReason != null) {
      await prefs.setString('maint_last_weather_reason', weatherReason);
    }
    if (usageReason != null) {
      await prefs.setString('maint_last_usage_reason', usageReason);
    }
  }

  Future<void> resetCooldowns() async {
    state.value = const MaintenanceEngineState();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('maint_last_weather_ts');
    await prefs.remove('maint_last_usage_ts');
    await prefs.remove('maint_last_weather_reason');
    await prefs.remove('maint_last_usage_reason');
  }

  bool _cooldownPassed(DateTime? last, double cooldownHours) {
    if (last == null) return true;
    final millis = (cooldownHours * 3600000).round();
    return DateTime.now().difference(last) >= Duration(milliseconds: millis);
  }

  double _usageThreshold(UsageSensitivity sensitivity) {
    switch (sensitivity) {
      case UsageSensitivity.high:
        return 40; // more sensitive → lower threshold
      case UsageSensitivity.medium:
        return 65;
      case UsageSensitivity.low:
        return 90;
    }
  }

  double _humidityThreshold(WeatherSensitivity sensitivity, double base) {
    switch (sensitivity) {
      case WeatherSensitivity.high:
        return (base - 5).clamp(50, 95);
      case WeatherSensitivity.normal:
        return base;
    }
  }

  Future<void> applyWeather(WeatherSnapshot weather, NotificationPreferences prefs) async {
    state.value = state.value.copyWith(lastWeatherSeen: weather);
    if (!prefs.weatherBasedCleaningEnabled) return;

    final humidityLimit = _humidityThreshold(prefs.weatherSensitivity, prefs.humidityThreshold);
    final wetEvent = weather.isWet || (weather.precipitationMm ?? 0) > 0.2;
    final humidEvent = weather.humidity >= humidityLimit;
    if (!wetEvent && !humidEvent) return;

    if (!_cooldownPassed(state.value.lastWeatherTrigger, prefs.weatherCooldownHours)) return;

    final reason = wetEvent
        ? 'Wet weather detected → reduce mold/bacteria risk'
        : 'Humidity ${weather.humidity.toStringAsFixed(0)}% ≥ $humidityLimit%';

    NotificationsService.instance.triggerWeatherCleaning(reason: reason, snapshot: weather);
    final now = DateTime.now();
    state.value = state.value.copyWith(lastWeatherTrigger: now, lastWeatherReason: reason);
    await _persist(lastWeather: now, weatherReason: reason);
  }

  Future<void> applyUsage({
    required int dispenseEvents,
    required Duration activeDuration,
    required NotificationPreferences prefs,
  }) async {
    if (!prefs.heavyUseEnabled) return;

    final score = dispenseEvents + activeDuration.inMinutes * 2;
    final threshold = _usageThreshold(prefs.heavyUseSensitivity);
    state.value = state.value.copyWith(lastUsageScore: score.toDouble());
    if (score < threshold) return;

    if (!_cooldownPassed(state.value.lastUsageTrigger, prefs.heavyUseCooldownHours)) return;

    final reason =
        'High feeder activity detected (score ${score.toStringAsFixed(0)} ≥ ${threshold.toStringAsFixed(0)})';
    NotificationsService.instance.triggerHeavyUse(reason: reason);
    final now = DateTime.now();
    state.value = state.value.copyWith(lastUsageTrigger: now, lastUsageReason: reason);
    await _persist(lastUsage: now, usageReason: reason);
  }

  Future<void> simulateWeatherEvent({
    required String label,
    required NotificationPreferences prefs,
  }) async {
    final mock = WeatherSnapshot(
      condition: label,
      temperatureC: 13,
      humidity: 92,
      precipitationChance: 0.8,
      windKph: 10,
      pressureMb: 1004,
      uvIndex: 0.2,
      visibilityKm: 2,
      dewPointC: 11,
      fetchedAt: DateTime.now(),
      isRaining: label.toLowerCase().contains('rain'),
      isSnowing: label.toLowerCase().contains('snow'),
      isHailing: label.toLowerCase().contains('hail'),
    );
    await applyWeather(mock, prefs);
  }

  Future<void> simulateHeavyUse(NotificationPreferences prefs) async {
    await applyUsage(
      dispenseEvents: 120,
      activeDuration: const Duration(minutes: 35),
      prefs: prefs,
    );
  }
}
