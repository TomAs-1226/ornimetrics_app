/// Activity feed + species life-list.
///
/// The feed binds directly to the API service's `sightings` notifier, which is
/// kept live by the SSE stream (new sightings are prepended as they happen) and
/// backfilled by `/api/sightings/recent`. The life-list comes from
/// `/api/species/summary`.

library;

import 'package:flutter/material.dart';

import '../models/feeder_models.dart';
import '../services/feeder_api_service.dart';
import '../widgets/feeder_ui.dart';
import 'feeder_individual_profile_screen.dart';

class FeederActivityScreen extends StatefulWidget {
  final int initialTab;
  const FeederActivityScreen({super.key, this.initialTab = 0});

  @override
  State<FeederActivityScreen> createState() => _FeederActivityScreenState();
}

class _FeederActivityScreenState extends State<FeederActivityScreen>
    with SingleTickerProviderStateMixin {
  final _api = FeederApiService.instance;
  late final TabController _tabs =
      TabController(length: 2, vsync: this, initialIndex: widget.initialTab.clamp(0, 1));

  @override
  void initState() {
    super.initState();
    // Backfill in case the user deep-linked here.
    _api.getSightingsRecent();
    _api.getSpeciesSummary();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Feed'),
            Tab(text: 'Life list'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _FeedTab(api: _api),
          _LifeListTab(api: _api),
        ],
      ),
    );
  }
}

class _FeedTab extends StatelessWidget {
  final FeederApiService api;
  const _FeedTab({required this.api});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: api.getSightingsRecent,
      child: ValueListenableBuilder<List<Sighting>>(
        valueListenable: api.sightings,
        builder: (context, list, _) {
          if (list.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 120),
                FeederEmptyState(
                  icon: Icons.timeline_rounded,
                  title: 'No visits yet',
                  message: 'When a bird visits the feeder it will appear here, newest first.',
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: FeederSpacing.sm),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 64),
            itemBuilder: (context, i) => SightingTile(sighting: list[i]),
          );
        },
      ),
    );
  }
}

class _LifeListTab extends StatelessWidget {
  final FeederApiService api;
  const _LifeListTab({required this.api});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: api.getSpeciesSummary,
      child: ValueListenableBuilder<List<SpeciesLifeEntry>>(
        valueListenable: api.lifeList,
        builder: (context, list, _) {
          if (list.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 120),
                FeederEmptyState(
                  icon: Icons.menu_book_rounded,
                  title: 'Your life list is empty',
                  message: 'Every species the feeder identifies gets added here with a running count.',
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(FeederSpacing.lg),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: FeederSpacing.md),
            itemBuilder: (context, i) {
              final e = list[i];
              return FeederCard(
                child: Row(
                  children: [
                    SpeciesAvatar(name: e.display, size: 44),
                    const SizedBox(width: FeederSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.display,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                            e.lastSeen != null ? 'Last seen ${relativeTime(e.lastSeen!)}' : 'Seen recently',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${e.count}',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: scheme.primary)),
                        Text('visits', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// A single visit row, reused by the home hub and the feed. Tapping a sighting
/// with an individual opens that bird's profile.
class SightingTile extends StatelessWidget {
  final Sighting sighting;
  const SightingTile({super.key, required this.sighting});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasIndividual = sighting.individual != null && sighting.individual!.isNotEmpty;
    return ListTile(
      onTap: hasIndividual
          ? () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => FeederIndividualProfileScreen(individualId: sighting.individual!),
              ))
          : null,
      leading: SpeciesAvatar(name: sighting.displayName, distressed: sighting.distressed),
      title: Text(sighting.displayName,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      // Single ellipsizing line so it can never overflow the tight width
      // ListTile gives its subtitle.
      subtitle: Text(
        hasIndividual
            ? '${relativeTime(sighting.dateTime)}  •  ${sighting.individual}'
            : relativeTime(sighting.dateTime),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
      // Keep trailing compact so it never crowds the title (ListTile doesn't
      // shrink trailing): a small welfare icon instead of the full chip.
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (sighting.distressed)
            Icon(Icons.health_and_safety_outlined, color: scheme.error, size: 20)
          else
            ConfidencePill(confidence: sighting.confidence),
          if (hasIndividual)
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant, size: 20),
        ],
      ),
    );
  }
}
