/// Feeder settings — device controls backed by the real API.
///
/// - Detection on/off  → POST /api/control/detection
/// - Reset individuals → POST /api/control/reset_db
/// - Rename / remove the paired feeder (local).

library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/feeder_models.dart';
import '../services/feeder_api_service.dart';
import '../services/feeder_bluetooth_service.dart';
import '../widgets/feeder_ui.dart';

class FeederSettingsScreen extends StatefulWidget {
  final PairedFeeder device;

  /// Called after the feeder is removed so the caller can tear down live state.
  final VoidCallback onRemoved;
  const FeederSettingsScreen({super.key, required this.device, required this.onRemoved});

  @override
  State<FeederSettingsScreen> createState() => _FeederSettingsScreenState();
}

class _FeederSettingsScreenState extends State<FeederSettingsScreen> {
  final _api = FeederApiService.instance;
  final _bt = FeederBluetoothService.instance;
  bool _busy = false;

  Future<void> _toggleDetection(bool enabled) async {
    HapticFeedback.selectionClick();
    if (_api.isDemoMode) {
      final s = _api.status.value;
      if (s != null) {
        _api.status.value = FeederStatus(
          backend: s.backend, detectionEnabled: enabled, has3d: s.has3d,
          hasHailo: s.hasHailo, hasIndividualId: s.hasIndividualId, mode: s.mode, uptime: s.uptime,
        );
      }
      return;
    }
    setState(() => _busy = true);
    final result = await _api.setDetectionEnabled(enabled);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result == null) _snack('Couldn\'t reach the feeder');
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: widget.device.feederName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename feeder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Feeder name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final d = widget.device;
    final updated = PairedFeeder(
      deviceId: d.deviceId, deviceName: d.deviceName, feederName: name,
      staticIp: d.staticIp, version: d.version, pairedAt: d.pairedAt, userId: d.userId,
    );
    await _bt.saveAndSetCurrent(updated);
    if (mounted) _snack('Renamed to "$name"');
  }

  Future<void> _resetGallery() async {
    final scheme = Theme.of(context).colorScheme;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.restart_alt_rounded, color: scheme.error),
        title: const Text('Reset individuals?'),
        content: const Text(
          'This clears the feeder\'s individual-bird gallery (the "#" ids and their '
          'appearance memory). Your species life-list and history are kept. The '
          'feeder will start telling individuals apart again from scratch.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (_api.isDemoMode) {
      _snack('Demo feeder — nothing to reset');
      return;
    }
    setState(() => _busy = true);
    final ok = await _api.resetDatabase();
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(ok ? 'Individual gallery reset' : 'Couldn\'t reset — feeder unreachable');
    if (ok) _api.getIndividuals();
  }

  Future<void> _remove() async {
    final scheme = Theme.of(context).colorScheme;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove feeder?'),
        content: Text('Remove "${widget.device.feederName}"? You can add it again later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _bt.removePairedDevice(widget.device.deviceId);
    _api.clear();
    widget.onRemoved();
    if (mounted) Navigator.of(context).pop();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Feeder settings')),
      body: ListView(
        padding: FeederSpacing.screen,
        children: [
          const FeederSectionHeader(icon: Icons.videocam_rounded, title: 'Detection'),
          FeederCard(
            padding: EdgeInsets.zero,
            child: ValueListenableBuilder<FeederStatus?>(
              valueListenable: _api.status,
              builder: (context, status, _) {
                final enabled = status?.detectionEnabled ?? true;
                return SwitchListTile(
                  value: enabled,
                  onChanged: _busy ? null : _toggleDetection,
                  secondary: Icon(enabled ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                      color: scheme.primary),
                  title: const Text('Bird detection'),
                  subtitle: Text(enabled ? 'The feeder is actively watching' : 'Detection is paused'),
                );
              },
            ),
          ),
          const SizedBox(height: FeederSpacing.lg),
          const FeederSectionHeader(icon: Icons.tune_rounded, title: 'Device'),
          FeederCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.drive_file_rename_outline_rounded, color: scheme.primary),
                  title: const Text('Rename feeder'),
                  subtitle: Text(widget.device.feederName),
                  onTap: _rename,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.restart_alt_rounded, color: scheme.primary),
                  title: const Text('Reset individuals'),
                  subtitle: const Text('Clear the re-ID gallery; keep species & history'),
                  onTap: _resetGallery,
                ),
              ],
            ),
          ),
          const SizedBox(height: FeederSpacing.lg),
          FeederCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(Icons.link_off_rounded, color: scheme.error),
              title: Text('Remove feeder', style: TextStyle(color: scheme.error)),
              subtitle: const Text('Unpair from this phone'),
              onTap: _remove,
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: FeederSpacing.lg),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }
}
