/// Welfare alerts — screening flags, never diagnoses.
///
/// Lists `/api/welfare/alerts`. The header makes the framing explicit and
/// offers a "find a wildlife rehabber" action. A human is always in the loop.

library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/feeder_models.dart';
import '../services/feeder_api_service.dart';
import '../widgets/feeder_ui.dart';
import 'feeder_individual_profile_screen.dart';

class FeederWelfareScreen extends StatefulWidget {
  const FeederWelfareScreen({super.key});

  @override
  State<FeederWelfareScreen> createState() => _FeederWelfareScreenState();
}

class _FeederWelfareScreenState extends State<FeederWelfareScreen> {
  final _api = FeederApiService.instance;

  @override
  void initState() {
    super.initState();
    _api.getWelfareAlerts();
  }

  Future<void> _findRehabber() async {
    final uri = Uri.parse(WelfareCopy.rehabberUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Welfare alerts')),
      body: RefreshIndicator(
        onRefresh: () => _api.getWelfareAlerts(),
        child: ValueListenableBuilder<List<WelfareAlert>>(
          valueListenable: _api.welfareAlerts,
          builder: (context, alerts, _) {
            return ListView(
              padding: const EdgeInsets.all(FeederSpacing.lg),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                // Always-on framing card.
                Container(
                  padding: FeederSpacing.card,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(FeederSpacing.radius),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.health_and_safety_outlined, color: scheme.primary),
                          const SizedBox(width: FeederSpacing.sm),
                          Expanded(
                            child: Text('How to read these',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                      const SizedBox(height: FeederSpacing.sm),
                      Text(WelfareCopy.screeningNote,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      const SizedBox(height: FeederSpacing.md),
                      FilledButton.tonalIcon(
                        onPressed: _findRehabber,
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: const Text(WelfareCopy.findRehabber),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: FeederSpacing.lg),
                if (alerts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: FeederEmptyState(
                      icon: Icons.verified_outlined,
                      title: 'No welfare flags',
                      message: 'Nothing has been flagged recently. That\'s good news.',
                    ),
                  )
                else
                  for (final a in alerts) ...[
                    _WelfareAlertCard(alert: a),
                    const SizedBox(height: FeederSpacing.md),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WelfareAlertCard extends StatelessWidget {
  final WelfareAlert alert;
  const _WelfareAlertCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasIndividual = alert.individual != null && alert.individual!.isNotEmpty;
    return FeederCard(
      onTap: hasIndividual
          ? () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => FeederIndividualProfileScreen(individualId: alert.individual!),
              ))
          : null,
      child: Row(
        children: [
          SpeciesAvatar(name: alert.displayName, size: 48, distressed: true),
          const SizedBox(width: FeederSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(alert.displayName,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  '${relativeTime(alert.dateTime)}'
                  '${hasIndividual ? ' • ${alert.individual}' : ''}'
                  '${alert.distressZ != null ? ' • score ${alert.distressZ!.toStringAsFixed(1)}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const DistressChip(),
          if (hasIndividual) Icon(Icons.chevron_right, color: scheme.onSurfaceVariant, size: 20),
        ],
      ),
    );
  }
}
