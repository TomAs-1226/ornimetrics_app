import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/notification_models.dart';
import '../models/weather_models.dart';
import 'food_level_provider.dart';

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
  final ValueNotifier<FoodLevelReading?> foodLevel = ValueNotifier<FoodLevelReading?>(null);
  final ValueNotifier<bool> permissionsPrompted = ValueNotifier<bool>(false);

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _pluginReady = false;
  StreamSubscription<FoodLevelReading>? _foodSub;
  FoodLevelProvider? _foodProvider;
  bool _sentLowFoodAlert = false;
  double _lastProgress = 100;

  static const int _foodNotificationId = 4444;
  static const int _alertNotificationId = 4445;

  Future<void> load() async {
    await _ensurePlugin();
    final prefs = await SharedPreferences.getInstance();
    permissionsPrompted.value = prefs.getBool('pref_notifications_prompted') ?? false;
    final interval = prefs.getInt('pref_cleaning_interval') ?? 7;
    final weatherSensIdx = prefs.getInt('pref_weather_sensitivity') ?? 0;
    final usageSensIdx = prefs.getInt('pref_usage_sensitivity') ?? 1;
    final weatherCool = prefs.getDouble('pref_weather_cooldown_hours') ?? 12;
    final usageCool = prefs.getDouble('pref_usage_cooldown_hours') ?? 12;
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
      weatherBasedCleaningEnabled: prefs.getBool('pref_weather_cleaning') ?? true,
      weatherSensitivity: WeatherSensitivity
          .values[weatherSensIdx.clamp(0, WeatherSensitivity.values.length - 1).toInt()],
      humidityThreshold: prefs.getDouble('pref_humidity_threshold') ?? 78,
      heavyUseEnabled: prefs.getBool('pref_heavy_use') ?? true,
      heavyUseSensitivity:
          UsageSensitivity.values[usageSensIdx.clamp(0, UsageSensitivity.values.length - 1).toInt()],
      lowFoodThresholdPercent: prefs.getDouble('pref_low_food_threshold') ?? 20,
      progressNotificationsEnabled: prefs.getBool('pref_progress_notifications') ?? true,
      heavyUseCooldownHours: usageCool,
      weatherCooldownHours: weatherCool,
    );
  }

  Future<void> updatePrefs(NotificationPreferences next) async {
    preferences.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pref_low_food', next.lowFoodEnabled);
    await prefs.setBool('pref_clogged', next.cloggedEnabled);
    await prefs.setBool('pref_cleaning', next.cleaningReminderEnabled);
    await prefs.setInt('pref_cleaning_interval', next.cleaningIntervalDays);
    await prefs.setBool('pref_weather_cleaning', next.weatherBasedCleaningEnabled);
    await prefs.setInt('pref_weather_sensitivity', next.weatherSensitivity.index);
    await prefs.setDouble('pref_humidity_threshold', next.humidityThreshold);
    await prefs.setBool('pref_heavy_use', next.heavyUseEnabled);
    await prefs.setInt('pref_usage_sensitivity', next.heavyUseSensitivity.index);
    await prefs.setDouble('pref_low_food_threshold', next.lowFoodThresholdPercent);
    await prefs.setBool('pref_progress_notifications', next.progressNotificationsEnabled);
    await prefs.setDouble('pref_usage_cooldown_hours', next.heavyUseCooldownHours);
    await prefs.setDouble('pref_weather_cooldown_hours', next.weatherCooldownHours);
    if (next.lastCleaned != null) {
      await prefs.setString('pref_last_cleaned', next.lastCleaned!.toIso8601String());
    }
  }

  Future<void> markCleaned() async {
    final now = DateTime.now();
    final current = preferences.value.copyWith(lastCleaned: now);
    await updatePrefs(current);
  }

  void _emit(NotificationType type, String message, {Map<String, dynamic>? meta}) {
    final updated = List<NotificationEvent>.from(events.value)
      ..insert(0, NotificationEvent(type: type, message: message, timestamp: DateTime.now(), meta: meta));
    events.value = updated.take(25).toList();
    _showAlertNotification(type, message);
  }

  Future<void> _ensurePlugin() async {
    if (_pluginReady || kIsWeb) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    final initialized = await _plugin.initialize(const InitializationSettings(android: androidInit, iOS: iosInit));
    _pluginReady = initialized ?? false;
  }

  /// Prompt the user for notification permissions (Android 13+/iOS) so alerts and
  /// foreground progress bars can render. Safe to call multiple times.
  Future<void> requestPermissions() async {
    await _ensurePlugin();
    if (!_pluginReady) return;

    if (Platform.isAndroid) {
      final androidPlugin =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      // Android 13+ requires an explicit notifications permission grant.
      await androidPlugin?.requestNotificationsPermission();
      await androidPlugin?.requestExactAlarmsPermission();
    } else if (Platform.isIOS || Platform.isMacOS) {
      final iosPlugin =
          _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      await iosPlugin?.requestPermissions(alert: true, badge: true, sound: true);
    }
    final prefs = await SharedPreferences.getInstance();
    permissionsPrompted.value = true;
    await prefs.setBool('pref_notifications_prompted', true);
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

  void triggerWeatherCleaning({required String reason, WeatherSnapshot? snapshot}) {
    if (!preferences.value.weatherBasedCleaningEnabled) return;
    _emit(NotificationType.weatherBased, reason, meta: {
      'snapshot': snapshot,
    });
  }

  void triggerHeavyUse({required String reason}) {
    if (!preferences.value.heavyUseEnabled) return;
    _emit(NotificationType.heavyUse, reason);
  }

  Future<void> startFoodLevelTracking(FoodLevelProvider provider) async {
    await _foodSub?.cancel();
    await _foodProvider?.dispose();
    _foodProvider = provider;
    _foodSub = provider.watchLevels().listen(_handleFoodLevel);
  }

  Future<void> stopFoodLevelTracking() async {
    await _foodSub?.cancel();
    await _foodProvider?.dispose();
    _foodProvider = null;
  }

  void _handleFoodLevel(FoodLevelReading reading) {
    foodLevel.value = reading;
    _lastProgress = reading.percentFull;
    if (preferences.value.progressNotificationsEnabled) {
      _showProgressNotification(reading.percentFull);
    }

    if (preferences.value.lowFoodEnabled && reading.percentFull <= preferences.value.lowFoodThresholdPercent) {
      if (!_sentLowFoodAlert) {
        _emit(
          NotificationType.lowFood,
          'Food level at ${reading.percentFull.toStringAsFixed(0)}%. Time to refill.',
          meta: {'percent': reading.percentFull},
        );
        _sentLowFoodAlert = true;
      }
    } else {
      _sentLowFoodAlert = false;
    }
  }

  Future<void> _showProgressNotification(double percent) async {
    await _ensurePlugin();
    if (!_pluginReady) return;

    final pct = percent.clamp(0, 100).round();
    if (!Platform.isAndroid) {
      // iOS/web fallback: simple status update.
      await _plugin.show(
        _foodNotificationId,
        'Feeder food level',
        'Food level: $pct%',
        const NotificationDetails(
          iOS: DarwinNotificationDetails(),
        ),
      );
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      'food_level_channel',
      'Food level',
      channelDescription: 'Shows feeder food level progress.',
      importance: Importance.low,
      priority: Priority.low,
      showProgress: true,
      maxProgress: 100,
      progress: pct,
      ongoing: pct > preferences.value.lowFoodThresholdPercent,
      onlyAlertOnce: true,
      enableVibration: false,
      category: AndroidNotificationCategory.status,
    );
    await _plugin.show(
      _foodNotificationId,
      'Feeder food',
      pct <= preferences.value.lowFoodThresholdPercent ? 'Feeding reminder' : 'Food remaining',
      NotificationDetails(android: androidDetails),
    );
  }

  Future<void> _showAlertNotification(NotificationType type, String message) async {
    await _ensurePlugin();
    if (!_pluginReady) return;
    final title = () {
      switch (type) {
        case NotificationType.lowFood:
          return 'Low food alert';
        case NotificationType.clogged:
          return 'Clog risk';
        case NotificationType.cleaningDue:
          return 'Cleaning reminder';
        case NotificationType.heavyUse:
          return 'Heavy use detected';
        case NotificationType.weatherBased:
          return 'Weather-based cleaning';
        case NotificationType.foodLevel:
          return 'Food level update';
      }
    }();

    final android = AndroidNotificationDetails(
      'feeder_alerts',
      'Feeder alerts',
      channelDescription: 'Feeder status and maintenance alerts',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: const BigTextStyleInformation(''),
    );
    final details = NotificationDetails(
      android: android,
      iOS: const DarwinNotificationDetails(),
    );
    await _plugin.show(_alertNotificationId, title, message, details);
  }
}
