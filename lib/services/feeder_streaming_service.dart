/// Video streaming service for Ornimetrics OS feeder
/// Handles MJPEG and RTSP stream management

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const Duration kStreamTimeout = Duration(seconds: 30);
const Duration kReconnectDelay = Duration(seconds: 3);
const int kMaxReconnectAttempts = 5;

/// Stream type enum
enum StreamType { mjpeg, rtsp }

/// Stream state enum
enum StreamState { disconnected, connecting, connected, error, reconnecting }

/// MJPEG frame data
class MjpegFrame {
  final Uint8List data;
  final DateTime timestamp;
  final int size;

  const MjpegFrame({
    required this.data,
    required this.timestamp,
    required this.size,
  });
}

/// Streaming service for MJPEG video feeds
class FeederStreamingService {
  static final FeederStreamingService instance = FeederStreamingService._();
  FeederStreamingService._();

  // State notifiers
  final ValueNotifier<StreamState> state = ValueNotifier(StreamState.disconnected);
  final ValueNotifier<MjpegFrame?> currentFrame = ValueNotifier(null);
  final ValueNotifier<String?> errorMessage = ValueNotifier(null);
  final ValueNotifier<double> fps = ValueNotifier(0.0);
  final ValueNotifier<int> frameCount = ValueNotifier(0);
  final ValueNotifier<int> bytesReceived = ValueNotifier(0);

  // Internal state
  String? _streamUrl;
  StreamSubscription<List<int>>? _streamSubscription;
  http.Client? _httpClient;
  Timer? _fpsTimer;
  int _frameCountSinceLastTick = 0;
  int _reconnectAttempts = 0;
  bool _shouldReconnect = true;

  // Buffer for MJPEG boundary detection
  final List<int> _buffer = [];
  static const List<int> _jpegStart = [0xFF, 0xD8];
  static const List<int> _jpegEnd = [0xFF, 0xD9];

  /// Start streaming from URL
  Future<void> startStream(String url) async {
    if (state.value == StreamState.connected || state.value == StreamState.connecting) {
      if (_streamUrl == url) return;
      await stopStream();
    }

    _streamUrl = url;
    _shouldReconnect = true;
    _reconnectAttempts = 0;
    await _connect();
  }

  /// Connect to the stream
  Future<void> _connect() async {
    if (_streamUrl == null) return;

    try {
      state.value = StreamState.connecting;
      errorMessage.value = null;

      _httpClient?.close();
      _httpClient = http.Client();

      final request = http.Request('GET', Uri.parse(_streamUrl!));
      final response = await _httpClient!.send(request).timeout(kStreamTimeout);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      state.value = StreamState.connected;
      _reconnectAttempts = 0;
      _startFpsCounter();

      _streamSubscription = response.stream.listen(
        _processStreamData,
        onError: _handleStreamError,
        onDone: _handleStreamDone,
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('FeederStreamingService: Connection error: $e');
      errorMessage.value = 'Failed to connect: ${_formatError(e)}';
      state.value = StreamState.error;
      _scheduleReconnect();
    }
  }

  /// Process incoming stream data
  void _processStreamData(List<int> data) {
    bytesReceived.value += data.length;
    _buffer.addAll(data);

    // Find JPEG frames in buffer
    while (true) {
      final startIndex = _findSequence(_buffer, _jpegStart);
      if (startIndex == -1) {
        // No start marker found, clear buffer up to last byte (might be partial marker)
        if (_buffer.length > 1) {
          _buffer.removeRange(0, _buffer.length - 1);
        }
        break;
      }

      final endIndex = _findSequence(_buffer, _jpegEnd, startIndex + 2);
      if (endIndex == -1) {
        // No end marker yet, wait for more data
        // Remove data before start marker
        if (startIndex > 0) {
          _buffer.removeRange(0, startIndex);
        }
        break;
      }

      // Extract JPEG frame
      final frameEnd = endIndex + 2;
      final frameData = Uint8List.fromList(_buffer.sublist(startIndex, frameEnd));
      _buffer.removeRange(0, frameEnd);

      // Update state
      _frameCountSinceLastTick++;
      frameCount.value++;
      currentFrame.value = MjpegFrame(
        data: frameData,
        timestamp: DateTime.now(),
        size: frameData.length,
      );
    }

    // Prevent buffer from growing too large
    if (_buffer.length > 1024 * 1024) {
      _buffer.clear();
      debugPrint('FeederStreamingService: Buffer cleared (overflow protection)');
    }
  }

  /// Find sequence in buffer
  int _findSequence(List<int> buffer, List<int> sequence, [int startFrom = 0]) {
    outer:
    for (int i = startFrom; i <= buffer.length - sequence.length; i++) {
      for (int j = 0; j < sequence.length; j++) {
        if (buffer[i + j] != sequence[j]) {
          continue outer;
        }
      }
      return i;
    }
    return -1;
  }

  /// Handle stream error
  void _handleStreamError(dynamic error) {
    debugPrint('FeederStreamingService: Stream error: $error');
    errorMessage.value = 'Stream error: ${_formatError(error)}';
    state.value = StreamState.error;
    _scheduleReconnect();
  }

  /// Handle stream completion
  void _handleStreamDone() {
    debugPrint('FeederStreamingService: Stream ended');
    if (_shouldReconnect && state.value != StreamState.disconnected) {
      state.value = StreamState.error;
      _scheduleReconnect();
    }
  }

  /// Schedule reconnection attempt
  void _scheduleReconnect() {
    if (!_shouldReconnect) return;
    if (_reconnectAttempts >= kMaxReconnectAttempts) {
      errorMessage.value = 'Max reconnection attempts reached';
      state.value = StreamState.disconnected;
      return;
    }

    _reconnectAttempts++;
    state.value = StreamState.reconnecting;
    debugPrint('FeederStreamingService: Reconnecting (attempt $_reconnectAttempts)');

    Future.delayed(kReconnectDelay, () {
      if (_shouldReconnect && state.value == StreamState.reconnecting) {
        _connect();
      }
    });
  }

  /// Start FPS counter
  void _startFpsCounter() {
    _stopFpsCounter();
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      fps.value = _frameCountSinceLastTick.toDouble();
      _frameCountSinceLastTick = 0;
    });
  }

  /// Stop FPS counter
  void _stopFpsCounter() {
    _fpsTimer?.cancel();
    _fpsTimer = null;
    fps.value = 0;
  }

  /// Stop streaming
  Future<void> stopStream() async {
    _shouldReconnect = false;
    _stopFpsCounter();

    await _streamSubscription?.cancel();
    _streamSubscription = null;

    _httpClient?.close();
    _httpClient = null;

    _buffer.clear();
    _streamUrl = null;
    state.value = StreamState.disconnected;
    currentFrame.value = null;
    errorMessage.value = null;
    _reconnectAttempts = 0;
  }

  /// Toggle stream (pause/resume)
  void toggleStream() {
    if (state.value == StreamState.connected) {
      _shouldReconnect = false;
      _streamSubscription?.pause();
      _stopFpsCounter();
    } else if (_streamSubscription?.isPaused == true) {
      _shouldReconnect = true;
      _streamSubscription?.resume();
      _startFpsCounter();
    }
  }

  /// Check if currently streaming
  bool get isStreaming => state.value == StreamState.connected;

  /// Get current stream URL
  String? get streamUrl => _streamUrl;

  /// Format error for display
  String _formatError(dynamic error) {
    final message = error.toString();
    if (message.contains('SocketException')) {
      return 'Cannot reach feeder';
    }
    if (message.contains('TimeoutException')) {
      return 'Connection timed out';
    }
    return message.split(':').last.trim();
  }

  /// Clear all state
  void clear() {
    stopStream();
    frameCount.value = 0;
    bytesReceived.value = 0;
  }

  /// Dispose of resources
  void dispose() {
    stopStream();
    state.dispose();
    currentFrame.dispose();
    errorMessage.dispose();
    fps.dispose();
    frameCount.dispose();
    bytesReceived.dispose();
  }
}

/// MJPEG image widget helper
class MjpegStreamController {
  final FeederStreamingService _service = FeederStreamingService.instance;

  MjpegStreamController();

  /// Start the stream
  Future<void> start(String url) => _service.startStream(url);

  /// Stop the stream
  Future<void> stop() => _service.stopStream();

  /// Toggle pause/resume
  void toggle() => _service.toggleStream();

  /// Get frame stream
  ValueNotifier<MjpegFrame?> get frameNotifier => _service.currentFrame;

  /// Get state notifier
  ValueNotifier<StreamState> get stateNotifier => _service.state;

  /// Get FPS notifier
  ValueNotifier<double> get fpsNotifier => _service.fps;

  /// Get error notifier
  ValueNotifier<String?> get errorNotifier => _service.errorMessage;

  /// Current state
  StreamState get state => _service.state.value;

  /// Is connected
  bool get isConnected => _service.state.value == StreamState.connected;
}
