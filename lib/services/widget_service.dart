import 'dart:convert';
import 'dart:io';
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

    try {
      await _channel.invokeMethod('updateWidget', {
        'appGroupId': _appGroupId,
        'key': 'widgetData',
        'data': jsonEncode(data),
      });
    } catch (e) {
      // Widget update failed - not critical
      print('Widget update failed: $e');
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
