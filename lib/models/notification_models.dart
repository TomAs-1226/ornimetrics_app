import 'package:flutter/foundation.dart';

enum NotificationType { lowFood, clogged, cleaningDue, heavyUse, weatherBased, foodLevel }

enum UsageSensitivity { low, medium, high }

enum WeatherSensitivity { normal, high }

class NotificationEvent {
  final NotificationType type;
  final String message;
  final DateTime timestamp;
  final Map<String, dynamic>? meta;

  NotificationEvent({required this.type, required this.message, required this.timestamp, this.meta});
}

class NotificationPreferences with ChangeNotifier {
  bool lowFoodEnabled;
  bool cloggedEnabled;
  bool cleaningReminderEnabled;
  int cleaningIntervalDays;
  DateTime? lastCleaned;
  bool weatherBasedCleaningEnabled;
  WeatherSensitivity weatherSensitivity;
  double humidityThreshold;
  bool heavyUseEnabled;
  UsageSensitivity heavyUseSensitivity;
  double lowFoodThresholdPercent;
  bool progressNotificationsEnabled;
  double heavyUseCooldownHours;
  double weatherCooldownHours;

  NotificationPreferences({
    this.lowFoodEnabled = true,
    this.cloggedEnabled = true,
    this.cleaningReminderEnabled = true,
    this.cleaningIntervalDays = 7,
    this.lastCleaned,
    this.weatherBasedCleaningEnabled = true,
    this.weatherSensitivity = WeatherSensitivity.normal,
    this.humidityThreshold = 78,
    this.heavyUseEnabled = true,
    this.heavyUseSensitivity = UsageSensitivity.medium,
    this.lowFoodThresholdPercent = 20,
    this.progressNotificationsEnabled = true,
    this.heavyUseCooldownHours = 12,
    this.weatherCooldownHours = 12,
  });

  NotificationPreferences copyWith({
    bool? lowFoodEnabled,
    bool? cloggedEnabled,
    bool? cleaningReminderEnabled,
    int? cleaningIntervalDays,
    DateTime? lastCleaned,
    bool? weatherBasedCleaningEnabled,
    WeatherSensitivity? weatherSensitivity,
    double? humidityThreshold,
    bool? heavyUseEnabled,
    UsageSensitivity? heavyUseSensitivity,
    double? lowFoodThresholdPercent,
    bool? progressNotificationsEnabled,
    double? heavyUseCooldownHours,
    double? weatherCooldownHours,
  }) {
    return NotificationPreferences(
      lowFoodEnabled: lowFoodEnabled ?? this.lowFoodEnabled,
      cloggedEnabled: cloggedEnabled ?? this.cloggedEnabled,
      cleaningReminderEnabled: cleaningReminderEnabled ?? this.cleaningReminderEnabled,
      cleaningIntervalDays: cleaningIntervalDays ?? this.cleaningIntervalDays,
      lastCleaned: lastCleaned ?? this.lastCleaned,
      weatherBasedCleaningEnabled: weatherBasedCleaningEnabled ?? this.weatherBasedCleaningEnabled,
      weatherSensitivity: weatherSensitivity ?? this.weatherSensitivity,
      humidityThreshold: humidityThreshold ?? this.humidityThreshold,
      heavyUseEnabled: heavyUseEnabled ?? this.heavyUseEnabled,
      heavyUseSensitivity: heavyUseSensitivity ?? this.heavyUseSensitivity,
      lowFoodThresholdPercent: lowFoodThresholdPercent ?? this.lowFoodThresholdPercent,
      progressNotificationsEnabled: progressNotificationsEnabled ?? this.progressNotificationsEnabled,
      heavyUseCooldownHours: heavyUseCooldownHours ?? this.heavyUseCooldownHours,
      weatherCooldownHours: weatherCooldownHours ?? this.weatherCooldownHours,
    );
  }
}
