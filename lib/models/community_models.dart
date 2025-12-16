import 'package:cloud_firestore/cloud_firestore.dart';

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

  factory CommunityPost.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return CommunityPost(
      id: doc.id,
      author: data['author']?.toString() ?? 'anon',
      caption: data['caption']?.toString() ?? '',
      imageUrl: data['image_url']?.toString(),
      createdAt: (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      timeOfDayTag: data['time_of_day']?.toString() ?? 'daytime',
      model: data['model']?.toString() ?? 'Ornimetrics O1 feeder',
      weather: data['weather'] is Map
          ? WeatherSnapshot(
              condition: data['weather']['condition']?.toString() ?? 'Unknown',
              temperatureC: (data['weather']['temperatureC'] as num?)?.toDouble() ?? 0,
              humidity: (data['weather']['humidity'] as num?)?.toDouble() ?? 0,
              precipitationChance: (data['weather']['precipitationChance'] as num?)?.toDouble(),
              windKph: (data['weather']['windKph'] as num?)?.toDouble(),
              pressureMb: (data['weather']['pressureMb'] as num?)?.toDouble(),
              uvIndex: (data['weather']['uvIndex'] as num?)?.toDouble(),
              visibilityKm: (data['weather']['visibilityKm'] as num?)?.toDouble(),
              dewPointC: (data['weather']['dewPointC'] as num?)?.toDouble(),
              fetchedAt: DateTime.tryParse(data['weather']['fetchedAt']?.toString() ?? '') ?? DateTime.now(),
              isRaining: data['weather']['isRaining'] == true,
              isSnowing: data['weather']['isSnowing'] == true,
              isHailing: data['weather']['isHailing'] == true,
              feelsLikeC: (data['weather']['feelsLikeC'] as num?)?.toDouble(),
              precipitationMm: (data['weather']['precipitationMm'] as num?)?.toDouble(),
            )
          : null,
      sensors: SensorSnapshot.fromMap(data['sensors'] as Map<String, dynamic>?),
    );
  }

  Map<String, dynamic> toMap() => {
        'author': author,
        'caption': caption,
        'image_url': imageUrl,
        'created_at': FieldValue.serverTimestamp(),
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
