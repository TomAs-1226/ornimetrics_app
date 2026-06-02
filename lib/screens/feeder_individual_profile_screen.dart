/// One bird's profile — the "you have regulars" feature.
///
/// Loads `/api/individual/<id>`: visit history, species, and a health trend
/// (distress_z over time) rendered as a sparkline. Hosts the "teach the feeder"
/// actions (name / correct species / flag) which POST to `/api/teach` — the
/// fuel for the self-improving loop.

library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/feeder_models.dart';
import '../services/feeder_api_service.dart';
import '../widgets/feeder_ui.dart';

class FeederIndividualProfileScreen extends StatefulWidget {
  final String individualId; // e.g. "#3"
  final String? species; // optional hint for the empty header
  const FeederIndividualProfileScreen({
    super.key,
    required this.individualId,
    this.species,
  });

  @override
  State<FeederIndividualProfileScreen> createState() =>
      _FeederIndividualProfileScreenState();
}

class _FeederIndividualProfileScreenState
    extends State<FeederIndividualProfileScreen> {
  final _api = FeederApiService.instance;
  IndividualProfile? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _profile == null;
      _error = null;
    });
    final p = await _api.getIndividual(widget.individualId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (p != null) {
        _profile = p;
      } else if (_profile == null) {
        _error = 'Couldn\'t load this bird\'s profile.';
      }
    });
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: _profile?.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name this bird'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'e.g. Spot', labelText: 'Name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final ok = await _api.teachName(individual: widget.individualId, name: name);
    _afterTeach(ok, ok ? 'Named "$name" — thanks for teaching the feeder' : 'Couldn\'t save the name');
  }

  Future<void> _correctSpecies() async {
    final controller = TextEditingController();
    final species = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Correct the species'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Currently identified as ${_profile?.display ?? 'unknown'}.',
                style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: FeederSpacing.md),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'e.g. Blue Jay', labelText: 'Correct species'),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Submit')),
        ],
      ),
    );
    if (species == null || species.isEmpty) return;
    final ok = await _api.teachSpecies(individual: widget.individualId, species: species);
    _afterTeach(ok, ok ? 'Correction submitted — the feeder learns from this' : 'Couldn\'t submit the correction');
  }

  Future<void> _flag() async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report a concern'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'e.g. looks like an injured wing', labelText: 'Note'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Send')),
        ],
      ),
    );
    if (note == null || note.isEmpty) return;
    final ok = await _api.teachFlag(individual: widget.individualId, note: note);
    _afterTeach(ok, ok ? 'Thanks — your note was recorded' : 'Couldn\'t record the note');
  }

  void _afterTeach(bool ok, String message) {
    if (!mounted) return;
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    if (ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_profile?.displayName ?? widget.individualId)),
      body: _loading
          ? const _ProfileSkeleton()
          : _error != null
              ? FeederErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _ProfileBody(
                    profile: _profile!,
                    onRename: _rename,
                    onCorrect: _correctSpecies,
                    onFlag: _flag,
                  ),
                ),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  final IndividualProfile profile;
  final VoidCallback onRename, onCorrect, onFlag;
  const _ProfileBody({
    required this.profile,
    required this.onRename,
    required this.onCorrect,
    required this.onFlag,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final df = DateFormat.yMMMd();
    return ListView(
      padding: FeederSpacing.screen,
      children: [
        // Header
        FeederCard(
          child: Row(
            children: [
              SpeciesAvatar(name: profile.display, size: 64),
              const SizedBox(width: FeederSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(profile.displayName,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        IconButton(
                          tooltip: 'Rename',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: onRename,
                        ),
                      ],
                    ),
                    Text(profile.display, style: TextStyle(color: scheme.onSurfaceVariant)),
                    Text(profile.id, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.outline)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: FeederSpacing.lg),

        // Visit stats
        Row(
          children: [
            Expanded(child: FeederStatTile(icon: Icons.visibility_rounded, label: 'Visits', value: profile.count)),
            const SizedBox(width: FeederSpacing.md),
            Expanded(
              child: FeederCard(
                padding: const EdgeInsets.symmetric(vertical: FeederSpacing.lg, horizontal: FeederSpacing.sm),
                child: Column(
                  children: [
                    Icon(Icons.schedule_rounded, color: scheme.primary, size: 26),
                    const SizedBox(height: FeederSpacing.sm),
                    Text(profile.lastSeen != null ? relativeTime(profile.lastSeen!) : '—',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: FeederSpacing.xs),
                    Text('Last seen', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (profile.firstSeen != null) ...[
          const SizedBox(height: FeederSpacing.sm),
          Text('A regular since ${df.format(profile.firstSeen!)}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
        const SizedBox(height: FeederSpacing.lg),

        // Health trend
        FeederSectionHeader(icon: Icons.monitor_heart_outlined, title: 'Health trend'),
        FeederCard(
          child: _HealthTrend(profile: profile),
        ),
        const SizedBox(height: FeederSpacing.lg),

        // Teach the feeder
        FeederSectionHeader(icon: Icons.school_outlined, title: 'Teach the feeder'),
        FeederCard(
          child: Column(
            children: [
              _TeachRow(
                icon: Icons.badge_outlined,
                title: 'Name this bird',
                subtitle: 'Give your regular a name',
                onTap: onRename,
              ),
              const Divider(height: 1),
              _TeachRow(
                icon: Icons.spellcheck_rounded,
                title: 'Correct the species',
                subtitle: 'Help the model get it right',
                onTap: onCorrect,
              ),
              const Divider(height: 1),
              _TeachRow(
                icon: Icons.flag_outlined,
                title: 'Report a concern',
                subtitle: 'Flag something that looks off',
                onTap: onFlag,
              ),
            ],
          ),
        ),
        const SizedBox(height: FeederSpacing.lg),
        Text(
          'Corrections you make here train the feeder on your own birds over time.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: FeederSpacing.xl),
      ],
    );
  }
}

class _HealthTrend extends StatelessWidget {
  final IndividualProfile profile;
  const _HealthTrend({required this.profile});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trend = profile.distressTrend;
    if (trend.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: FeederSpacing.lg),
        child: Row(
          children: [
            Icon(Icons.show_chart_rounded, color: scheme.onSurfaceVariant),
            const SizedBox(width: FeederSpacing.md),
            Expanded(
              child: Text('Not enough data yet to chart a trend.',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
          ],
        ),
      );
    }
    final values = trend.map((e) => e.z).toList();
    final last = profile.lastDistressZ ?? values.last;
    // The server flags above ~2.0; surface that as a gentle reference line.
    const threshold = 2.0;
    final elevated = last >= threshold;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(last.toStringAsFixed(1),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: elevated ? scheme.error : scheme.primary,
                    )),
            const SizedBox(width: 6),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('current screening score',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ),
            ),
          ],
        ),
        const SizedBox(height: FeederSpacing.md),
        Sparkline(
          values: values,
          color: elevated ? scheme.error : scheme.primary,
          threshold: threshold,
          height: 72,
        ),
        const SizedBox(height: FeederSpacing.md),
        Container(
          padding: const EdgeInsets.all(FeederSpacing.md),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(FeederSpacing.radiusSm),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: FeederSpacing.sm),
              Expanded(
                child: Text(WelfareCopy.screeningNote,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TeachRow extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  const _TeachRow({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: FeederSpacing.screen,
      children: const [
        SkeletonBox(height: 96, borderRadius: BorderRadius.all(Radius.circular(16))),
        SizedBox(height: FeederSpacing.lg),
        SkeletonBox(height: 92, borderRadius: BorderRadius.all(Radius.circular(16))),
        SizedBox(height: FeederSpacing.lg),
        SkeletonBox(height: 180, borderRadius: BorderRadius.all(Radius.circular(16))),
      ],
    );
  }
}
