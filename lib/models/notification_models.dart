import 'package:flutter/foundation.dart';

enum NotificationType { lowFood, clogged, cleaningDue }

class NotificationEvent {
  final NotificationType type;
  final String message;
  final DateTime timestamp;

  NotificationEvent({required this.type, required this.message, required this.timestamp});
}

class NotificationPreferences with ChangeNotifier {
  bool lowFoodEnabled;
  bool cloggedEnabled;
  bool cleaningReminderEnabled;
  int cleaningIntervalDays;
  DateTime? lastCleaned;

  NotificationPreferences({
    this.lowFoodEnabled = true,
    this.cloggedEnabled = true,
    this.cleaningReminderEnabled = true,
    this.cleaningIntervalDays = 7,
    this.lastCleaned,
  });

  NotificationPreferences copyWith({
    bool? lowFoodEnabled,
    bool? cloggedEnabled,
    bool? cleaningReminderEnabled,
    int? cleaningIntervalDays,
    DateTime? lastCleaned,
  }) {
    return NotificationPreferences(
      lowFoodEnabled: lowFoodEnabled ?? this.lowFoodEnabled,
      cloggedEnabled: cloggedEnabled ?? this.cloggedEnabled,
      cleaningReminderEnabled: cleaningReminderEnabled ?? this.cleaningReminderEnabled,
      cleaningIntervalDays: cleaningIntervalDays ?? this.cleaningIntervalDays,
      lastCleaned: lastCleaned ?? this.lastCleaned,
    );
  }
}
