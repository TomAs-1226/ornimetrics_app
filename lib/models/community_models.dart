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

  factory SensorSnapshot.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const SensorSnapshot();
    return SensorSnapshot(
      lowFood: map['lowFood'] == true,
      clogged: map['clogged'] == true,
      cleaningDue: map['cleaningDue'] == true,
    );
  }
}

class CommunityPost {
  final String id;
  final String author;
  final String caption;
  final String? imageUrl;
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
    this.imageUrl,
    this.weather,
  });

  factory CommunityPost.fromRealtime(String id, Map data) {
    final normalized = Map<String, dynamic>.from(data);
    return CommunityPost(
      id: id,
      author: normalized['author']?.toString() ?? 'anon',
      caption: normalized['caption']?.toString() ?? '',
      imageUrl: normalized['image_url']?.toString(),
      createdAt: _parseTimestamp(normalized['created_at']),
      timeOfDayTag: normalized['time_of_day']?.toString() ?? 'daytime',
      model: normalized['model']?.toString() ?? 'Ornimetrics O1 feeder',
      weather: normalized['weather'] is Map
          ? WeatherSnapshot(
              condition: normalized['weather']['condition']?.toString() ?? 'Unknown',
              temperatureC: (normalized['weather']['temperatureC'] as num?)?.toDouble() ?? 0,
              humidity: (normalized['weather']['humidity'] as num?)?.toDouble() ?? 0,
              precipitationChance: (normalized['weather']['precipitationChance'] as num?)?.toDouble(),
              windKph: (normalized['weather']['windKph'] as num?)?.toDouble(),
              pressureMb: (normalized['weather']['pressureMb'] as num?)?.toDouble(),
              uvIndex: (normalized['weather']['uvIndex'] as num?)?.toDouble(),
              visibilityKm: (normalized['weather']['visibilityKm'] as num?)?.toDouble(),
              dewPointC: (normalized['weather']['dewPointC'] as num?)?.toDouble(),
              fetchedAt: DateTime.tryParse(normalized['weather']['fetchedAt']?.toString() ?? '') ?? DateTime.now(),
              isRaining: normalized['weather']['isRaining'] == true,
              isSnowing: normalized['weather']['isSnowing'] == true,
              isHailing: normalized['weather']['isHailing'] == true,
              feelsLikeC: (normalized['weather']['feelsLikeC'] as num?)?.toDouble(),
              precipitationMm: (normalized['weather']['precipitationMm'] as num?)?.toDouble(),
            )
          : null,
      sensors: SensorSnapshot.fromMap(normalized['sensors'] as Map<String, dynamic>?),
    );
  }

  Map<String, dynamic> toMap() => {
        'author': author,
        'caption': caption,
        'image_url': imageUrl,
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
