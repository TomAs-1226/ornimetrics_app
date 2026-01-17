/// Feeder Tab Screen - Main hub for Ornimetrics OS integration
/// Shows paired device status, live stats, quick actions, and navigation

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/feeder_models.dart';
import '../services/feeder_api_service.dart';
import '../services/feeder_bluetooth_service.dart';
import '../services/feeder_firebase_service.dart';
import 'feeder_setup_screen.dart';
import 'feeder_stream_screen.dart';
import 'feeder_individuals_screen.dart';
import 'feeder_detections_screen.dart';

class FeederTabScreen extends StatefulWidget {
  const FeederTabScreen({super.key});

  @override
  State<FeederTabScreen> createState() => _FeederTabScreenState();
}

class _FeederTabScreenState extends State<FeederTabScreen>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  final _bluetoothService = FeederBluetoothService.instance;
  final _apiService = FeederApiService.instance;
  final _firebaseService = FeederFirebaseService.instance;

  late AnimationController _refreshAnimController;
  bool _isRefreshing = false;
  bool _initialLoadDone = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _refreshAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _loadPairedDevice();
  }

  Future<void> _loadPairedDevice() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await _bluetoothService.loadCurrentDevice(user.uid);
      final device = _bluetoothService.currentDevice.value;
      if (device != null) {
        _apiService.setFromPairedFeeder(device);
        _firebaseService.initialize(userId: user.uid, deviceId: device.deviceId);
        await _refreshData();
        _firebaseService.startListening();
        _apiService.startPolling();
      }
    }
    setState(() => _initialLoadDone = true);
  }

  Future<void> _refreshData() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    _refreshAnimController.repeat();

    try {
      await _apiService.refreshAll();
    } catch (e) {
      debugPrint('FeederTabScreen: Refresh error: $e');
    } finally {
      _refreshAnimController.stop();
      _refreshAnimController.reset();
      setState(() => _isRefreshing = false);
    }
  }

  Future<void> _addNewFeeder() async {
    HapticFeedback.selectionClick();
    final result = await Navigator.of(context).push<PairedFeeder>(
      MaterialPageRoute(builder: (_) => const FeederSetupScreen()),
    );

    if (result != null && mounted) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _firebaseService.initialize(userId: user.uid, deviceId: result.deviceId);
        _firebaseService.startListening();
        _apiService.startPolling();
      }
      setState(() {});
      _refreshData();
    }
  }

  Future<void> _removeFeeder(PairedFeeder feeder) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Feeder?'),
        content: Text('Are you sure you want to remove "${feeder.feederName}"? '
            'You can add it again later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _bluetoothService.removePairedDevice(feeder.deviceId);
      _apiService.clear();
      _firebaseService.clear();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _refreshAnimController.dispose();
    _apiService.stopPolling();
    _firebaseService.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (!_initialLoadDone) {
      return const Center(child: CircularProgressIndicator());
    }

    return ValueListenableBuilder<PairedFeeder?>(
      valueListenable: _bluetoothService.currentDevice,
      builder: (context, device, _) {
        if (device == null) {
          return _buildNoDeviceState(colorScheme);
        }

        return RefreshIndicator(
          onRefresh: _refreshData,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildDeviceCard(device, colorScheme),
                      const SizedBox(height: 16),
                      _buildConnectionStatus(colorScheme),
                      const SizedBox(height: 16),
                      _buildQuickStats(colorScheme),
                      const SizedBox(height: 16),
                      _buildQuickActions(colorScheme),
                      const SizedBox(height: 16),
                      _buildRecentActivity(colorScheme),
                      const SizedBox(height: 16),
                      _buildTrainingStatus(colorScheme),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNoDeviceState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.rss_feed,
                size: 60,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'No Feeder Connected',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Connect your Ornimetrics OS feeder to see live bird detections, '
              'individual tracking, and more.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _addNewFeeder,
              icon: const Icon(Icons.add),
              label: const Text('Add Feeder'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceCard(PairedFeeder device, ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.rss_feed,
                size: 28,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.feederName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'v${device.version} • ${device.staticIp}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                switch (value) {
                  case 'refresh':
                    _refreshData();
                    break;
                  case 'remove':
                    _removeFeeder(device);
                    break;
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'refresh',
                  child: ListTile(
                    leading: Icon(Icons.refresh),
                    title: Text('Refresh'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'remove',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline, color: colorScheme.error),
                    title: Text('Remove', style: TextStyle(color: colorScheme.error)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStatus(ColorScheme colorScheme) {
    return ValueListenableBuilder<bool>(
      valueListenable: _apiService.isConnected,
      builder: (context, isConnected, _) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isConnected
                ? colorScheme.primaryContainer.withOpacity(0.5)
                : colorScheme.errorContainer.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isConnected
                  ? colorScheme.primary.withOpacity(0.3)
                  : colorScheme.error.withOpacity(0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isConnected ? Colors.green : Colors.red,
                  boxShadow: [
                    BoxShadow(
                      color: (isConnected ? Colors.green : Colors.red).withOpacity(0.5),
                      blurRadius: 6,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isConnected ? 'Connected to feeder' : 'Not connected',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: isConnected
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onErrorContainer,
                  ),
                ),
              ),
              if (!isConnected)
                TextButton(
                  onPressed: _refreshData,
                  child: const Text('Retry'),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickStats(ColorScheme colorScheme) {
    return ValueListenableBuilder<FeederStats?>(
      valueListenable: _apiService.stats,
      builder: (context, stats, _) {
        return Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.flutter_dash,
                label: 'Today',
                value: '${stats?.detectionsToday ?? 0}',
                colorScheme: colorScheme,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.category,
                label: 'Species',
                value: '${stats?.speciesCount ?? 0}',
                colorScheme: colorScheme,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.person_pin,
                label: 'Individuals',
                value: '${stats?.uniqueIndividuals ?? 0}',
                colorScheme: colorScheme,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQuickActions(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.videocam,
                label: 'Live Stream',
                colorScheme: colorScheme,
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FeederStreamScreen()),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionButton(
                icon: Icons.pets,
                label: 'Individuals',
                colorScheme: colorScheme,
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FeederIndividualsScreen()),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionButton(
                icon: Icons.history,
                label: 'History',
                colorScheme: colorScheme,
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FeederDetectionsScreen()),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecentActivity(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Recent Activity',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FeederDetectionsScreen()),
                );
              },
              child: const Text('See All'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<List<FeederDetection>>(
          valueListenable: _apiService.recentDetections,
          builder: (context, detections, _) {
            if (detections.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.hourglass_empty,
                          size: 48,
                          color: colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No recent detections',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return Card(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: detections.take(5).length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final detection = detections[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: colorScheme.primaryContainer,
                      child: Icon(
                        Icons.flutter_dash,
                        color: colorScheme.onPrimaryContainer,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      detection.formattedSpecies,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      _formatTimestamp(detection.timestamp),
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: detection.confidenceColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${(detection.confidence * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: detection.confidenceColor,
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTrainingStatus(ColorScheme colorScheme) {
    return ValueListenableBuilder<TrainingStatus?>(
      valueListenable: _apiService.trainingStatus,
      builder: (context, training, _) {
        if (training == null || !training.trainingEnabled) {
          return const SizedBox.shrink();
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.model_training,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Model Training',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    if (training.isTraining)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Training',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (training.isTraining) ...[
                  LinearProgressIndicator(
                    value: training.trainingProgress.progress,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    training.trainingProgress.message,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ] else ...[
                  Text(
                    training.datasetReady
                        ? 'Dataset ready for training'
                        : 'Collecting training data...',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (training.lastTrainingTime != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Last trained: ${_formatTimestamp(training.lastTrainingTime!)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme colorScheme;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: colorScheme.primary, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            children: [
              Icon(icon, color: colorScheme.primary, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
