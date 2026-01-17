/// Live Stream Screen for Ornimetrics OS
/// Displays MJPEG video feed from the feeder with controls and overlays

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/feeder_models.dart';
import '../services/feeder_api_service.dart';
import '../services/feeder_bluetooth_service.dart';
import '../services/feeder_streaming_service.dart';

class FeederStreamScreen extends StatefulWidget {
  const FeederStreamScreen({super.key});

  @override
  State<FeederStreamScreen> createState() => _FeederStreamScreenState();
}

class _FeederStreamScreenState extends State<FeederStreamScreen>
    with TickerProviderStateMixin {
  final _streamingService = FeederStreamingService.instance;
  final _apiService = FeederApiService.instance;
  final _bluetoothService = FeederBluetoothService.instance;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _showControls = true;
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _fadeController.forward();
    _startStream();
  }

  void _startStream() {
    final device = _bluetoothService.currentDevice.value;
    if (device != null) {
      _streamingService.startStream(device.mjpegStreamUrl);
    }
  }

  void _toggleFullscreen() {
    HapticFeedback.selectionClick();
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _fadeController.forward();
    } else {
      _fadeController.reverse();
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _streamingService.stopStream();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _isFullscreen
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
              title: const Text(
                'Live Stream',
                style: TextStyle(color: Colors.white),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.fullscreen),
                  onPressed: _toggleFullscreen,
                ),
              ],
            ),
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video stream
            _buildVideoPlayer(colorScheme),

            // Overlay controls
            if (_showControls) ...[
              // Top gradient
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Container(
                    height: 120,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black54, Colors.transparent],
                      ),
                    ),
                  ),
                ),
              ),

              // Bottom controls
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: _buildBottomControls(colorScheme),
                ),
              ),

              // Live indicator
              Positioned(
                top: _isFullscreen ? 24 : 100,
                left: 16,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: _buildLiveIndicator(),
                ),
              ),

              // Stats overlay
              Positioned(
                top: _isFullscreen ? 24 : 100,
                right: 16,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: _buildStatsOverlay(colorScheme),
                ),
              ),
            ],

            // Fullscreen exit button
            if (_isFullscreen)
              Positioned(
                top: 24,
                right: 24,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: IconButton(
                    icon: const Icon(Icons.fullscreen_exit, color: Colors.white, size: 32),
                    onPressed: _toggleFullscreen,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlayer(ColorScheme colorScheme) {
    return ValueListenableBuilder<StreamState>(
      valueListenable: _streamingService.state,
      builder: (context, state, _) {
        if (state == StreamState.connecting || state == StreamState.reconnecting) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 16),
                Text(
                  state == StreamState.reconnecting
                      ? 'Reconnecting...'
                      : 'Connecting...',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          );
        }

        if (state == StreamState.error) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 64),
                const SizedBox(height: 16),
                ValueListenableBuilder<String?>(
                  valueListenable: _streamingService.errorMessage,
                  builder: (context, error, _) {
                    return Text(
                      error ?? 'Stream error',
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    );
                  },
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _startStream,
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  label: const Text('Retry', style: TextStyle(color: Colors.white)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white54),
                  ),
                ),
              ],
            ),
          );
        }

        if (state == StreamState.disconnected) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.videocam_off, color: Colors.white54, size: 64),
                const SizedBox(height: 16),
                const Text(
                  'Stream stopped',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _startStream,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Stream'),
                ),
              ],
            ),
          );
        }

        // Connected - show video
        return ValueListenableBuilder<MjpegFrame?>(
          valueListenable: _streamingService.currentFrame,
          builder: (context, frame, _) {
            if (frame == null) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            }

            return Center(
              child: Image.memory(
                frame.data,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (context, error, stack) {
                  return const Icon(
                    Icons.broken_image,
                    color: Colors.white54,
                    size: 64,
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLiveIndicator() {
    return ValueListenableBuilder<StreamState>(
      valueListenable: _streamingService.state,
      builder: (context, state, _) {
        if (state != StreamState.connected) {
          return const SizedBox.shrink();
        }

        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.5, end: 1.0),
          duration: const Duration(milliseconds: 800),
          builder: (context, value, child) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.9),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.5 * value),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'LIVE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatsOverlay(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // FPS
          ValueListenableBuilder<double>(
            valueListenable: _streamingService.fps,
            builder: (context, fps, _) {
              return Text(
                '${fps.toStringAsFixed(1)} FPS',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          // Frame count
          ValueListenableBuilder<int>(
            valueListenable: _streamingService.frameCount,
            builder: (context, count, _) {
              return Text(
                '$count frames',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          // Detection status
          ValueListenableBuilder<FeederSystemStatus?>(
            valueListenable: _apiService.systemStatus,
            builder: (context, status, _) {
              final isActive = status?.detection.active ?? false;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive ? Colors.green : Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isActive ? 'Detecting' : 'Idle',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls(ColorScheme colorScheme) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).padding.bottom + 16,
        top: 16,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Screenshot button (placeholder)
          _ControlButton(
            icon: Icons.camera_alt,
            label: 'Capture',
            onTap: () {
              HapticFeedback.lightImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Screenshot saved'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          // Play/Pause
          ValueListenableBuilder<StreamState>(
            valueListenable: _streamingService.state,
            builder: (context, state, _) {
              final isPlaying = state == StreamState.connected;
              return _ControlButton(
                icon: isPlaying ? Icons.pause : Icons.play_arrow,
                label: isPlaying ? 'Pause' : 'Play',
                isPrimary: true,
                onTap: () {
                  HapticFeedback.selectionClick();
                  if (isPlaying) {
                    _streamingService.stopStream();
                  } else {
                    _startStream();
                  }
                },
              );
            },
          ),
          // Fullscreen
          _ControlButton(
            icon: _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
            label: _isFullscreen ? 'Exit' : 'Fullscreen',
            onTap: _toggleFullscreen,
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: isPrimary ? 64 : 48,
            height: isPrimary ? 64 : 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isPrimary ? Colors.white : Colors.white24,
            ),
            child: Icon(
              icon,
              color: isPrimary ? Colors.black : Colors.white,
              size: isPrimary ? 32 : 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
