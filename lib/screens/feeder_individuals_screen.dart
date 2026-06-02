/// "Your regulars" — the list of individual birds the feeder re-identifies.
///
/// Binds to `/api/individuals`. Re-ID is appearance-based and approximate, so
/// the copy frames it as a soft hint. Tapping a bird opens its profile.

library;

import 'package:flutter/material.dart';

import '../models/feeder_models.dart';
import '../services/feeder_api_service.dart';
import '../widgets/feeder_ui.dart';
import 'feeder_individual_profile_screen.dart';

class FeederIndividualsScreen extends StatefulWidget {
  const FeederIndividualsScreen({super.key});

  @override
  State<FeederIndividualsScreen> createState() => _FeederIndividualsScreenState();
}

class _FeederIndividualsScreenState extends State<FeederIndividualsScreen> {
  final _api = FeederApiService.instance;

  @override
  void initState() {
    super.initState();
    _api.getIndividuals();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Your regulars')),
      body: RefreshIndicator(
        onRefresh: () => _api.getIndividuals(),
        child: ValueListenableBuilder<List<FeederIndividual>>(
          valueListenable: _api.individuals,
          builder: (context, list, _) {
            if (list.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  FeederEmptyState(
                    icon: Icons.pets_rounded,
                    title: 'No regulars yet',
                    message:
                        'As individual birds return, the feeder learns to tell them apart and they show up here.',
                  ),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.all(FeederSpacing.lg),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: FeederSpacing.lg),
                  padding: const EdgeInsets.all(FeederSpacing.md),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(FeederSpacing.radiusSm),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
                      const SizedBox(width: FeederSpacing.sm),
                      Expanded(
                        child: Text(
                          'Individual recognition is appearance-based and approximate — treat it as a friendly hint.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
                for (final bird in list) ...[
                  _IndividualCard(bird: bird),
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

class _IndividualCard extends StatelessWidget {
  final FeederIndividual bird;
  const _IndividualCard({required this.bird});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FeederCard(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            FeederIndividualProfileScreen(individualId: bird.id, species: bird.species),
      )),
      child: Row(
        children: [
          SpeciesAvatar(name: bird.display, size: 48),
          const SizedBox(width: FeederSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(bird.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    if (bird.name != null && bird.name!.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(bird.id,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.outline)),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(bird.display,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onSurfaceVariant)),
                if (bird.lastSeen != null)
                  Text('Last seen ${relativeTime(bird.lastSeen!)}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.outline)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}
