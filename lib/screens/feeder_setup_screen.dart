/// Premium "Add your feeder" flow.
///
/// The real feeder is a Wi‑Fi device reached over HTTP at a static IP; its
/// Bluetooth peripheral is *read-only status* (no provisioning characteristic),
/// so we don't try to pair/configure over BLE. Instead BLE is used to *detect*
/// that the feeder is powered and nearby, and setup completes over the network:
/// we auto-discover the feeder (default IP / mDNS) and let the user confirm or
/// enter the IP, then verify with a real `/api/status` call.

library;

import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/feeder_models.dart';
import '../services/feeder_bluetooth_service.dart';
import '../services/feeder_api_service.dart';
import '../widgets/feeder_ui.dart';

enum _Phase { discover, connect, connecting, success }

class FeederSetupScreen extends StatefulWidget {
  final VoidCallback? onSetupComplete;
  const FeederSetupScreen({super.key, this.onSetupComplete});

  @override
  State<FeederSetupScreen> createState() => _FeederSetupScreenState();
}

class _FeederSetupScreenState extends State<FeederSetupScreen>
    with TickerProviderStateMixin {
  final _bt = FeederBluetoothService.instance;
  final _api = FeederApiService.instance;

  final _ip = TextEditingController(text: '192.168.0.86');
  final _name = TextEditingController(text: 'Backyard Feeder');
  final _formKey = GlobalKey<FormState>();

  late final AnimationController _radar =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  _Phase _phase = _Phase.discover;
  bool _btDetected = false;
  String? _autoIp; // an IP that answered during auto-discovery
  FeederStatus? _status; // status from a successful probe (for success preview)
  String? _error;

  // Candidate hosts to auto-probe while the user reads the discover screen.
  static const _candidates = ['192.168.0.86', 'thomaspi.local'];

  @override
  void initState() {
    super.initState();
    _startBlePresence();
    _autoDiscover();
  }

  Future<void> _startBlePresence() async {
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    // Request permission but never block setup on it — IP setup works regardless.
    final ok = await _bt.requestPermissions();
    if (!ok) return;
    await _bt.startScan();
    _bt.discoveredDevices.addListener(_onBleDevices);
  }

  void _onBleDevices() {
    if (!mounted) return;
    final found = _bt.discoveredDevices.value.isNotEmpty;
    if (found != _btDetected) setState(() => _btDetected = found);
  }

  Future<void> _autoDiscover() async {
    for (final host in _candidates) {
      final status = await _api.probe('http://$host:5000');
      if (!mounted) return;
      if (status != null) {
        setState(() {
          _autoIp = host;
          _status = status;
          if (_ip.text == '192.168.0.86') _ip.text = host;
        });
        return; // first responder wins
      }
    }
  }

  Future<void> _connect(String host) async {
    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();
    setState(() {
      _phase = _Phase.connecting;
      _error = null;
    });
    final status = await _api.probe('http://$host:5000');
    if (!mounted) return;
    if (status == null) {
      setState(() {
        _phase = _Phase.connect;
        _error = 'No feeder answered at $host:5000. Check the address and that '
            'your phone is on the same Wi‑Fi as the feeder.';
      });
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'local';
    final feeder = PairedFeeder(
      deviceId: 'net-$host',
      deviceName: 'Ornimetrics',
      feederName: _name.text.trim().isEmpty ? 'My Feeder' : _name.text.trim(),
      staticIp: host,
      version: status.backend,
      pairedAt: DateTime.now(),
      userId: uid,
    );
    await _bt.saveAndSetCurrent(feeder);
    _api.setFromPairedFeeder(feeder);
    if (!mounted) return;
    setState(() {
      _status = status;
      _phase = _Phase.success;
    });
    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 1400));
    widget.onSetupComplete?.call();
    if (mounted) Navigator.of(context).pop(feeder);
  }

  @override
  void dispose() {
    _radar.dispose();
    _bt.discoveredDevices.removeListener(_onBleDevices);
    _bt.stopScan();
    _ip.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add your feeder'), centerTitle: true),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: switch (_phase) {
            _Phase.discover => _discover(),
            _Phase.connect => _connectForm(),
            _Phase.connecting => _connecting(),
            _Phase.success => _success(),
          },
        ),
      ),
    );
  }

  // ----- Discover -----------------------------------------------------------
  Widget _discover() {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      key: const ValueKey('discover'),
      padding: FeederSpacing.screen,
      children: [
        const SizedBox(height: FeederSpacing.lg),
        Center(child: _Radar(controller: _radar, active: _autoIp == null)),
        const SizedBox(height: FeederSpacing.xl),
        Text('Let\'s find your feeder',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: FeederSpacing.sm),
        Text(
          'Your Ornimetrics feeder joins your Wi‑Fi and the app talks to it over '
          'your home network.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: FeederSpacing.lg),
        // BLE presence indicator (detection only — not used to provision).
        _PresenceChip(detected: _btDetected),
        const SizedBox(height: FeederSpacing.lg),
        const _Checklist(items: [
          'Power on the feeder and wait ~30s',
          'Make sure it\'s connected to your Wi‑Fi',
          'Keep your phone on the same network',
        ]),
        const SizedBox(height: FeederSpacing.xl),
        if (_autoIp != null)
          _FoundCard(
            ip: _autoIp!,
            status: _status,
            onConnect: () => _connect(_autoIp!),
          )
        else
          FilledButton.icon(
            onPressed: () => setState(() => _phase = _Phase.connect),
            icon: const Icon(Icons.wifi_rounded),
            label: const Text('Connect by IP address'),
          ),
        const SizedBox(height: FeederSpacing.sm),
        if (_autoIp != null)
          TextButton(
            onPressed: () => setState(() => _phase = _Phase.connect),
            child: const Text('Enter a different address'),
          ),
      ],
    );
  }

  // ----- Connect form -------------------------------------------------------
  Widget _connectForm() {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      key: const ValueKey('connect'),
      padding: FeederSpacing.screen,
      children: [
        const SizedBox(height: FeederSpacing.sm),
        Text('Connect to your feeder',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: FeederSpacing.xs),
        Text(
          'Enter the feeder\'s IP address (shown during setup, e.g. 192.168.0.86).',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: FeederSpacing.lg),
        Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Feeder name',
                  prefixIcon: Icon(Icons.label_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: FeederSpacing.md),
              TextFormField(
                controller: _ip,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'IP address',
                  hintText: '192.168.0.86',
                  prefixIcon: Icon(Icons.lan_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Enter the feeder\'s IP address';
                  final ipOk = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(t) &&
                      t.split('.').every((p) => (int.tryParse(p) ?? 999) <= 255);
                  final hostOk = RegExp(r'^[a-zA-Z0-9.\-]+$').hasMatch(t);
                  if (!ipOk && !hostOk) return 'Enter a valid IP like 192.168.0.86';
                  return null;
                },
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: FeederSpacing.lg),
          _ErrorBox(message: _error!),
        ],
        const SizedBox(height: FeederSpacing.xl),
        FilledButton.icon(
          onPressed: () {
            if (_formKey.currentState!.validate()) _connect(_ip.text.trim());
          },
          icon: const Icon(Icons.link_rounded),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text('Connect'),
          ),
        ),
        const SizedBox(height: FeederSpacing.sm),
        TextButton(
          onPressed: () => setState(() => _phase = _Phase.discover),
          child: const Text('Back'),
        ),
      ],
    );
  }

  // ----- Connecting ---------------------------------------------------------
  Widget _connecting() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      key: const ValueKey('connecting'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 84, height: 84,
            child: CircularProgressIndicator(strokeWidth: 5, color: scheme.primary),
          ),
          const SizedBox(height: FeederSpacing.xl),
          Text('Reaching your feeder…',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: FeederSpacing.xs),
          Text(_ip.text.trim(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  // ----- Success ------------------------------------------------------------
  Widget _success() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      key: const ValueKey('success'),
      child: SingleChildScrollView(
        padding: FeederSpacing.screen,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 600),
              curve: Curves.elasticOut,
              builder: (context, v, _) => Transform.scale(
                scale: v,
                child: Container(
                  width: 96, height: 96,
                  decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
                  child: Icon(Icons.check_rounded, size: 56, color: scheme.onPrimaryContainer),
                ),
              ),
            ),
            const SizedBox(height: FeederSpacing.xl),
            Text('You\'re all set!',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: FeederSpacing.xs),
            Text('${_name.text.trim()} is connected and ready.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            if (_status != null) ...[
              const SizedBox(height: FeederSpacing.lg),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: FeederSpacing.sm,
                runSpacing: FeederSpacing.sm,
                children: [
                  _capChip(Icons.memory_rounded, _status!.mode),
                  if (_status!.hasHailo) _capChip(Icons.bolt_rounded, 'Hailo AI'),
                  if (_status!.has3d) _capChip(Icons.view_in_ar_rounded, '3D camera'),
                  if (_status!.hasIndividualId) _capChip(Icons.fingerprint_rounded, 'Re‑ID'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _capChip(IconData icon, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(icon, size: 16, color: scheme.onSecondaryContainer),
      label: Text(label),
      backgroundColor: scheme.secondaryContainer,
      labelStyle: TextStyle(color: scheme.onSecondaryContainer, fontWeight: FontWeight.w600, fontSize: 12),
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
    );
  }
}

// ===========================================================================
// Pieces
// ===========================================================================
class _Radar extends StatelessWidget {
  final AnimationController controller;
  final bool active;
  const _Radar({required this.controller, required this.active});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 140, height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (active)
            for (final delay in const [0.0, 0.5])
              AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  final t = (controller.value + delay) % 1.0;
                  return Container(
                    width: 60 + t * 80,
                    height: 60 + t * 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: (1 - t) * 0.4),
                        width: 2,
                      ),
                    ),
                  );
                },
              ),
          Container(
            width: 96, height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary]),
            ),
            child: Icon(active ? Icons.wifi_find_rounded : Icons.check_rounded,
                size: 44, color: scheme.onPrimary),
          ),
        ],
      ),
    );
  }
}

class _PresenceChip extends StatelessWidget {
  final bool detected;
  const _PresenceChip({required this.detected});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = detected ? Colors.green : scheme.onSurfaceVariant;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: FeederSpacing.md, vertical: FeederSpacing.sm),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(detected ? Icons.bluetooth_connected_rounded : Icons.bluetooth_searching_rounded,
                size: 16, color: color),
            const SizedBox(width: FeederSpacing.sm),
            Flexible(
              child: Text(
                detected ? 'Feeder detected nearby' : 'Looking for your feeder over Bluetooth…',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: scheme.onSurface, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Checklist extends StatelessWidget {
  final List<String> items;
  const _Checklist({required this.items});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FeederCard(
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: FeederSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text('${i + 1}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: scheme.onPrimaryContainer)),
                ),
                const SizedBox(width: FeederSpacing.md),
                Expanded(
                  child: Text(items[i], style: Theme.of(context).textTheme.bodyMedium),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FoundCard extends StatelessWidget {
  final String ip;
  final FeederStatus? status;
  final VoidCallback onConnect;
  const _FoundCard({required this.ip, this.status, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FeederCard(
      color: scheme.primaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_rounded, color: scheme.onPrimaryContainer),
              const SizedBox(width: FeederSpacing.sm),
              Expanded(
                child: Text('Feeder found on your network',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.bold, color: scheme.onPrimaryContainer)),
              ),
            ],
          ),
          const SizedBox(height: FeederSpacing.xs),
          Text('$ip${status != null ? ' • ${status!.mode}' : ''}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onPrimaryContainer)),
          const SizedBox(height: FeederSpacing.md),
          FilledButton.icon(
            onPressed: onConnect,
            icon: const Icon(Icons.link_rounded),
            label: const Text('Connect'),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: FeederSpacing.card,
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(FeederSpacing.radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
          const SizedBox(width: FeederSpacing.sm),
          Expanded(
            child: Text(message, style: TextStyle(color: scheme.onErrorContainer, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
