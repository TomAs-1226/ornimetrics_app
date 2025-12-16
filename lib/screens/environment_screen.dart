import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/weather_models.dart';
import '../services/weather_provider.dart';

class EnvironmentScreen extends StatefulWidget {
  const EnvironmentScreen({super.key, required this.provider, this.onSwapProvider});

  final WeatherProvider provider;
  final void Function()? onSwapProvider;

  @override
  State<EnvironmentScreen> createState() => _EnvironmentScreenState();
}

class _EnvironmentScreenState extends State<EnvironmentScreen> with SingleTickerProviderStateMixin {
  WeatherSnapshot? _data;
  String? _error;
  bool _loading = true;
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.provider.fetchCurrent();
      setState(() => _data = res);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
              leading: const Icon(Icons.cloud_queue),
              title: Text(widget.provider is MockWeatherProvider ? 'Mock Weather Provider' : 'Real Weather Provider'),
              subtitle: const Text('Swap once API key is ready. Mock works immediately.'),
              trailing: widget.onSwapProvider != null
                  ? ElevatedButton(onPressed: widget.onSwapProvider, child: const Text('Switch'))
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
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 180),
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
                    maxLines: 1,
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
