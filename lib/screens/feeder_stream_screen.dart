/// Live MJPEG stream with a real-time identification overlay.
///
/// The video comes from `/video_feed` (decoded by [FeederStreamingService]).
/// The overlay reads `/api/current` (kept fresh by the home hub's poller) to
/// show the species, individual and any welfare flag for the bird in frame.

library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

import '../models/feeder_models.dart';
import '../services/feeder_api_service.dart';
import '../services/feeder_bluetooth_service.dart';
import '../services/feeder_streaming_service.dart';
import '../widgets/feeder_ui.dart';

class FeederStreamScreen extends StatefulWidget {
  const FeederStreamScreen({super.key});

  @override
  State<FeederStreamScreen> createState() => _FeederStreamScreenState();
}

class _FeederStreamScreenState extends State<FeederStreamScreen>
    with TickerProviderStateMixin {
  final _streamingService = FeederStreamingService.instance;
  final _api = FeederApiService.instance;
  final _bluetoothService = FeederBluetoothService.instance;

  late final AnimationController _fadeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  )..forward();
  late final Animation<double> _fadeAnimation =
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut);

  bool _showControls = true;
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    _startStream();
    // Make sure the overlay has fresh `current` data even if opened directly.
    _api.startCurrentPolling();
  }

  void _startStream() {
    final url = _api.mjpegStreamUrl ?? _bluetoothService.currentDevice.value?.mjpegStreamUrl;
    if (url != null) _streamingService.startStream(url);
  }

  void _toggleFullscreen() {
    HapticFeedback.selectionClick();
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    _showControls ? _fadeController.forward() : _fadeController.reverse();
  }

  Future<void> _capture() async {
    final frame = _streamingService.currentFrame.value;
    if (frame == null) {
      _snack('No frame to capture yet');
      return;
    }
    HapticFeedback.lightImpact();
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/ornimetrics_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await file.writeAsBytes(frame.data);
      await Share.shareXFiles([XFile(file.path)], text: 'From my Ornimetrics feeder');
    } catch (e) {
      _snack('Couldn\'t share the capture');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _streamingService.stopStream();
    // Leave `current` polling running — the home hub owns its lifecycle.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _isFullscreen
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
              title: const Text('Live view', style: TextStyle(color: Colors.white)),
              actions: [
                IconButton(
                  tooltip: 'Fullscreen',
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
            _buildVideoPlayer(),
            if (_showControls) ...[
              Positioned(
                top: 0, left: 0, right: 0,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Container(
                    height: 140,
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
              Positioned(
                top: _isFullscreen ? 24 : 96, left: 16,
                child: FadeTransition(opacity: _fadeAnimation, child: _LiveBadge(stream: _streamingService)),
              ),
              Positioned(
                top: _isFullscreen ? 24 : 96, right: 16,
                child: FadeTransition(opacity: _fadeAnimation, child: _StatsOverlay(stream: _streamingService)),
              ),
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _IdentificationOverlay(api: _api),
                      _buildBottomControls(),
                    ],
                  ),
                ),
              ),
            ],
            if (_isFullscreen)
              Positioned(
                top: 24, right: 24,
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

  Widget _buildVideoPlayer() {
    return ValueListenableBuilder<StreamState>(
      valueListenable: _streamingService.state,
      builder: (context, state, _) {
        if (state == StreamState.connecting || state == StreamState.reconnecting) {
          return _centered(
            const CircularProgressIndicator(color: Colors.white),
            state == StreamState.reconnecting ? 'Reconnecting…' : 'Connecting…',
          );
        }
        if (state == StreamState.error) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 56),
                const SizedBox(height: 16),
                ValueListenableBuilder<String?>(
                  valueListenable: _streamingService.errorMessage,
                  builder: (context, error, _) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(error ?? 'Stream error',
                        style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _startStream,
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  label: const Text('Retry', style: TextStyle(color: Colors.white)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white54)),
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
                const Icon(Icons.videocam_off, color: Colors.white54, size: 56),
                const SizedBox(height: 16),
                const Text('Stream paused', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _startStream,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start stream'),
                ),
              ],
            ),
          );
        }
        return ValueListenableBuilder<MjpegFrame?>(
          valueListenable: _streamingService.currentFrame,
          builder: (context, frame, _) {
            if (frame == null) {
              return _centered(const CircularProgressIndicator(color: Colors.white), 'Buffering…');
            }
            return Center(
              child: Image.memory(
                frame.data,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.broken_image, color: Colors.white54, size: 56),
              ),
            );
          },
        );
      },
    );
  }

  Widget _centered(Widget indicator, String label) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [indicator, const SizedBox(height: 16), Text(label, style: const TextStyle(color: Colors.white70))],
        ),
      );

  Widget _buildBottomControls() {
    return Container(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 16,
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
          _ControlButton(icon: Icons.ios_share, label: 'Share', onTap: _capture),
          ValueListenableBuilder<StreamState>(
            valueListenable: _streamingService.state,
            builder: (context, state, _) {
              final playing = state == StreamState.connected;
              return _ControlButton(
                icon: playing ? Icons.pause : Icons.play_arrow,
                label: playing ? 'Pause' : 'Play',
                isPrimary: true,
                onTap: () {
                  HapticFeedback.selectionClick();
                  playing ? _streamingService.stopStream() : _startStream();
                },
              );
            },
          ),
          _ControlButton(
            icon: _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
            label: _isFullscreen ? 'Exit' : 'Full',
            onTap: _toggleFullscreen,
          ),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  final FeederStreamingService stream;
  const _LiveBadge({required this.stream});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<StreamState>(
      valueListenable: stream.state,
      builder: (context, state, _) {
        if (state != StreamState.connected) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(8)),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, color: Colors.white, size: 8),
              SizedBox(width: 6),
              Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
        );
      },
    );
  }
}

class _StatsOverlay extends StatelessWidget {
  final FeederStreamingService stream;
  const _StatsOverlay({required this.stream});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
      child: ValueListenableBuilder<double>(
        valueListenable: stream.fps,
        builder: (context, fps, _) => Text('${fps.toStringAsFixed(0)} fps',
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
      ),
    );
  }
}

/// The bottom identification card driven by /api/current.
class _IdentificationOverlay extends StatelessWidget {
  final FeederApiService api;
  const _IdentificationOverlay({required this.api});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CurrentState?>(
      valueListenable: api.current,
      builder: (context, cur, _) {
        final hasBird = cur?.hasBird ?? false;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SizeTransition(sizeFactor: anim, child: child),
          ),
          child: !hasBird
              ? const SizedBox(key: ValueKey('none'), width: double.infinity)
              : Container(
                  key: ValueKey(cur!.species),
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(FeederSpacing.radius),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    children: [
                      SpeciesAvatar(name: cur.displaySpecies, size: 44, distressed: cur.welfare.distressed),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(cur.displaySpecies,
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                            if (cur.displayIndividual != null)
                              Text(cur.displayIndividual!,
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
                          ],
                        ),
                      ),
                      if (cur.welfare.distressed)
                        const DistressChip()
                      else if (cur.speciesConfidence != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
                          child: Text('${((cur.speciesConfidence ?? 0) * 100).round()}%',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                ),
        );
      },
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
            width: isPrimary ? 60 : 46,
            height: isPrimary ? 60 : 46,
            decoration: BoxDecoration(shape: BoxShape.circle, color: isPrimary ? Colors.white : Colors.white24),
            child: Icon(icon, color: isPrimary ? Colors.black : Colors.white, size: isPrimary ? 30 : 22),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}
