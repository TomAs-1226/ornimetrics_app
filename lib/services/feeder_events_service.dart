/// Server-Sent Events client for the feeder's `GET /api/events` stream.
///
/// This is the recommended realtime path (push, not poll): it delivers
/// `hello`, `sighting` and `welfare_alert` events. Sightings flow into the
/// activity feed and welfare alerts fire a local notification. The stream
/// auto-reconnects after a dropped connection (the server sends `retry: 3000`).

library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/feeder_models.dart';
import 'feeder_api_service.dart';
import 'notifications_service.dart';

enum SseState { idle, connecting, open, reconnecting }

class FeederEventsService {
  static final FeederEventsService instance = FeederEventsService._();
  FeederEventsService._();

  final ValueNotifier<SseState> state = ValueNotifier(SseState.idle);

  /// Latest sighting pushed over SSE — handy for live "just spotted" UI.
  final ValueNotifier<Sighting?> lastSighting = ValueNotifier(null);

  /// Latest welfare alert pushed over SSE.
  final ValueNotifier<WelfareAlert?> lastWelfareAlert = ValueNotifier(null);

  final FeederApiService _api = FeederApiService.instance;

  String? _baseUrl;
  http.Client? _client;
  StreamSubscription<String>? _sub;
  Timer? _reconnectTimer;
  bool _shouldRun = false;
  Duration _retry = const Duration(seconds: 3);

  // SSE frame accumulators.
  String? _eventType;
  final StringBuffer _data = StringBuffer();

  /// Open the stream against [baseUrl] (e.g. `http://192.168.0.86:5000`).
  void start(String baseUrl) {
    final normalized =
        baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    if (_shouldRun && _baseUrl == normalized) return;
    _baseUrl = normalized;
    _shouldRun = true;
    _connect();
  }

  Future<void> _connect() async {
    if (!_shouldRun || _baseUrl == null) return;
    _reconnectTimer?.cancel();
    state.value =
        state.value == SseState.idle ? SseState.connecting : SseState.reconnecting;

    try {
      _client?.close();
      _client = http.Client();
      final request = http.Request('GET', Uri.parse('$_baseUrl/api/events'));
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Cache-Control'] = 'no-cache';

      final response = await _client!.send(request);
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      state.value = SseState.open;

      _sub = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _onLine,
            onError: _onErrorOrDone,
            onDone: _onErrorOrDone,
            cancelOnError: true,
          );
    } catch (e) {
      debugPrint('FeederEventsService: connect error $e');
      _scheduleReconnect();
    }
  }

  void _onLine(String line) {
    // Blank line dispatches the accumulated event.
    if (line.isEmpty) {
      _dispatch();
      return;
    }
    // Comment / keepalive.
    if (line.startsWith(':')) return;

    final idx = line.indexOf(':');
    final field = idx == -1 ? line : line.substring(0, idx);
    var value = idx == -1 ? '' : line.substring(idx + 1);
    if (value.startsWith(' ')) value = value.substring(1);

    switch (field) {
      case 'event':
        _eventType = value;
        break;
      case 'data':
        if (_data.isNotEmpty) _data.write('\n');
        _data.write(value);
        break;
      case 'retry':
        final ms = int.tryParse(value);
        if (ms != null) _retry = Duration(milliseconds: ms);
        break;
      default:
        break;
    }
  }

  void _dispatch() {
    final raw = _data.toString();
    _data.clear();
    final namedType = _eventType;
    _eventType = null;
    if (raw.isEmpty) return;

    Map<String, dynamic> json;
    try {
      json = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = (json['type'] as String?) ?? namedType ?? '';
    switch (type) {
      case 'hello':
        break;
      case 'sighting':
        final s = Sighting.fromJson(json);
        lastSighting.value = s;
        _api.ingestSighting(s);
        break;
      case 'welfare_alert':
        final a = WelfareAlert.fromJson(json);
        lastWelfareAlert.value = a;
        _api.ingestWelfareAlert(a);
        _notifyWelfare(a);
        break;
      default:
        break;
    }
  }

  void _notifyWelfare(WelfareAlert a) {
    final who = a.individual != null ? '${a.displayName} (${a.individual})' : a.displayName;
    NotificationsService.instance.showWelfareAlert(
      title: 'Welfare check: $who',
      body: 'A bird at your feeder looks like it may need a closer look. '
          'This is a screening flag, not a diagnosis — tap to review.',
    );
  }

  void _onErrorOrDone([Object? error]) {
    if (error != null) debugPrint('FeederEventsService: stream error $error');
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _sub?.cancel();
    _sub = null;
    _client?.close();
    _client = null;
    if (!_shouldRun) {
      state.value = SseState.idle;
      return;
    }
    state.value = SseState.reconnecting;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_retry, _connect);
  }

  void stop() {
    _shouldRun = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _sub?.cancel();
    _sub = null;
    _client?.close();
    _client = null;
    _data.clear();
    _eventType = null;
    state.value = SseState.idle;
  }
}
