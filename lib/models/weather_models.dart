class WeatherSnapshot {
  final String condition;
  final double temperatureC;
  final double? precipitationChance;
  final double humidity;
  final double? windKph;
  final double? pressureMb;
  final double? uvIndex;
  final double? visibilityKm;
  final double? dewPointC;
  final DateTime fetchedAt;
  final bool isRaining;
  final bool isSnowing;
  final bool isHailing;
  final double? feelsLikeC;
  final double? precipitationMm;

  WeatherSnapshot({
    required this.condition,
    required this.temperatureC,
    required this.humidity,
    this.precipitationChance,
    this.windKph,
    this.pressureMb,
    this.uvIndex,
    this.visibilityKm,
    this.dewPointC,
    required this.fetchedAt,
    this.isRaining = false,
    this.isSnowing = false,
    this.isHailing = false,
    this.feelsLikeC,
    this.precipitationMm,
  });

  bool get isWet => isRaining || isSnowing || isHailing || (precipitationChance ?? 0) >= 0.35;

  Map<String, dynamic> toMap() => {
        'condition': condition,
        'temperatureC': temperatureC,
        'precipitationChance': precipitationChance,
        'humidity': humidity,
        'windKph': windKph,
        'pressureMb': pressureMb,
        'uvIndex': uvIndex,
        'visibilityKm': visibilityKm,
        'dewPointC': dewPointC,
        'fetchedAt': fetchedAt.toIso8601String(),
        'isRaining': isRaining,
        'isSnowing': isSnowing,
        'isHailing': isHailing,
        'feelsLikeC': feelsLikeC,
        'precipitationMm': precipitationMm,
      };

  factory WeatherSnapshot.fromMap(Map<String, dynamic> map) {
    return WeatherSnapshot(
      condition: map['condition']?.toString() ?? 'Unknown',
      temperatureC: (map['temperatureC'] as num?)?.toDouble() ?? 0,
      precipitationChance: (map['precipitationChance'] as num?)?.toDouble(),
      humidity: (map['humidity'] as num?)?.toDouble() ?? 0,
      windKph: (map['windKph'] as num?)?.toDouble(),
      pressureMb: (map['pressureMb'] as num?)?.toDouble(),
      uvIndex: (map['uvIndex'] as num?)?.toDouble(),
      visibilityKm: (map['visibilityKm'] as num?)?.toDouble(),
      dewPointC: (map['dewPointC'] as num?)?.toDouble(),
      fetchedAt: DateTime.tryParse(map['fetchedAt']?.toString() ?? '') ?? DateTime.now(),
      isRaining: map['isRaining'] == true,
      isSnowing: map['isSnowing'] == true,
      isHailing: map['isHailing'] == true,
      feelsLikeC: (map['feelsLikeC'] as num?)?.toDouble(),
      precipitationMm: (map['precipitationMm'] as num?)?.toDouble(),
    );
  }
}
