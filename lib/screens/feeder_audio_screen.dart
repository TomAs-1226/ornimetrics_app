/// Heard vs. seen — fuses the BirdNET mic path (`/api/audio/recent`) with the
/// camera. Birds the feeder *heard* even if none were on camera.

library;

import 'package:flutter/material.dart';

import '../models/feeder_models.dart';
import '../services/feeder_api_service.dart';
import '../widgets/feeder_ui.dart';

class FeederAudioScreen extends StatefulWidget {
  const FeederAudioScreen({super.key});

  @override
  State<FeederAudioScreen> createState() => _FeederAudioScreenState();
}

class _FeederAudioScreenState extends State<FeederAudioScreen> {
  final _api = FeederApiService.instance;

  @override
  void initState() {
    super.initState();
    _api.getAudioRecent();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Heard nearby')),
      body: RefreshIndicator(
        onRefresh: () => _api.getAudioRecent(),
        child: ValueListenableBuilder<List<AudioHeard>>(
          valueListenable: _api.audioHeard,
          builder: (context, heard, _) {
            // Species currently/recently seen on camera, for the "also seen" hint.
            final seen = _api.lifeList.value.map((e) => e.display.toLowerCase()).toSet();
            if (heard.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  FeederEmptyState(
                    icon: Icons.graphic_eq_rounded,
                    title: 'Nothing heard yet',
                    message: 'The feeder\'s mic identifies birds by their call. Songs it recognises will appear here.',
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
                          'Identified by call on a separate mic — these birds may be nearby even when none are on camera.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
                for (final h in heard) ...[
                  _HeardCard(heard: h, alsoSeen: seen.contains(h.species.toLowerCase())),
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

class _HeardCard extends StatelessWidget {
  final AudioHeard heard;
  final bool alsoSeen;
  const _HeardCard({required this.heard, required this.alsoSeen});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FeederCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: scheme.tertiaryContainer, shape: BoxShape.circle),
            child: Icon(Icons.graphic_eq_rounded, color: scheme.onTertiaryContainer),
          ),
          const SizedBox(width: FeederSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(heard.species,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(relativeTime(heard.dateTime),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ),
                    if (alsoSeen) ...[
                      const SizedBox(width: FeederSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.videocam_rounded, size: 12, color: scheme.onSecondaryContainer),
                            const SizedBox(width: 4),
                            Text('Also seen',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSecondaryContainer)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          ConfidencePill(confidence: heard.confidence),
        ],
      ),
    );
  }
}
