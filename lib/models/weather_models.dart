class WeatherSnapshot {
  final String condition;
  final double temperatureC;
  final double? precipitationChance;
  final double humidity;
  final DateTime fetchedAt;

  WeatherSnapshot({
    required this.condition,
    required this.temperatureC,
    required this.humidity,
    this.precipitationChance,
    required this.fetchedAt,
  });
}
