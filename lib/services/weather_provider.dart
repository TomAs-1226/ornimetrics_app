import '../models/weather_models.dart';

abstract class WeatherProvider {
  Future<WeatherSnapshot> fetchCurrent();
}

class MockWeatherProvider implements WeatherProvider {
  @override
  Future<WeatherSnapshot> fetchCurrent() async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return WeatherSnapshot(
      condition: 'Partly cloudy',
      temperatureC: 18.5,
      humidity: 62,
      precipitationChance: 0.2,
      windKph: 9.4,
      pressureMb: 1014,
      uvIndex: 3.2,
      visibilityKm: 12.5,
      dewPointC: 10.2,
      fetchedAt: DateTime.now(),
    );
  }
}

/// Placeholder for a real API-backed provider.
class RealWeatherProvider implements WeatherProvider {
  RealWeatherProvider({this.apiKey, this.endpoint});

  final String? apiKey;
  final String? endpoint;

  @override
  Future<WeatherSnapshot> fetchCurrent() async {
    // TODO: wire up to real weather API when API key + endpoint are available.
    // Keep signature stable so the UI remains unchanged.
    throw Exception('Real weather provider not configured. Add API key + endpoint.');
  }
}
