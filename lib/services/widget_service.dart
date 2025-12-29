import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service for updating iOS home screen widgets with bird detection data
class WidgetService {
  WidgetService._();
  static final WidgetService instance = WidgetService._();

  static const _channel = MethodChannel('com.ornimetrics.app/widget');
  static const _appGroupId = 'group.com.ornimetrics.app';

  /// Update the widget with current detection data
  Future<void> updateWidget({
    required int totalDetections,
    required int uniqueSpecies,
    required String lastDetection,
    required String topSpecies,
  }) async {
    if (!Platform.isIOS) return;

    final data = {
      'totalDetections': totalDetections,
      'uniqueSpecies': uniqueSpecies,
      'lastDetection': lastDetection,
      'topSpecies': topSpecies,
      'lastUpdated': DateTime.now().toIso8601String(),
    };

    debugPrint('WidgetService: Sending update - $totalDetections detections, $uniqueSpecies species');
    debugPrint('WidgetService: Data = ${jsonEncode(data)}');

    try {
      final result = await _channel.invokeMethod('updateWidget', {
        'appGroupId': _appGroupId,
        'key': 'widgetData',
        'data': jsonEncode(data),
      });
      debugPrint('WidgetService: Update result = $result');
    } catch (e) {
      debugPrint('WidgetService: Update FAILED - $e');
    }
  }

  /// Request widget refresh (iOS 14+)
  Future<void> refreshWidget() async {
    if (!Platform.isIOS) return;

    try {
      await _channel.invokeMethod('refreshWidget');
    } catch (e) {
      print('Widget refresh failed: $e');
    }
  }
}
