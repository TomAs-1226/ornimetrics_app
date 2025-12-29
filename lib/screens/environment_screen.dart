import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../models/weather_models.dart';
import '../services/maintenance_rules_engine.dart';
import '../services/notifications_service.dart';
import '../services/weather_provider.dart';

class EnvironmentScreen extends StatefulWidget {
  const EnvironmentScreen({
    super.key,
    required this.provider,
    required this.latitude,
    required this.longitude,
    this.locationStatus,
    this.onRequestLocation,
  });

  final WeatherProvider provider;
  final double? latitude;
  final double? longitude;
  final String? locationStatus;
  final VoidCallback? onRequestLocation;

  @override
  State<EnvironmentScreen> createState() => _EnvironmentScreenState();
}

class _EnvironmentScreenState extends State<EnvironmentScreen> with SingleTickerProviderStateMixin {
  WeatherSnapshot? _data;
  String? _error;
  bool _loading = true;
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);

  static const _kWeatherCacheKey = 'cached_weather_snapshot';

  @override
  void initState() {
    super.initState();
    _restoreCached();
    _load();
  }

  Future<void> _restoreCached() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kWeatherCacheKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final map = json.decode(raw) as Map<String, dynamic>;
      final cached = WeatherSnapshot.fromMap(map);
      if (mounted) {
        setState(() {
          _data = cached;
          _loading = false;
          _error = null;
        });
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (widget.latitude == null || widget.longitude == null) {
      setState(() {
        _error = widget.locationStatus ?? 'Location permission required to load weather.';
        _loading = false;
      });
      return;
    }
    try {
      final res = await widget.provider.fetchCurrent(
        latitude: widget.latitude!,
        longitude: widget.longitude!,
      );
      await MaintenanceRulesEngine.instance.applyWeather(
        res,
        NotificationsService.instance.preferences.value,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kWeatherCacheKey, json.encode(res.toMap()));
      setState(() => _data = res);
    } catch (e) {
      debugPrint('Weather fetch failed: $e');
      // Show user-friendly message instead of technical details
      final errorStr = e.toString().toLowerCase();
      String userMessage;
      if (errorStr.contains('socket') || errorStr.contains('connection') || errorStr.contains('network')) {
        userMessage = 'No internet connection';
      } else if (errorStr.contains('timeout')) {
        userMessage = 'Connection timed out';
      } else {
        userMessage = 'Could not load weather data';
      }
      // If we have cached data, keep showing it and surface a friendly message
      setState(() => _error = _data != null ? 'Using cached weather • $userMessage' : userMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Environment', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Weather + humidity around your feeder',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _load,
              )
            ],
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _loading
                ? _buildLoadingCard()
                : _error != null
                    ? _buildErrorCard(_error!)
                    : _buildDataCard(_data!),
          ),
          const SizedBox(height: 16),
          Text('Provider', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.my_location),
              title: Text(
                widget.latitude != null ? 'Location secured' : 'Location needed',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                widget.locationStatus ??
                    (widget.latitude != null
                        ? 'Using current GPS coordinates for weather + history.'
                        : 'Grant location access to attach real weather to your feed.'),
              ),
              trailing: widget.onRequestLocation != null
                  ? ElevatedButton(
                      onPressed: widget.onRequestLocation,
                      child: const Text('Request access'),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            FadeTransition(
              opacity: _controller.drive(Tween(begin: 0.4, end: 1)),
              child: const Icon(Icons.waves, size: 40),
            ),
            const SizedBox(width: 16),
            const Expanded(child: LinearProgressIndicator(minHeight: 6)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(String message) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Could not load weather'),
                  const SizedBox(height: 4),
                  Text(message, style: const TextStyle(fontSize: 12)),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDataCard(WeatherSnapshot data) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${data.temperatureC.toStringAsFixed(1)}°C',
                        style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(data.condition, style: theme.textTheme.titleMedium),
                  ],
                ),
                CircleAvatar(
                  radius: 30,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(Icons.sunny_snowing, color: theme.colorScheme.onPrimaryContainer),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _metricChip(icon: Icons.water_drop, label: 'Humidity', value: '${data.humidity.toStringAsFixed(0)}%'),
                _metricChip(
                  icon: Icons.umbrella,
                  label: 'Precip',
                  value: data.precipitationChance != null
                      ? '${(data.precipitationChance! * 100).toStringAsFixed(0)}%'
                      : '—',
                ),
                _metricChip(
                  icon: Icons.air,
                  label: 'Wind',
                  value: data.windKph != null ? '${data.windKph!.toStringAsFixed(0)} kph' : 'Calm',
                ),
                _metricChip(
                  icon: Icons.speed,
                  label: 'Pressure',
                  value: data.pressureMb != null ? '${data.pressureMb!.toStringAsFixed(0)} mb' : '—',
                ),
                _metricChip(
                  icon: Icons.remove_red_eye_outlined,
                  label: 'Visibility',
                  value: data.visibilityKm != null ? '${data.visibilityKm!.toStringAsFixed(1)} km' : '—',
                ),
                _metricChip(
                  icon: Icons.wb_sunny_outlined,
                  label: 'UV index',
                  value: data.uvIndex?.toStringAsFixed(1) ?? '—',
                ),
                _metricChip(
                  icon: Icons.water_outlined,
                  label: 'Dew point',
                  value: data.dewPointC != null ? '${data.dewPointC!.toStringAsFixed(1)}°C' : '—',
                ),
                if (data.feelsLikeC != null)
                  _metricChip(
                    icon: Icons.thermostat_auto,
                    label: 'Feels like',
                    value: '${data.feelsLikeC!.toStringAsFixed(1)}°C',
                  ),
                if (data.precipitationMm != null)
                  _metricChip(
                    icon: Icons.grain_outlined,
                    label: 'Rain (hr)',
                    value: '${data.precipitationMm!.toStringAsFixed(1)} mm',
                  ),
                _metricChip(
                  icon: Icons.access_time,
                  label: 'Updated',
                  value: DateFormat('hh:mm a').format(data.fetchedAt),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _metricChip({required IconData icon, required String label, required String value}) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 220),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceVariant.withOpacity(0.6),
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.surfaceVariant.withOpacity(0.9),
              theme.colorScheme.primaryContainer.withOpacity(0.35),
            ],
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  Text(
                    value,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
