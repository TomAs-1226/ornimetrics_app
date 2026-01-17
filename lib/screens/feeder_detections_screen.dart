/// Detection History Screen for Ornimetrics OS
/// Shows recent detections with filtering and search capabilities

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/feeder_models.dart';
import '../services/feeder_api_service.dart';
import '../services/feeder_firebase_service.dart';

class FeederDetectionsScreen extends StatefulWidget {
  const FeederDetectionsScreen({super.key});

  @override
  State<FeederDetectionsScreen> createState() => _FeederDetectionsScreenState();
}

class _FeederDetectionsScreenState extends State<FeederDetectionsScreen> {
  final _apiService = FeederApiService.instance;
  final _firebaseService = FeederFirebaseService.instance;

  String? _selectedSpecies;
  bool _isLoading = true;
  bool _showOnlyWith3D = false;
  DateTimeRange? _dateRange;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await _apiService.getRecentDetections(
      limit: 200,
      species: _selectedSpecies,
    );
    setState(() => _isLoading = false);
  }

  List<FeederDetection> _filterDetections(List<FeederDetection> detections) {
    var filtered = detections;

    if (_showOnlyWith3D) {
      filtered = filtered.where((d) => d.has3d).toList();
    }

    if (_dateRange != null) {
      filtered = filtered.where((d) {
        return d.timestamp.isAfter(_dateRange!.start) &&
            d.timestamp.isBefore(_dateRange!.end.add(const Duration(days: 1)));
      }).toList();
    }

    return filtered;
  }

  Future<void> _showFilterSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FilterSheet(
        selectedSpecies: _selectedSpecies,
        showOnlyWith3D: _showOnlyWith3D,
        dateRange: _dateRange,
        availableSpecies: _getAvailableSpecies(),
        onApply: (species, has3d, range) {
          setState(() {
            _selectedSpecies = species;
            _showOnlyWith3D = has3d;
            _dateRange = range;
          });
          _loadData();
        },
      ),
    );
  }

  List<String> _getAvailableSpecies() {
    final species = <String>{};
    for (final detection in _apiService.recentDetections.value) {
      species.add(detection.species);
    }
    return species.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detection History'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: _selectedSpecies != null ||
                  _showOnlyWith3D ||
                  _dateRange != null,
              child: const Icon(Icons.filter_list),
            ),
            onPressed: _showFilterSheet,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ValueListenableBuilder<List<FeederDetection>>(
              valueListenable: _apiService.recentDetections,
              builder: (context, detections, _) {
                final filtered = _filterDetections(detections);

                if (filtered.isEmpty) {
                  return _buildEmptyState(colorScheme);
                }

                return _buildDetectionsList(filtered, colorScheme);
              },
            ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 80,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 24),
            Text(
              'No Detections Found',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _selectedSpecies != null || _showOnlyWith3D || _dateRange != null
                  ? 'Try adjusting your filters'
                  : 'Detections will appear here when your feeder spots birds.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (_selectedSpecies != null ||
                _showOnlyWith3D ||
                _dateRange != null) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedSpecies = null;
                    _showOnlyWith3D = false;
                    _dateRange = null;
                  });
                  _loadData();
                },
                icon: const Icon(Icons.clear),
                label: const Text('Clear Filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetectionsList(List<FeederDetection> detections, ColorScheme colorScheme) {
    // Group by date
    final grouped = <String, List<FeederDetection>>{};
    for (final detection in detections) {
      final dateKey = _formatDateKey(detection.timestamp);
      grouped.putIfAbsent(dateKey, () => []).add(detection);
    }

    final dateKeys = grouped.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: dateKeys.length,
      itemBuilder: (context, index) {
        final dateKey = dateKeys[index];
        final dayDetections = grouped[dateKey]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date header
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      dateKey,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${dayDetections.length} detection${dayDetections.length != 1 ? 's' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            // Detections
            ...dayDetections.map((detection) => _DetectionCard(
                  detection: detection,
                  colorScheme: colorScheme,
                  onTap: () => _showDetectionDetail(detection),
                )),
          ],
        );
      },
    );
  }

  String _formatDateKey(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);

    if (dateOnly == today) {
      return 'Today';
    } else if (dateOnly == yesterday) {
      return 'Yesterday';
    } else {
      return '${date.month}/${date.day}/${date.year}';
    }
  }

  void _showDetectionDetail(FeederDetection detection) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DetectionDetailSheet(detection: detection),
    );
  }
}

class _DetectionCard extends StatelessWidget {
  final FeederDetection detection;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _DetectionCard({
    required this.detection,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Thumbnail
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: detection.imageUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          detection.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.flutter_dash,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      )
                    : Icon(
                        Icons.flutter_dash,
                        color: colorScheme.onPrimaryContainer,
                        size: 28,
                      ),
              ),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            detection.formattedSpecies,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (detection.has3d)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '3D',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onTertiaryContainer,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatTime(detection.timestamp),
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (detection.individualId != null) ...[
                          const SizedBox(width: 12),
                          Icon(
                            Icons.person_pin,
                            size: 12,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Bird #${detection.individualId}',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Confidence
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: detection.confidenceColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${(detection.confidence * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: detection.confidenceColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$hour12:$minute $period';
  }
}

class _FilterSheet extends StatefulWidget {
  final String? selectedSpecies;
  final bool showOnlyWith3D;
  final DateTimeRange? dateRange;
  final List<String> availableSpecies;
  final Function(String?, bool, DateTimeRange?) onApply;

  const _FilterSheet({
    required this.selectedSpecies,
    required this.showOnlyWith3D,
    required this.dateRange,
    required this.availableSpecies,
    required this.onApply,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String? _selectedSpecies;
  late bool _showOnlyWith3D;
  late DateTimeRange? _dateRange;

  @override
  void initState() {
    super.initState();
    _selectedSpecies = widget.selectedSpecies;
    _showOnlyWith3D = widget.showOnlyWith3D;
    _dateRange = widget.dateRange;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outline.withOpacity(0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Title
          Text(
            'Filter Detections',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 24),

          // Species filter
          Text(
            'Species',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('All'),
                selected: _selectedSpecies == null,
                onSelected: (_) => setState(() => _selectedSpecies = null),
              ),
              ...widget.availableSpecies.map((species) => FilterChip(
                    label: Text(species.replaceAll('_', ' ')),
                    selected: _selectedSpecies == species,
                    onSelected: (_) =>
                        setState(() => _selectedSpecies = species),
                  )),
            ],
          ),
          const SizedBox(height: 24),

          // 3D filter
          SwitchListTile(
            title: const Text('Only with 3D data'),
            subtitle: const Text('Show detections with depth information'),
            value: _showOnlyWith3D,
            onChanged: (value) => setState(() => _showOnlyWith3D = value),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),

          // Date range
          ListTile(
            title: const Text('Date range'),
            subtitle: Text(
              _dateRange != null
                  ? '${_formatDate(_dateRange!.start)} - ${_formatDate(_dateRange!.end)}'
                  : 'All time',
            ),
            trailing: const Icon(Icons.calendar_today),
            contentPadding: EdgeInsets.zero,
            onTap: _selectDateRange,
          ),
          const SizedBox(height: 24),

          // Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _selectedSpecies = null;
                      _showOnlyWith3D = false;
                      _dateRange = null;
                    });
                  },
                  child: const Text('Clear'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () {
                    widget.onApply(
                      _selectedSpecies,
                      _showOnlyWith3D,
                      _dateRange,
                    );
                    Navigator.pop(context);
                  },
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: _dateRange,
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
    }
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}';
  }
}

class _DetectionDetailSheet extends StatelessWidget {
  final FeederDetection detection;

  const _DetectionDetailSheet({required this.detection});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.5,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.outline.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),

                // Image
                if (detection.imageUrl != null)
                  Container(
                    height: 250,
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: colorScheme.surfaceContainerHighest,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        detection.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                          child: Icon(
                            Icons.image_not_supported,
                            size: 64,
                            color: colorScheme.outline,
                          ),
                        ),
                      ),
                    ),
                  ),

                // Content
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  detection.formattedSpecies,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatFullTimestamp(detection.timestamp),
                                  style: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: detection.confidenceColor.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '${(detection.confidence * 100).toStringAsFixed(0)}%',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: detection.confidenceColor,
                                  ),
                                ),
                                Text(
                                  'Confidence',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: detection.confidenceColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Info grid
                      Row(
                        children: [
                          Expanded(
                            child: _InfoCard(
                              icon: Icons.person_pin,
                              label: 'Individual',
                              value: detection.individualId != null
                                  ? 'Bird #${detection.individualId}'
                                  : 'Unknown',
                              colorScheme: colorScheme,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _InfoCard(
                              icon: Icons.view_in_ar,
                              label: '3D Data',
                              value: detection.has3d ? 'Available' : 'No',
                              colorScheme: colorScheme,
                            ),
                          ),
                        ],
                      ),

                      if (detection.bbox != null) ...[
                        const SizedBox(height: 24),
                        Text(
                          'Detection Area',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Bounding box: ${detection.bbox!.join(', ')}',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatFullTimestamp(DateTime time) {
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final hour = time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '${months[time.month - 1]} ${time.day}, ${time.year} at $hour12:$minute $period';
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme colorScheme;

  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colorScheme.primary, size: 24),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
