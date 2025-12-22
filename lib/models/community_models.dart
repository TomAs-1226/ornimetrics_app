import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_database/firebase_database.dart';

import 'weather_models.dart';

class SensorSnapshot {
  final bool lowFood;
  final bool clogged;
  final bool cleaningDue;

  const SensorSnapshot({this.lowFood = false, this.clogged = false, this.cleaningDue = false});

  Map<String, dynamic> toMap() => {
    'lowFood': lowFood,
    'clogged': clogged,
    'cleaningDue': cleaningDue,
  };

  factory SensorSnapshot.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const SensorSnapshot();
    final normalized = Map<String, dynamic>.from(map.map((k, v) => MapEntry(k.toString(), v)));
    return SensorSnapshot(
      lowFood: normalized['lowFood'] == true,
      clogged: normalized['clogged'] == true,
      cleaningDue: normalized['cleaningDue'] == true,
    );
  }
}

class CommunityPost {
  final String id;
  final String author;
  final String caption;
  final String? imageUrl;
  final Uint8List? imageData;
  final DateTime createdAt;
  final String timeOfDayTag;
  final WeatherSnapshot? weather;
  final SensorSnapshot sensors;
  final String model;

  CommunityPost({
    required this.id,
    required this.author,
    required this.caption,
    required this.createdAt,
    required this.timeOfDayTag,
    required this.sensors,
    required this.model,
    this.imageData,
    this.imageUrl,
    this.weather,
  });

  factory CommunityPost.fromRealtime(String id, Map data) {
    final normalized = <String, dynamic>{};
    data.forEach((k, v) => normalized[k.toString()] = v);
    final weatherMap = normalized['weather'] is Map
        ? Map<String, dynamic>.from((normalized['weather'] as Map).map((k, v) => MapEntry(k.toString(), v)))
        : null;
    final sensorsMap = normalized['sensors'] is Map
        ? Map<String, dynamic>.from((normalized['sensors'] as Map).map((k, v) => MapEntry(k.toString(), v)))
        : null;
    return CommunityPost(
      id: id,
      author: normalized['author']?.toString() ?? 'anon',
      caption: normalized['caption']?.toString() ?? '',
      imageUrl: normalized['image_url']?.toString(),
      imageData: _decodeInlineImage(normalized['image_base64']?.toString()),
      createdAt: _parseTimestamp(normalized['created_at']),
      timeOfDayTag: normalized['time_of_day']?.toString() ?? 'daytime',
      model: normalized['model']?.toString() ?? 'Ornimetrics O1 feeder',
      weather: weatherMap != null
          ? WeatherSnapshot(
        condition: weatherMap['condition']?.toString() ?? 'Unknown',
        temperatureC: (weatherMap['temperatureC'] as num?)?.toDouble() ?? 0,
        humidity: (weatherMap['humidity'] as num?)?.toDouble() ?? 0,
        precipitationChance: (weatherMap['precipitationChance'] as num?)?.toDouble(),
        windKph: (weatherMap['windKph'] as num?)?.toDouble(),
        pressureMb: (weatherMap['pressureMb'] as num?)?.toDouble(),
        uvIndex: (weatherMap['uvIndex'] as num?)?.toDouble(),
        visibilityKm: (weatherMap['visibilityKm'] as num?)?.toDouble(),
        dewPointC: (weatherMap['dewPointC'] as num?)?.toDouble(),
        fetchedAt: DateTime.tryParse(weatherMap['fetchedAt']?.toString() ?? '') ?? DateTime.now(),
        isRaining: weatherMap['isRaining'] == true,
        isSnowing: weatherMap['isSnowing'] == true,
        isHailing: weatherMap['isHailing'] == true,
        feelsLikeC: (weatherMap['feelsLikeC'] as num?)?.toDouble(),
        precipitationMm: (weatherMap['precipitationMm'] as num?)?.toDouble(),
      )
          : null,
      sensors: SensorSnapshot.fromMap(sensorsMap),
    );
  }

  Map<String, dynamic> toMap() => {
    'author': author,
    'caption': caption,
    'image_url': imageUrl,
    if (imageData != null) 'image_base64': 'data:image/jpeg;base64,${base64Encode(imageData!)}',
    'created_at': ServerValue.timestamp,
    'time_of_day': timeOfDayTag,
    'model': model,
    'weather': weather != null
        ? {
      'condition': weather!.condition,
      'temperatureC': weather!.temperatureC,
      'humidity': weather!.humidity,
      'precipitationChance': weather!.precipitationChance,
      'windKph': weather!.windKph,
      'pressureMb': weather!.pressureMb,
      'uvIndex': weather!.uvIndex,
      'visibilityKm': weather!.visibilityKm,
      'dewPointC': weather!.dewPointC,
      'fetchedAt': weather!.fetchedAt.toIso8601String(),
      'isRaining': weather!.isRaining,
      'isSnowing': weather!.isSnowing,
      'isHailing': weather!.isHailing,
      'feelsLikeC': weather!.feelsLikeC,
      'precipitationMm': weather!.precipitationMm,
    }
        : null,
    'sensors': sensors.toMap(),
  };
}

DateTime _parseTimestamp(dynamic v) {
  if (v is int) {
    return DateTime.fromMillisecondsSinceEpoch(v);
  }
  if (v is double) {
    return DateTime.fromMillisecondsSinceEpoch(v.round());
  }
  if (v is String) {
    return DateTime.tryParse(v) ?? DateTime.now();
  }
  return DateTime.now();
}

Uint8List? _decodeInlineImage(String? data) {
  if (data == null || data.isEmpty) return null;
  try {
    final cleaned = data.startsWith('data:') ? data.split(',').last : data;
    return base64Decode(cleaned);
  } catch (_) {
    return null;
  }
}
