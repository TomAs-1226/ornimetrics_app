import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../models/weather_models.dart';

abstract class WeatherProvider {
  Future<WeatherSnapshot> fetchCurrent({
    required double latitude,
    required double longitude,
  });

  Future<WeatherSnapshot> fetchHistorical({
    required DateTime timestamp,
    required double latitude,
    required double longitude,
  });
}

class MockWeatherProvider implements WeatherProvider {
  WeatherSnapshot _fakeSnapshot(DateTime ts) {
    final isEvening = ts.hour >= 18 || ts.hour <= 5;
    final raining = ts.minute % 3 == 0;
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
      fetchedAt: ts,
      isRaining: raining,
      isSnowing: false,
      isHailing: false,
      precipitationMm: raining ? 2.4 : 0.0,
    );
  }

  @override
  Future<WeatherSnapshot> fetchCurrent({required double latitude, required double longitude}) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return _fakeSnapshot(DateTime.now());
  }

  @override
  Future<WeatherSnapshot> fetchHistorical({
    required DateTime timestamp,
    required double latitude,
    required double longitude,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return _fakeSnapshot(timestamp);
  }
}

class RealWeatherProvider implements WeatherProvider {
  RealWeatherProvider({required this.apiKey, required this.endpoint, http.Client? client})
      : _client = client ?? http.Client();

  final String apiKey;
  final String endpoint;
  final http.Client _client;
  final Map<String, Map<int, WeatherSnapshot>> _historyCache = <String, Map<int, WeatherSnapshot>>{};

  Uri _buildUri(String path, Map<String, String> query) {
    final base = Uri.parse(endpoint.endsWith('/') ? endpoint : '$endpoint/');
    return base.resolve(path).replace(queryParameters: query);
  }

  WeatherSnapshot _snapshotFromCurrent(Map<String, dynamic> json) {
    final current = Map<String, dynamic>.from(json['current'] as Map);
    final location = Map<String, dynamic>.from(json['location'] as Map);
    final tsString = current['last_updated']?.toString() ?? location['localtime']?.toString();
    final fetched = tsString != null ? DateTime.tryParse(tsString) ?? DateTime.now() : DateTime.now();
    return WeatherSnapshot(
      condition: current['condition']?['text']?.toString() ?? 'Unknown',
      temperatureC: (current['temp_c'] as num?)?.toDouble() ?? 0,
      feelsLikeC: (current['feelslike_c'] as num?)?.toDouble(),
      humidity: (current['humidity'] as num?)?.toDouble() ?? 0,
      precipitationChance: (current['precip_mm'] as num?) != null ? (current['precip_mm'] as num).toDouble() : null,
      precipitationMm: (current['precip_mm'] as num?)?.toDouble(),
      windKph: (current['wind_kph'] as num?)?.toDouble(),
      pressureMb: (current['pressure_mb'] as num?)?.toDouble(),
      uvIndex: (current['uv'] as num?)?.toDouble(),
      visibilityKm: (current['vis_km'] as num?)?.toDouble(),
      dewPointC: (current['dewpoint_c'] as num?)?.toDouble(),
      fetchedAt: fetched,
      isRaining: (current['condition']?['text']?.toString().toLowerCase().contains('rain') ?? false) ||
          (current['precip_mm'] as num? ?? 0) > 0,
      isSnowing: (current['condition']?['text']?.toString().toLowerCase().contains('snow') ?? false),
      isHailing: (current['condition']?['text']?.toString().toLowerCase().contains('hail') ?? false),
    );
  }

  WeatherSnapshot _snapshotFromHour(Map<String, dynamic> hour, DateTime fallback) {
    final tsString = hour['time']?.toString();
    final ts = tsString != null ? DateTime.tryParse(tsString) ?? fallback : fallback;
    return WeatherSnapshot(
      condition: hour['condition']?['text']?.toString() ?? 'Unknown',
      temperatureC: (hour['temp_c'] as num?)?.toDouble() ?? 0,
      feelsLikeC: (hour['feelslike_c'] as num?)?.toDouble(),
      humidity: (hour['humidity'] as num?)?.toDouble() ?? 0,
      precipitationChance: (hour['chance_of_rain'] as num?)?.toDouble() != null
          ? ((hour['chance_of_rain'] as num).toDouble() / 100)
          : null,
      precipitationMm: (hour['precip_mm'] as num?)?.toDouble(),
      windKph: (hour['wind_kph'] as num?)?.toDouble(),
      pressureMb: (hour['pressure_mb'] as num?)?.toDouble(),
      uvIndex: (hour['uv'] as num?)?.toDouble(),
      visibilityKm: (hour['vis_km'] as num?)?.toDouble(),
      dewPointC: (hour['dewpoint_c'] as num?)?.toDouble(),
      fetchedAt: ts,
      isRaining: (hour['chance_of_rain'] as num? ?? 0) > 40 || (hour['precip_mm'] as num? ?? 0) > 0,
      isSnowing: (hour['chance_of_snow'] as num? ?? 0) > 40,
      isHailing: false,
    );
  }

  Future<Map<int, WeatherSnapshot>> _historyForDay({
    required DateTime timestamp,
    required double latitude,
    required double longitude,
  }) async {
    final key = DateFormat('yyyy-MM-dd').format(timestamp.toUtc());
    if (_historyCache.containsKey(key)) return _historyCache[key]!;

    final uri = _buildUri('history.json', <String, String>{
      'key': apiKey,
      'q': '$latitude,$longitude',
      'dt': key,
      'hour': timestamp.toUtc().hour.toString(),
    });

    final resp = await _client.get(uri);
    if (resp.statusCode != 200) {
      throw StateError('Weather history request failed (${resp.statusCode}): ${resp.body}');
    }

    final data = json.decode(resp.body) as Map<String, dynamic>;
    final hours = <int, WeatherSnapshot>{};
    final forecastDays = (data['forecast']?['forecastday'] as List?) ?? <dynamic>[];
    final forecast = forecastDays.isNotEmpty ? Map<String, dynamic>.from(forecastDays.first as Map) : null;
    final hourEntries = (forecast?['hour'] as List?) ?? <dynamic>[];
    for (final h in hourEntries) {
      final hour = Map<String, dynamic>.from(h as Map);
      final ts = DateTime.tryParse(hour['time'].toString()) ?? timestamp;
      hours[ts.toUtc().hour] = _snapshotFromHour(hour, ts);
    }

    _historyCache[key] = hours;
    return hours;
  }

  @override
  Future<WeatherSnapshot> fetchCurrent({
    required double latitude,
    required double longitude,
  }) async {
    if (apiKey.isEmpty) {
      throw StateError('WEATHER_API_KEY is missing. Add it to .env.');
    }
    final uri = _buildUri('current.json', <String, String>{
      'key': apiKey,
      'q': '$latitude,$longitude',
      'aqi': 'no',
    });

    final resp = await _client.get(uri);
    if (resp.statusCode != 200) {
      throw StateError('Weather request failed (${resp.statusCode}): ${resp.body}');
    }

    final data = json.decode(resp.body) as Map<String, dynamic>;
    return _snapshotFromCurrent(data);
  }

  @override
  Future<WeatherSnapshot> fetchHistorical({
    required DateTime timestamp,
    required double latitude,
    required double longitude,
  }) async {
    if (apiKey.isEmpty) {
      throw StateError('WEATHER_API_KEY is missing. Add it to .env.');
    }
    final day = await _historyForDay(timestamp: timestamp, latitude: latitude, longitude: longitude);
    if (day.isEmpty) {
      throw StateError('No weather history available for ${timestamp.toIso8601String()}');
    }
    final byHour = day[timestamp.toUtc().hour];
    if (byHour != null) return byHour;

    final nearest = day.entries.reduce((a, b) {
      final deltaA = (timestamp.toUtc().hour - a.key).abs();
      final deltaB = (timestamp.toUtc().hour - b.key).abs();
      return deltaA <= deltaB ? a : b;
    });
    return nearest.value;
  }
}
