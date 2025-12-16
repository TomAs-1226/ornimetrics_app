import '../models/weather_models.dart';

abstract class WeatherProvider {
  Future<WeatherSnapshot> fetchCurrent();
}

class MockWeatherProvider implements WeatherProvider {
  @override
  Future<WeatherSnapshot> fetchCurrent() async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final now = DateTime.now();
    final isEvening = now.hour >= 18 || now.hour <= 5;
    final raining = now.minute % 3 == 0;
    return WeatherSnapshot(
      condition: raining ? 'Rain showers' : (isEvening ? 'Clear night' : 'Partly cloudy'),
      temperatureC: isEvening ? 14.5 : 19.5,
      feelsLikeC: isEvening ? 13.0 : 20.1,
      humidity: raining ? 86 : 62,
      precipitationChance: raining ? 0.65 : 0.2,
      windKph: 9.4,
      pressureMb: 1014,
      uvIndex: isEvening ? 0.0 : 3.2,
      visibilityKm: raining ? 8.0 : 12.5,
      dewPointC: 10.2,
      fetchedAt: DateTime.now(),
      isRaining: raining,
      isSnowing: false,
      isHailing: false,
      precipitationMm: raining ? 2.4 : 0.0,
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
