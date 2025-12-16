import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/notification_models.dart';

/// Local-first notification service with a simple event stream.
/// This keeps storage in shared_preferences and is structured so that
/// a push backend can be swapped in later.
class NotificationsService {
  NotificationsService._();

  static final NotificationsService instance = NotificationsService._();

  final ValueNotifier<NotificationPreferences> preferences =
      ValueNotifier<NotificationPreferences>(NotificationPreferences());
  final ValueNotifier<List<NotificationEvent>> events =
      ValueNotifier<List<NotificationEvent>>(<NotificationEvent>[]);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final interval = prefs.getInt('pref_cleaning_interval') ?? 7;
    final lastRaw = prefs.getString('pref_last_cleaned');
    DateTime? last;
    if (lastRaw != null) {
      try {
        last = DateTime.parse(lastRaw);
      } catch (_) {}
    }
    preferences.value = NotificationPreferences(
      lowFoodEnabled: prefs.getBool('pref_low_food') ?? true,
      cloggedEnabled: prefs.getBool('pref_clogged') ?? true,
      cleaningReminderEnabled: prefs.getBool('pref_cleaning') ?? true,
      cleaningIntervalDays: interval,
      lastCleaned: last,
    );
  }

  Future<void> updatePrefs(NotificationPreferences next) async {
    preferences.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pref_low_food', next.lowFoodEnabled);
    await prefs.setBool('pref_clogged', next.cloggedEnabled);
    await prefs.setBool('pref_cleaning', next.cleaningReminderEnabled);
    await prefs.setInt('pref_cleaning_interval', next.cleaningIntervalDays);
    if (next.lastCleaned != null) {
      await prefs.setString('pref_last_cleaned', next.lastCleaned!.toIso8601String());
    }
  }

  Future<void> markCleaned() async {
    final now = DateTime.now();
    final current = preferences.value.copyWith(lastCleaned: now);
    await updatePrefs(current);
  }

  void _emit(NotificationType type, String message) {
    final updated = List<NotificationEvent>.from(events.value)
      ..insert(0, NotificationEvent(type: type, message: message, timestamp: DateTime.now()));
    events.value = updated.take(25).toList();
  }

  /// Simulate a "low food" notification; real sensor hooks can call this later.
  void simulateLowFood() {
    if (preferences.value.lowFoodEnabled) {
      _emit(NotificationType.lowFood, 'Feeder food level is low. Time to refill!');
    }
  }

  /// Simulate a clog notification.
  void simulateClogged() {
    if (preferences.value.cloggedEnabled) {
      _emit(NotificationType.clogged, 'Possible feeder clog detected. Inspect the chute.');
    }
  }

  /// Trigger a cleaning reminder based on configured interval.
  void triggerCleaningCheck() {
    if (!preferences.value.cleaningReminderEnabled) return;
    final last = preferences.value.lastCleaned;
    final interval = preferences.value.cleaningIntervalDays;
    final daysSince = last == null ? interval + 1 : DateTime.now().difference(last).inDays;
    if (daysSince >= interval) {
      _emit(NotificationType.cleaningDue, 'Cleaning due. It\'s been $daysSince day(s) since last cleaning.');
    }
  }
}
