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
  });
}
