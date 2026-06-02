/// Feeder home hub — the main Ornimetrics screen.
///
/// Drives off the real device contract (docs/API.md): a live "now" card from
/// `/api/current`, a digest from `/api/summary`, a realtime activity feed from
/// the `/api/events` SSE stream, and a welfare banner. History is pulled once
/// and refreshed on pull-to-refresh; the SSE stream keeps the feed live.

library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/feeder_models.dart';
import '../services/feeder_api_service.dart';
import '../services/feeder_bluetooth_service.dart';
import '../services/feeder_events_service.dart';
import '../services/feeder_firebase_service.dart';
import '../widgets/feeder_ui.dart';
import 'feeder_about_screen.dart';
import 'feeder_settings_screen.dart';
import 'feeder_setup_screen.dart';
import 'feeder_stream_screen.dart';
import 'feeder_individuals_screen.dart';
import 'feeder_activity_screen.dart';
import 'feeder_welfare_screen.dart';
import 'feeder_audio_screen.dart';

class FeederTabScreen extends StatefulWidget {
  const FeederTabScreen({super.key});

  @override
  State<FeederTabScreen> createState() => _FeederTabScreenState();
}

class _FeederTabScreenState extends State<FeederTabScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final _bluetoothService = FeederBluetoothService.instance;
  final _api = FeederApiService.instance;
  final _events = FeederEventsService.instance;
  final _firebaseService = FeederFirebaseService.instance;

  bool _initialLoadDone = false;
  bool _hasLoggedInUser = false;
  bool _live = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAccountStatus();
    _loadPairedDevice();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause the live channels in the background; resume on return.
    if (state == AppLifecycleState.resumed) {
      if (_bluetoothService.currentDevice.value != null) _startLive();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _stopLive();
    }
  }

  Future<void> _checkAccountStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (mounted) setState(() => _hasLoggedInUser = user != null);
  }

  Future<void> _loadPairedDevice() async {
    final user = FirebaseAuth.instance.currentUser;
    // Manual/local feeders are stored under 'local' so they survive without login.
    await _bluetoothService.loadCurrentDevice(user?.uid ?? 'local');
    final device = _bluetoothService.currentDevice.value;
    if (device != null) {
      _api.setFromPairedFeeder(device);
      if (user != null) {
        _firebaseService.initialize(userId: user.uid, deviceId: device.deviceId);
        _firebaseService.startListening();
      }
      _activate(device);
    }
    if (mounted) setState(() => _initialLoadDone = true);
  }

  /// Bring a device online: demo feeders serve canned data; real ones start the
  /// live channels.
  void _activate(PairedFeeder device) {
    if (FeederApiService.isDemoFeeder(device)) {
      _api.enableDemo();
      _live = true; // mark active so we don't also start network channels
    } else {
      _startLive();
    }
  }

  void _startLive() {
    if (_live || !_api.hasDevice || _api.isDemoMode) return;
    _live = true;
    _api.refreshAll();
    _api.startCurrentPolling();
    if (_api.baseUrl != null) _events.start(_api.baseUrl!);
  }

  Future<void> _connectByIp() async {
    HapticFeedback.selectionClick();
    final result = await showDialog<({String ip, String name})>(
      context: context,
      builder: (_) => const _ConnectByIpDialog(),
    );
    if (result == null || !mounted) return;

    final baseUrl = 'http://${result.ip}:5000';
    // Probe before saving so we only pair with something that answers.
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text('Looking for a feeder at ${result.ip}…')));
    final status = await _api.probe(baseUrl);
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    if (status == null) {
      messenger.showSnackBar(SnackBar(
        content: Text('No feeder answered at ${result.ip}:5000. Check the IP and that you\'re on the same Wi‑Fi.'),
      ));
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'local';
    final feeder = PairedFeeder(
      deviceId: 'manual-${result.ip}',
      deviceName: 'Ornimetrics',
      feederName: result.name.isEmpty ? 'My Feeder' : result.name,
      staticIp: result.ip,
      version: status.backend,
      pairedAt: DateTime.now(),
      userId: uid,
    );
    await _bluetoothService.saveAndSetCurrent(feeder);
    _api.setFromPairedFeeder(feeder);
    _live = false;
    _startLive();
    if (mounted) setState(() {});
  }

  void _stopLive() {
    if (!_live) return;
    _live = false;
    _api.stopCurrentPolling();
    _events.stop();
  }

  Future<void> _refresh() => _api.refreshAll();

  Future<void> _addNewFeeder() async {
    HapticFeedback.selectionClick();
    if (!_hasLoggedInUser) {
      await _showAccountRequiredDialog();
      return;
    }
    final result = await Navigator.of(context).push<PairedFeeder>(
      MaterialPageRoute(builder: (_) => const FeederSetupScreen()),
    );
    if (result != null && mounted) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _firebaseService.initialize(userId: user.uid, deviceId: result.deviceId);
        _firebaseService.startListening();
      }
      _activate(result);
      setState(() {});
    }
  }

  Future<void> _showAccountRequiredDialog() async {
    final scheme = Theme.of(context).colorScheme;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.account_circle, size: 36, color: scheme.primary),
        title: const Text('Sign in required'),
        content: const Text(
          'To set up your Ornimetrics feeder, sign in to your account first. '
          'You can do that from the Settings tab.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in from Settings to continue.')),
      );
    }
  }


  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopLive();
    _firebaseService.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_initialLoadDone) {
      return const Center(child: CircularProgressIndicator());
    }
    return ValueListenableBuilder<PairedFeeder?>(
      valueListenable: _bluetoothService.currentDevice,
      builder: (context, device, _) {
        if (device == null) {
          return _NoDeviceState(
            onAdd: _addNewFeeder,
            onManual: _connectByIp,
            signedIn: _hasLoggedInUser,
          );
        }
        return FeederHomeView(
          device: device,
          onRefresh: _refresh,
          onRemove: _stopLive, // post-removal cleanup; FeederSettings does the unpair
        );
      },
    );
  }
}

// ===========================================================================
// No-device state
// ===========================================================================
class _NoDeviceState extends StatelessWidget {
  final VoidCallback onAdd;
  final VoidCallback onManual;
  final bool signedIn;
  const _NoDeviceState({
    required this.onAdd,
    required this.onManual,
    required this.signedIn,
  });

  @override
  Widget build(BuildContext context) {
    return FeederEmptyState(
      icon: Icons.sensors_rounded,
      title: 'No feeder connected',
      message:
          'Connect your Ornimetrics feeder to see live bird detections, individual '
          'profiles, welfare alerts and more.',
      action: Column(
        children: [
          FilledButton.icon(
            onPressed: onManual,
            icon: const Icon(Icons.wifi_rounded),
            label: const Text('Connect by IP address'),
          ),
          const SizedBox(height: FeederSpacing.sm),
          TextButton.icon(
            onPressed: onAdd,
            icon: Icon(signedIn ? Icons.bluetooth_rounded : Icons.login, size: 18),
            label: Text(signedIn ? 'Set up over Bluetooth' : 'Sign in for Bluetooth setup'),
          ),
        ],
      ),
    );
  }
}

/// Dialog to enter a feeder's LAN IP. Returns (ip, name) or null.
class _ConnectByIpDialog extends StatefulWidget {
  const _ConnectByIpDialog();

  @override
  State<_ConnectByIpDialog> createState() => _ConnectByIpDialogState();
}

class _ConnectByIpDialogState extends State<_ConnectByIpDialog> {
  final _ip = TextEditingController(text: '192.168.0.86');
  final _name = TextEditingController(text: 'My Feeder');

  static final _ipRegex = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');

  @override
  void dispose() {
    _ip.dispose();
    _name.dispose();
    super.dispose();
  }

  String? _validate(String raw) {
    final v = raw.trim();
    if (!_ipRegex.hasMatch(v)) return 'Enter a valid IP like 192.168.0.86';
    if (v.split('.').any((p) => (int.tryParse(p) ?? 999) > 255)) {
      return 'Each part must be 0–255';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(Icons.wifi_rounded, color: scheme.primary),
      title: const Text('Connect by IP'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your feeder is a device on your Wi‑Fi. Enter its static IP address '
            '(shown during setup, e.g. 192.168.0.86). Your phone must be on the '
            'same network.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: FeederSpacing.lg),
          TextField(
            controller: _ip,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'IP address',
              prefixIcon: Icon(Icons.lan_outlined),
            ),
          ),
          const SizedBox(height: FeederSpacing.md),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Feeder name',
              prefixIcon: Icon(Icons.label_outline),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final err = _validate(_ip.text);
            if (err != null) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
              return;
            }
            Navigator.pop(context, (ip: _ip.text.trim(), name: _name.text.trim()));
          },
          child: const Text('Connect'),
        ),
      ],
    );
  }
}

// ===========================================================================
// Connected view
// ===========================================================================
/// The connected-feeder home body. Public so it can be widget-tested directly
/// (it has no Firebase dependency — only the API service).
class FeederHomeView extends StatelessWidget {
  final PairedFeeder device;
  final Future<void> Function() onRefresh;
  final VoidCallback onRemove;

  FeederHomeView({
    super.key,
    required this.device,
    required this.onRefresh,
    required this.onRemove,
  });

  final _api = FeederApiService.instance;

  void _open(BuildContext context, Widget screen) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Offline banner above last-known data.
        ValueListenableBuilder<FeederConnection>(
          valueListenable: _api.connection,
          builder: (context, conn, _) {
            if (conn != FeederConnection.offline) return const SizedBox.shrink();
            return ValueListenableBuilder<DateTime?>(
              valueListenable: _api.lastUpdated,
              builder: (context, ts, __) => OfflineBanner(lastUpdated: ts),
            );
          },
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: FeederSpacing.screen,
              children: [
                _DeviceHeader(device: device, onRemove: onRemove, onRefresh: onRefresh),
                const SizedBox(height: FeederSpacing.lg),
                _LiveNowCard(onTapLive: () => _open(context, const FeederStreamScreen())),
                const SizedBox(height: FeederSpacing.lg),
                _DigestStats(onWelfare: () => _open(context, const FeederWelfareScreen())),
                const SizedBox(height: FeederSpacing.lg),
                _WelfareBanner(onTap: () => _open(context, const FeederWelfareScreen())),
                _QuickActions(
                  onLive: () => _open(context, const FeederStreamScreen()),
                  onActivity: () => _open(context, const FeederActivityScreen()),
                  onIndividuals: () => _open(context, const FeederIndividualsScreen()),
                  onHeard: () => _open(context, const FeederAudioScreen()),
                ),
                const SizedBox(height: FeederSpacing.lg),
                const _TodayDigest(),
                const SizedBox(height: FeederSpacing.lg),
                _TopSpecies(onSeeAll: () => _open(context, const FeederActivityScreen(initialTab: 1))),
                const SizedBox(height: FeederSpacing.lg),
                _RecentActivity(onSeeAll: () => _open(context, const FeederActivityScreen())),
                const SizedBox(height: FeederSpacing.xl),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DeviceHeader extends StatelessWidget {
  final PairedFeeder device;
  final VoidCallback onRemove;
  final Future<void> Function() onRefresh;
  const _DeviceHeader({required this.device, required this.onRemove, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FeederCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => FeederAboutScreen(device: device)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.sensors_rounded, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: FeederSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.feederName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                _ConnectionLine(),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'about') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => FeederAboutScreen(device: device)),
                );
              }
              if (v == 'settings') {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => FeederSettingsScreen(device: device, onRemoved: onRemove),
                ));
              }
              if (v == 'refresh') onRefresh();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'about', child: ListTile(leading: Icon(Icons.info_outline), title: Text('About this feeder'), contentPadding: EdgeInsets.zero)),
              PopupMenuItem(value: 'settings', child: ListTile(leading: Icon(Icons.settings_outlined), title: Text('Feeder settings'), contentPadding: EdgeInsets.zero)),
              PopupMenuItem(value: 'refresh', child: ListTile(leading: Icon(Icons.refresh), title: Text('Refresh'), contentPadding: EdgeInsets.zero)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConnectionLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final api = FeederApiService.instance;
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<FeederConnection>(
      valueListenable: api.connection,
      builder: (context, conn, _) {
        final online = conn == FeederConnection.online;
        final connecting = conn == FeederConnection.connecting || conn == FeederConnection.unknown;
        final color = online ? Colors.green : (connecting ? scheme.outline : scheme.error);
        final label = online ? 'Online' : (connecting ? 'Connecting…' : 'Offline');
        return Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(width: 8),
            ValueListenableBuilder<FeederStatus?>(
              valueListenable: api.status,
              builder: (context, st, _) => st == null
                  ? const SizedBox.shrink()
                  : Flexible(
                      child: Text('• ${st.mode}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// The live "now" card driven by /api/current.
class _LiveNowCard extends StatelessWidget {
  final VoidCallback onTapLive;
  const _LiveNowCard({required this.onTapLive});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final api = FeederApiService.instance;
    return ValueListenableBuilder<CurrentState?>(
      valueListenable: api.current,
      builder: (context, cur, _) {
        final hasBird = cur?.hasBird ?? false;
        final distressed = cur?.welfare.distressed ?? false;
        return FeederCard(
          onTap: onTapLive,
          color: scheme.surfaceContainerHigh,
          child: Row(
            children: [
              _LiveThumb(api: api),
              const SizedBox(width: FeederSpacing.lg),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: hasBird
                      ? Column(
                          key: ValueKey(cur!.species),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _LiveDot(),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text('AT THE FEEDER NOW',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 11, letterSpacing: 0.5, fontWeight: FontWeight.w700, color: scheme.primary)),
                                ),
                              ],
                            ),
                            const SizedBox(height: FeederSpacing.sm),
                            Text(cur.displaySpecies,
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            if (cur.displayIndividual != null)
                              Text(cur.displayIndividual!,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                            const SizedBox(height: FeederSpacing.sm),
                            Wrap(
                              spacing: FeederSpacing.sm,
                              runSpacing: FeederSpacing.xs,
                              children: [
                                ConfidencePill(confidence: cur.speciesConfidence),
                                if (distressed) const DistressChip(),
                              ],
                            ),
                          ],
                        )
                      : Column(
                          key: const ValueKey('idle'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Watching for birds',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                            const SizedBox(height: FeederSpacing.xs),
                            Text('Tap to open the live view',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                          ],
                        ),
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        );
      },
    );
  }
}

class _LiveThumb extends StatelessWidget {
  final FeederApiService api;
  const _LiveThumb({required this.api});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = api.snapshotUrl;
    return ValueListenableBuilder<CurrentState?>(
      valueListenable: api.current,
      builder: (context, cur, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(FeederSpacing.radiusSm),
          child: SizedBox(
            width: 84,
            height: 84,
            child: url == null
                ? _thumbFallback(scheme)
                : Image.network(
                    // Bust cache as the snapshot changes.
                    '$url?t=${cur?.ts.toStringAsFixed(0) ?? '0'}',
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => _thumbFallback(scheme),
                    loadingBuilder: (context, child, progress) =>
                        progress == null ? child : _thumbFallback(scheme),
                  ),
          ),
        );
      },
    );
  }

  Widget _thumbFallback(ColorScheme scheme) => Container(
        color: scheme.surfaceContainerHighest,
        child: Icon(Icons.videocam_outlined, color: scheme.onSurfaceVariant),
      );
}

class _LiveDot extends StatefulWidget {
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) {
      return Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.red));
    }
    return FadeTransition(
      opacity: Tween(begin: 0.4, end: 1.0).animate(_c),
      child: Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.red)),
    );
  }
}

class _DigestStats extends StatelessWidget {
  final VoidCallback onWelfare;
  const _DigestStats({required this.onWelfare});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final api = FeederApiService.instance;
    return ValueListenableBuilder<FeederSummary?>(
      valueListenable: api.summary,
      builder: (context, s, _) {
        if (s == null) {
          return Row(
            children: const [
              Expanded(child: SkeletonBox(height: 92, borderRadius: BorderRadius.all(Radius.circular(16)))),
              SizedBox(width: FeederSpacing.md),
              Expanded(child: SkeletonBox(height: 92, borderRadius: BorderRadius.all(Radius.circular(16)))),
              SizedBox(width: FeederSpacing.md),
              Expanded(child: SkeletonBox(height: 92, borderRadius: BorderRadius.all(Radius.circular(16)))),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: FeederStatTile(icon: Icons.category_rounded, label: 'Species', value: s.speciesCount)),
            const SizedBox(width: FeederSpacing.md),
            Expanded(child: FeederStatTile(icon: Icons.pets_rounded, label: 'Regulars', value: s.individualsCount)),
            const SizedBox(width: FeederSpacing.md),
            Expanded(
              child: GestureDetector(
                onTap: s.welfareAlerts24h > 0 ? onWelfare : null,
                child: FeederStatTile(
                  icon: Icons.health_and_safety_outlined,
                  label: 'Welfare 24h',
                  value: s.welfareAlerts24h,
                  accent: s.welfareAlerts24h > 0 ? scheme.error : null,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WelfareBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _WelfareBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final api = FeederApiService.instance;
    return ValueListenableBuilder<List<WelfareAlert>>(
      valueListenable: api.welfareAlerts,
      builder: (context, alerts, _) {
        if (alerts.isEmpty) return const SizedBox.shrink();
        final a = alerts.first;
        return Padding(
          padding: const EdgeInsets.only(bottom: FeederSpacing.lg),
          child: Material(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(FeederSpacing.radius),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: FeederSpacing.card,
                child: Row(
                  children: [
                    Icon(Icons.health_and_safety_outlined, color: scheme.onErrorContainer),
                    const SizedBox(width: FeederSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(WelfareCopy.gentleHeadline,
                              style: TextStyle(fontWeight: FontWeight.bold, color: scheme.onErrorContainer)),
                          const SizedBox(height: 2),
                          Text('${a.displayName} • ${relativeTime(a.dateTime)} — screening flag, tap to review',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: scheme.onErrorContainer)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: scheme.onErrorContainer),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _QuickActions extends StatelessWidget {
  final VoidCallback onLive, onActivity, onIndividuals, onHeard;
  const _QuickActions({
    required this.onLive,
    required this.onActivity,
    required this.onIndividuals,
    required this.onHeard,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      (_QA(Icons.videocam_rounded, 'Live', onLive)),
      (_QA(Icons.timeline_rounded, 'Activity', onActivity)),
      (_QA(Icons.pets_rounded, 'Regulars', onIndividuals)),
      (_QA(Icons.graphic_eq_rounded, 'Heard', onHeard)),
    ];
    return Row(
      children: [
        for (int i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: FeederSpacing.md),
          Expanded(child: items[i]),
        ],
      ],
    );
  }
}

class _QA extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QA(this.icon, this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FeederCard(
      onTap: onTap,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(vertical: FeederSpacing.lg),
      child: Column(
        children: [
          Icon(icon, color: scheme.primary, size: 26),
          const SizedBox(height: FeederSpacing.sm),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _TopSpecies extends StatelessWidget {
  final VoidCallback onSeeAll;
  const _TopSpecies({required this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final api = FeederApiService.instance;
    return ValueListenableBuilder<FeederSummary?>(
      valueListenable: api.summary,
      builder: (context, s, _) {
        final top = s?.topSpecies ?? const [];
        if (top.isEmpty) return const SizedBox.shrink();
        final maxCount = top.map((e) => e.count).fold<int>(1, (a, b) => a > b ? a : b);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FeederSectionHeader(
              icon: Icons.leaderboard_rounded,
              title: 'Top species',
              trailing: TextButton(onPressed: onSeeAll, child: const Text('Life list')),
            ),
            FeederCard(
              child: Column(
                children: [
                  for (int i = 0; i < top.length; i++) ...[
                    if (i > 0) const SizedBox(height: FeederSpacing.md),
                    Row(
                      children: [
                        SpeciesAvatar(name: top[i].display, size: 34),
                        const SizedBox(width: FeederSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(top[i].display,
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: top[i].count / maxCount,
                                  minHeight: 6,
                                  backgroundColor: scheme.surfaceContainerHighest,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: FeederSpacing.md),
                        Text('${top[i].count}',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RecentActivity extends StatelessWidget {
  final VoidCallback onSeeAll;
  const _RecentActivity({required this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    final api = FeederApiService.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FeederSectionHeader(
          icon: Icons.timeline_rounded,
          title: 'Recent activity',
          trailing: TextButton(onPressed: onSeeAll, child: const Text('See all')),
        ),
        ValueListenableBuilder<List<Sighting>>(
          valueListenable: api.sightings,
          builder: (context, list, _) {
            if (list.isEmpty) {
              return const FeederCard(
                child: SizedBox(
                  height: 80,
                  child: Center(child: Text('No visits yet — birds will show up here')),
                ),
              );
            }
            final items = list.take(5).toList();
            return FeederCard(
              padding: const EdgeInsets.symmetric(vertical: FeederSpacing.sm),
              child: Column(
                children: [
                  for (int i = 0; i < items.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 64),
                    SightingTile(sighting: items[i]),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// A "Today" digest computed from the recent sightings feed: visits so far
/// today, the busiest hour, and how many species / individuals showed up.
class _TodayDigest extends StatelessWidget {
  const _TodayDigest();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final api = FeederApiService.instance;
    return ValueListenableBuilder<List<Sighting>>(
      valueListenable: api.sightings,
      builder: (context, all, _) {
        final now = DateTime.now();
        final today = all.where((s) {
          final d = s.dateTime;
          return d.year == now.year && d.month == now.month && d.day == now.day;
        }).toList();
        if (today.isEmpty) return const SizedBox.shrink();

        final species = today.map((s) => s.display).toSet().length;
        final individuals =
            today.where((s) => s.individual != null).map((s) => s.individual).toSet().length;

        // Busiest hour by visit count.
        final byHour = <int, int>{};
        for (final s in today) {
          byHour[s.dateTime.hour] = (byHour[s.dateTime.hour] ?? 0) + 1;
        }
        int? peakHour;
        var peak = 0;
        byHour.forEach((h, c) {
          if (c > peak) {
            peak = c;
            peakHour = h;
          }
        });
        String hourLabel(int h) {
          final ampm = h < 12 ? 'am' : 'pm';
          final h12 = h % 12 == 0 ? 12 : h % 12;
          return '$h12$ampm';
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const FeederSectionHeader(icon: Icons.today_rounded, title: 'Today'),
            FeederCard(
              child: Row(
                children: [
                  Expanded(child: _TodayMetric(value: '${today.length}', label: 'visits', icon: Icons.flutter_dash_rounded)),
                  _todayDivider(scheme),
                  Expanded(child: _TodayMetric(value: '$species', label: 'species', icon: Icons.category_rounded)),
                  _todayDivider(scheme),
                  Expanded(
                    child: _TodayMetric(
                      value: peakHour != null ? hourLabel(peakHour!) : '—',
                      label: 'busiest',
                      icon: Icons.schedule_rounded,
                    ),
                  ),
                  if (individuals > 0) ...[
                    _todayDivider(scheme),
                    Expanded(child: _TodayMetric(value: '$individuals', label: 'regulars', icon: Icons.pets_rounded)),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _todayDivider(ColorScheme scheme) =>
      Container(width: 1, height: 40, color: scheme.outlineVariant);
}

class _TodayMetric extends StatelessWidget {
  final String value, label;
  final IconData icon;
  const _TodayMetric({required this.value, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              maxLines: 1,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 2),
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}
