import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/notification_models.dart';
import '../services/food_level_provider.dart';
import '../services/maintenance_rules_engine.dart';
import '../services/notifications_service.dart';

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() => _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  final _service = NotificationsService.instance;
  final _engine = MaintenanceRulesEngine.instance;

  @override
  void initState() {
    super.initState();
    _service.load();
    _engine.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Feeder Notifications')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ValueListenableBuilder<NotificationPreferences>(
            valueListenable: _service.preferences,
            builder: (_, prefs, __) {
              return Column(
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Alerts', style: TextStyle(fontWeight: FontWeight.bold)),
                          SwitchListTile(
                            title: const Text('Low/empty food'),
                            subtitle: Text('Notify when under ${prefs.lowFoodThresholdPercent.toStringAsFixed(0)}%'),
                            value: prefs.lowFoodEnabled,
                            onChanged: (val) => _service.updatePrefs(prefs.copyWith(lowFoodEnabled: val)),
                          ),
                          Slider(
                            value: prefs.lowFoodThresholdPercent,
                            min: 5,
                            max: 60,
                            divisions: 11,
                            label: '${prefs.lowFoodThresholdPercent.toStringAsFixed(0)}%',
                            onChanged: (v) => _service
                                .updatePrefs(prefs.copyWith(lowFoodThresholdPercent: v)),
                          ),
                          SwitchListTile(
                            title: const Text('Clogged feeder alerts'),
                            value: prefs.cloggedEnabled,
                            onChanged: (val) => _service.updatePrefs(prefs.copyWith(cloggedEnabled: val)),
                          ),
                          SwitchListTile(
                            title: const Text('Cleaning reminders'),
                            subtitle: Text('Every ${prefs.cleaningIntervalDays} day(s)'),
                            value: prefs.cleaningReminderEnabled,
                            onChanged: (val) => _service.updatePrefs(prefs.copyWith(cleaningReminderEnabled: val)),
                          ),
                          if (prefs.cleaningReminderEnabled)
                            Slider(
                              value: prefs.cleaningIntervalDays.toDouble(),
                              min: 3,
                              max: 60,
                              divisions: 19,
                              label: '${prefs.cleaningIntervalDays} days',
                              onChanged: (v) => _service.updatePrefs(prefs.copyWith(cleaningIntervalDays: v.round())),
                            ),
                          SwitchListTile(
                            title: const Text('Show progress notifications'),
                            subtitle: const Text('Android: ongoing bar; iOS: periodic updates'),
                            value: prefs.progressNotificationsEnabled,
                            onChanged: (val) =>
                                _service.updatePrefs(prefs.copyWith(progressNotificationsEnabled: val)),
                          ),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final label = Text(
                                  prefs.lastCleaned == null
                                      ? 'Last cleaned: not recorded'
                                      : 'Last cleaned: ${DateFormat('yMMMd').format(prefs.lastCleaned!)}',
                                  softWrap: true,
                                );

                                final button = ElevatedButton(
                                  onPressed: () async {
                                    await _service.markCleaned();
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Marked cleaned today')),
                                      );
                                    }
                                  },
                                  child: const Text('Mark cleaned today'),
                                );

                                if (constraints.maxWidth < 420) {
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      label,
                                      const SizedBox(height: 8),
                                      Align(alignment: Alignment.centerLeft, child: button),
                                    ],
                                  );
                                }

                                return Row(
                                  children: [
                                    Expanded(child: label),
                                    button,
                                  ],
                                );
                              },
                            )
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _maintenanceCard(prefs),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _foodLevelCard(),
          const SizedBox(height: 12),
          const Text('Recent notification events', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ValueListenableBuilder<List<NotificationEvent>>(
            valueListenable: _service.events,
            builder: (_, items, __) {
              if (items.isEmpty) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('No notifications yet. Connect your feeder to start receiving production alerts.'),
                  ),
                );
              }
              return Column(
                children: [
                  for (final e in items)
                    Card(
                      child: ListTile(
                        leading: Icon(_iconForType(e.type)),
                        title: Text(e.message),
                        subtitle: Text(DateFormat('MMM d, h:mm a').format(e.timestamp)),
                      ),
                    )
                ],
              );
            },
          )
        ],
      ),
    );
  }

  Widget _maintenanceCard(NotificationPreferences prefs) {
    return ValueListenableBuilder<MaintenanceEngineState>(
      valueListenable: _engine.state,
      builder: (context, state, _) {
        String format(DateTime? dt) =>
            dt == null ? '—' : DateFormat('MMM d, h:mm a').format(dt);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Maintenance rules', style: TextStyle(fontWeight: FontWeight.bold)),
                SwitchListTile(
                  title: const Text('Weather-based cleaning prompts'),
                  subtitle: Text(
                      'Triggers on rain/snow/hail or humidity ≥ ${prefs.humidityThreshold.toStringAsFixed(0)}%'),
                  value: prefs.weatherBasedCleaningEnabled,
                  onChanged: (v) => _service.updatePrefs(prefs.copyWith(weatherBasedCleaningEnabled: v)),
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final chips = [
                      ChoiceChip(
                        label: const Text('Normal'),
                        selected: prefs.weatherSensitivity == WeatherSensitivity.normal,
                        onSelected: (_) =>
                            _service.updatePrefs(prefs.copyWith(weatherSensitivity: WeatherSensitivity.normal)),
                      ),
                      ChoiceChip(
                        label: const Text('High'),
                        selected: prefs.weatherSensitivity == WeatherSensitivity.high,
                        onSelected: (_) =>
                            _service.updatePrefs(prefs.copyWith(weatherSensitivity: WeatherSensitivity.high)),
                      ),
                    ];

                    if (constraints.maxWidth < 360) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Weather sensitivity'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: chips,
                          )
                        ],
                      );
                    }

                    return Row(
                      children: [
                        const Text('Weather sensitivity'),
                        const SizedBox(width: 12),
                        Wrap(
                          spacing: 8,
                          children: chips,
                        )
                      ],
                    );
                  },
                ),
                Slider(
                  value: prefs.humidityThreshold,
                  min: 50,
                  max: 95,
                  divisions: 9,
                  label: '${prefs.humidityThreshold.toStringAsFixed(0)}% humidity',
                  onChanged: (v) => _service.updatePrefs(prefs.copyWith(humidityThreshold: v)),
                ),
                SwitchListTile(
                  title: const Text('Heavy-use cleaning prompts'),
                  subtitle: Text('Nudges when activity crosses ${prefs.heavyUseSensitivity.name} threshold'),
                  value: prefs.heavyUseEnabled,
                  onChanged: (v) => _service.updatePrefs(prefs.copyWith(heavyUseEnabled: v)),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('Heavy-use sensitivity'),
                    ChoiceChip(
                      label: const Text('Low'),
                      selected: prefs.heavyUseSensitivity == UsageSensitivity.low,
                      onSelected: (_) =>
                          _service.updatePrefs(prefs.copyWith(heavyUseSensitivity: UsageSensitivity.low)),
                    ),
                    ChoiceChip(
                      label: const Text('Medium'),
                      selected: prefs.heavyUseSensitivity == UsageSensitivity.medium,
                      onSelected: (_) =>
                          _service.updatePrefs(prefs.copyWith(heavyUseSensitivity: UsageSensitivity.medium)),
                    ),
                    ChoiceChip(
                      label: const Text('High'),
                      selected: prefs.heavyUseSensitivity == UsageSensitivity.high,
                      onSelected: (_) =>
                          _service.updatePrefs(prefs.copyWith(heavyUseSensitivity: UsageSensitivity.high)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _pill('Last weather trigger', format(state.lastWeatherTrigger)),
                    _pill('Weather reason', state.lastWeatherReason ?? '—'),
                    _pill('Last usage trigger', format(state.lastUsageTrigger)),
                    _pill('Usage reason', state.lastUsageReason ?? '—'),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () async {
                      await _engine.resetCooldowns();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Maintenance cooldown reset')),
                        );
                      }
                    },
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Reset maintenance cooldown'),
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _pill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _foodLevelCard() {
    return ValueListenableBuilder<FoodLevelReading?>(
      valueListenable: _service.foodLevel,
      builder: (context, reading, _) {
        final pct = reading?.percentFull ?? _service.preferences.value.lowFoodThresholdPercent;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final trailing = Text(
                        reading == null ? 'Awaiting sensor' : '${pct.toStringAsFixed(0)}%',
                        overflow: TextOverflow.ellipsis,
                      );

                      if (constraints.maxWidth < 360) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.rice_bowl_outlined),
                                const SizedBox(width: 8),
                                Text('Food level', style: Theme.of(context).textTheme.titleMedium),
                              ],
                            ),
                            const SizedBox(height: 6),
                            trailing,
                          ],
                        );
                      }

                      return Row(
                        children: [
                          const Icon(Icons.rice_bowl_outlined),
                          const SizedBox(width: 8),
                          Text('Food level', style: Theme.of(context).textTheme.titleMedium),
                          const Spacer(),
                          trailing,
                        ],
                      );
                    },
                  ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  minHeight: 10,
                  value: (pct / 100).clamp(0, 1),
                  backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                ),
                const SizedBox(height: 8),
                Text(
                  reading == null
                      ? 'Connect your production food-level sensor to surface alerts here.'
                      : 'Last update: ${DateFormat('hh:mm:ss a').format(reading.timestamp)}',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _iconForType(NotificationType type) {
    switch (type) {
      case NotificationType.lowFood:
        return Icons.local_fire_department_rounded;
      case NotificationType.clogged:
        return Icons.block;
      case NotificationType.cleaningDue:
        return Icons.cleaning_services_outlined;
      case NotificationType.heavyUse:
        return Icons.fitness_center_outlined;
      case NotificationType.weatherBased:
        return Icons.cloudy_snowing;
      case NotificationType.foodLevel:
        return Icons.rice_bowl;
    }
  }
}
