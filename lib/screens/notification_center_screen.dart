import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/notification_models.dart';
import '../services/notifications_service.dart';

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() => _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  final _service = NotificationsService.instance;

  @override
  void initState() {
    super.initState();
    _service.load();
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
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Alerts', style: TextStyle(fontWeight: FontWeight.bold)),
                      SwitchListTile(
                        title: const Text('Low food alerts'),
                        value: prefs.lowFoodEnabled,
                        onChanged: (val) => _service.updatePrefs(prefs.copyWith(lowFoodEnabled: val)),
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(prefs.lastCleaned == null
                                ? 'Last cleaned: not recorded'
                                : 'Last cleaned: ${DateFormat('yMMMd').format(prefs.lastCleaned!)}'),
                          ),
                          ElevatedButton(
                            onPressed: () async {
                              await _service.markCleaned();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Marked cleaned today')), 
                                );
                              }
                            },
                            child: const Text('Mark cleaned today'),
                          )
                        ],
                      )
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Simulate alerts', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _service.simulateLowFood(),
                        icon: const Icon(Icons.warning_amber),
                        label: const Text('Low food'),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _service.simulateClogged(),
                        icon: const Icon(Icons.block),
                        label: const Text('Clogged'),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _service.triggerCleaningCheck(),
                        icon: const Icon(Icons.cleaning_services_outlined),
                        label: const Text('Cleaning due'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
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
                    child: Text('No notifications yet. Use simulate buttons above to test.'),
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

  IconData _iconForType(NotificationType type) {
    switch (type) {
      case NotificationType.lowFood:
        return Icons.local_fire_department_rounded;
      case NotificationType.clogged:
        return Icons.block;
      case NotificationType.cleaningDue:
        return Icons.cleaning_services_outlined;
    }
  }
}
