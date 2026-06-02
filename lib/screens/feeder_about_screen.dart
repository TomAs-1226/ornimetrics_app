/// "About this feeder" — a premium device spec sheet, styled like the
/// "About phone" screens on Chinese ROMs (ColorOS/MIUI): a hero with the model
/// + OS, capability highlights, and a clean grouped specifications list.
///
/// Live fields come from `/api/status` + `/api/stats`; the fixed hardware specs
/// (processor, clock, accelerator, RAM, camera, …) describe the Ornimetrics
/// platform: a Raspberry Pi 5 class board with a Hailo-8 and the custom
/// Ornimetrics **D1** vision accelerator.

library;

import 'package:flutter/material.dart';

import '../models/feeder_models.dart';
import '../services/feeder_api_service.dart';
import '../widgets/feeder_ui.dart';

/// Fixed platform hardware (not exposed by the API).
class _HW {
  static const model = 'Ornimetrics One';
  static const modelCode = 'OMX-1';
  static const processor = 'Broadcom BCM2712';
  static const cpu = 'Quad-core Arm Cortex-A76 @ 2.4 GHz';
  static const visionChip = 'Ornimetrics D1';
  static const visionDesc = 'Custom vision accelerator';
  static const accelerator = 'Hailo-8';
  static const tops = '26 TOPS';
  static const ram = '8 GB LPDDR4X';
  static const storage = '64 GB';
  static const cameraMain = '12 MP Sony IMX708';
  static const tof = '3D Time-of-Flight depth';
  static const mic = 'Far-field mic array';
  static const connectivity = 'Wi-Fi (2.4/5 GHz) · Bluetooth LE';
  static const speciesModel = 'NABirds · 555 species';
}

class FeederAboutScreen extends StatefulWidget {
  final PairedFeeder device;
  const FeederAboutScreen({super.key, required this.device});

  @override
  State<FeederAboutScreen> createState() => _FeederAboutScreenState();
}

class _FeederAboutScreenState extends State<FeederAboutScreen> {
  final _api = FeederApiService.instance;

  @override
  void initState() {
    super.initState();
    if (!_api.isDemoMode) {
      _api.getStatus();
      _api.getStats();
    }
  }

  Future<void> _refresh() async {
    if (_api.isDemoMode) return;
    await Future.wait([_api.getStatus(), _api.getStats()]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About this feeder')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ValueListenableBuilder<FeederStatus?>(
          valueListenable: _api.status,
          builder: (context, status, _) {
            return ValueListenableBuilder<FeederStatsCounters?>(
              valueListenable: _api.stats,
              builder: (context, stats, __) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: FeederSpacing.xl),
                  children: [
                    _Hero(device: widget.device, status: status),
                    Padding(
                      padding: FeederSpacing.screen,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const FeederSectionHeader(
                              icon: Icons.auto_awesome_rounded, title: 'AI capabilities'),
                          _Capabilities(status: status),
                          const SizedBox(height: FeederSpacing.xl),
                          const FeederSectionHeader(
                              icon: Icons.tune_rounded, title: 'Live performance'),
                          _Performance(status: status, stats: stats),
                          const SizedBox(height: FeederSpacing.xl),
                          const FeederSectionHeader(
                              icon: Icons.developer_board_rounded, title: 'Hardware'),
                          _SpecGroup(rows: _hardwareRows(status)),
                          const SizedBox(height: FeederSpacing.lg),
                          const FeederSectionHeader(
                              icon: Icons.info_outline_rounded, title: 'System'),
                          _SpecGroup(rows: _systemRows(status)),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  List<(String, String)> _hardwareRows(FeederStatus? s) {
    final camera = '${_HW.cameraMain}${(s?.has3d ?? false) ? '  +  ${_HW.tof}' : ''}';
    return [
      ('Vision accelerator', '${_HW.visionChip} + ${_HW.accelerator}'),
      ('AI performance', _HW.tops),
      ('Processor', _HW.processor),
      ('CPU', _HW.cpu),
      ('RAM', _HW.ram),
      ('Storage', _HW.storage),
      ('Camera', camera),
      ('Audio', _HW.mic),
      ('Connectivity', _HW.connectivity),
    ];
  }

  List<(String, String)> _systemRows(FeederStatus? s) {
    return [
      ('Model', '${_HW.model} (${_HW.modelCode})'),
      ('Species model', _HW.speciesModel),
      ('AI backend', s?.backend ?? widget.device.version),
      ('Operating mode', s?.mode ?? '—'),
      ('Detection', (s?.detectionEnabled ?? false) ? 'Enabled' : 'Paused'),
      ('IP address', '${widget.device.staticIp}:5000'),
      ('Firmware', widget.device.version),
    ];
  }
}

class _Hero extends StatelessWidget {
  final PairedFeeder device;
  final FeederStatus? status;
  const _Hero({required this.device, this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(FeederSpacing.lg, FeederSpacing.xl, FeederSpacing.lg, FeederSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.tertiary],
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: scheme.onPrimary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.sensors_rounded, color: scheme.onPrimary, size: 40),
          ),
          const SizedBox(height: FeederSpacing.md),
          Text(device.feederName,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: scheme.onPrimary, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text('${_HW.model} · ${_HW.modelCode}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onPrimary.withValues(alpha: 0.85))),
          const SizedBox(height: FeederSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: FeederSpacing.md, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.onPrimary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('OrnimetricsOS ${device.version}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _Capabilities extends StatelessWidget {
  final FeederStatus? status;
  const _Capabilities({this.status});

  @override
  Widget build(BuildContext context) {
    final caps = <_Cap>[
      _Cap(Icons.bolt_rounded, _HW.visionChip, _HW.visionDesc, true),
      _Cap(Icons.memory_rounded, _HW.accelerator, '${_HW.tops} neural engine', status?.hasHailo ?? false),
      _Cap(Icons.view_in_ar_rounded, '3D camera', 'Depth-aware detection', status?.has3d ?? false),
      _Cap(Icons.fingerprint_rounded, 'Individual re-ID', 'Tells your regulars apart', status?.hasIndividualId ?? false),
      const _Cap(Icons.graphic_eq_rounded, 'Audio ID', 'BirdNET call recognition', true),
      const _Cap(Icons.health_and_safety_outlined, 'Welfare screening', 'Flags birds to check on', true),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellW = (constraints.maxWidth - FeederSpacing.md) / 2;
        return Wrap(
          spacing: FeederSpacing.md,
          runSpacing: FeederSpacing.md,
          children: [for (final c in caps) SizedBox(width: cellW, child: _CapCard(cap: c))],
        );
      },
    );
  }
}

class _Cap {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool available;
  const _Cap(this.icon, this.title, this.subtitle, this.available);
}

class _CapCard extends StatelessWidget {
  final _Cap cap;
  const _CapCard({required this.cap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = cap.available;
    return FeederCard(
      padding: const EdgeInsets.all(FeederSpacing.md),
      color: on ? scheme.surfaceContainerHigh : scheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: on ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(cap.icon, size: 20,
                    color: on ? scheme.onPrimaryContainer : scheme.onSurfaceVariant),
              ),
              const Spacer(),
              Icon(on ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
                  size: 18, color: on ? Colors.green : scheme.outline),
            ],
          ),
          const SizedBox(height: FeederSpacing.sm),
          Text(cap.title,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: on ? scheme.onSurface : scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(cap.subtitle,
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _Performance extends StatelessWidget {
  final FeederStatus? status;
  final FeederStatsCounters? stats;
  const _Performance({this.status, this.stats});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fps = stats?.fps ?? 0;
    return FeederCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _Metric(
                  big: fps.toStringAsFixed(fps >= 10 ? 0 : 1),
                  unit: 'fps',
                  label: 'Throughput',
                  color: scheme.primary,
                ),
              ),
              Container(width: 1, height: 48, color: scheme.outlineVariant),
              Expanded(
                child: _Metric(
                  big: _uptime(status?.uptime ?? stats?.uptimeSeconds ?? 0),
                  unit: '',
                  label: 'Uptime',
                  color: scheme.tertiary,
                ),
              ),
            ],
          ),
          if (stats != null) ...[
            const Divider(height: FeederSpacing.xl),
            Row(
              children: [
                Expanded(child: _MiniStat(value: stats!.totalDetections, label: 'Detections')),
                Expanded(child: _MiniStat(value: stats!.totalEnrollments, label: 'Enrollments')),
                Expanded(child: _MiniStat(value: stats!.totalTriggers, label: 'Triggers')),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _uptime(double seconds) {
    final s = seconds.round();
    final d = s ~/ 86400, h = (s % 86400) ~/ 3600, m = (s % 3600) ~/ 60;
    if (d > 0) return '${d}d ${h}h';
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

class _Metric extends StatelessWidget {
  final String big, unit, label;
  final Color color;
  const _Metric({required this.big, required this.unit, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: color),
              children: [
                TextSpan(text: big),
                if (unit.isNotEmpty)
                  TextSpan(text: ' $unit', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final int value;
  final String label;
  const _MiniStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: AnimatedCount(value: value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 2),
        Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

/// A grouped "About phone"-style list of label → value rows.
class _SpecGroup extends StatelessWidget {
  final List<(String, String)> rows;
  const _SpecGroup({required this.rows});

  @override
  Widget build(BuildContext context) {
    return FeederCard(
      padding: const EdgeInsets.symmetric(horizontal: FeederSpacing.lg, vertical: FeederSpacing.xs),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _SpecRow(label: rows[i].$1, value: rows[i].$2),
          ],
        ],
      ),
    );
  }
}

class _SpecRow extends StatelessWidget {
  final String label, value;
  const _SpecRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FeederSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            flex: 4,
            child: Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
          const SizedBox(width: FeederSpacing.md),
          Expanded(
            flex: 6,
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
