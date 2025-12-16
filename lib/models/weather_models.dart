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
}
