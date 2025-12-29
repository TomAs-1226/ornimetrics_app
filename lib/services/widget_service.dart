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

  /// Update the widget with comprehensive detection data
  Future<void> updateWidget({
    // Core stats
    required int totalDetections,
    required int uniqueSpecies,
    required String lastDetection,
    required String topSpecies,
    // Diversity metrics (optional with defaults)
    double rarityScore = 0,
    double diversityIndex = 0,
    double commonSpeciesRatio = 0,
    // Activity metrics
    List<int>? hourlyActivity,
    int peakHour = 12,
    int activeHours = 0,
    // Trends
    double weeklyTrend = 0,
    double monthlyTrend = 0,
    String trendingSpecies = '—',
    String decliningSpecies = '—',
    // Community
    int communityTotal = 0,
    int userRank = 0,
    int communityMembers = 0,
    int sharedSightings = 0,
  }) async {
    if (!Platform.isIOS) return;

    final data = {
      // Core stats
      'totalDetections': totalDetections,
      'uniqueSpecies': uniqueSpecies,
      'lastDetection': lastDetection,
      'topSpecies': topSpecies,
      'lastUpdated': DateTime.now().toIso8601String(),
      // Diversity metrics
      'rarityScore': rarityScore,
      'diversityIndex': diversityIndex,
      'commonSpeciesRatio': commonSpeciesRatio,
      // Activity metrics
      'hourlyActivity': hourlyActivity ?? List.filled(24, 0),
      'peakHour': peakHour,
      'activeHours': activeHours,
      // Trends
      'weeklyTrend': weeklyTrend,
      'monthlyTrend': monthlyTrend,
      'trendingSpecies': trendingSpecies,
      'decliningSpecies': decliningSpecies,
      // Community
      'communityTotal': communityTotal,
      'userRank': userRank,
      'communityMembers': communityMembers,
      'sharedSightings': sharedSightings,
    };

    debugPrint('WidgetService: Sending update - $totalDetections detections, $uniqueSpecies species');

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
      debugPrint('Widget refresh failed: $e');
    }
  }
}
