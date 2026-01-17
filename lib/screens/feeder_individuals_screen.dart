/// Individuals Screen for Ornimetrics OS
/// Displays known individual birds with profiles and visit history

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/feeder_models.dart';
import '../services/feeder_api_service.dart';
import '../services/feeder_firebase_service.dart';

class FeederIndividualsScreen extends StatefulWidget {
  const FeederIndividualsScreen({super.key});

  @override
  State<FeederIndividualsScreen> createState() => _FeederIndividualsScreenState();
}

class _FeederIndividualsScreenState extends State<FeederIndividualsScreen>
    with SingleTickerProviderStateMixin {
  final _apiService = FeederApiService.instance;
  final _firebaseService = FeederFirebaseService.instance;

  late TabController _tabController;
  String? _selectedSpecies;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await _apiService.getIndividuals();
    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Individuals'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'All Birds', icon: Icon(Icons.pets)),
            Tab(text: 'By Species', icon: Icon(Icons.category)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildAllBirdsTab(colorScheme),
                _buildBySpeciesTab(colorScheme),
              ],
            ),
    );
  }

  Widget _buildAllBirdsTab(ColorScheme colorScheme) {
    return ValueListenableBuilder<List<FeederIndividual>>(
      valueListenable: _apiService.individuals,
      builder: (context, individuals, _) {
        if (individuals.isEmpty) {
          return _buildEmptyState(colorScheme);
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: individuals.length,
          itemBuilder: (context, index) {
            final individual = individuals[index];
            return _IndividualCard(
              individual: individual,
              colorScheme: colorScheme,
              onTap: () => _showIndividualDetail(individual),
            );
          },
        );
      },
    );
  }

  Widget _buildBySpeciesTab(ColorScheme colorScheme) {
    return ValueListenableBuilder<List<FeederIndividual>>(
      valueListenable: _apiService.individuals,
      builder: (context, individuals, _) {
        if (individuals.isEmpty) {
          return _buildEmptyState(colorScheme);
        }

        // Group by species
        final speciesMap = <String, List<FeederIndividual>>{};
        for (final ind in individuals) {
          speciesMap.putIfAbsent(ind.species, () => []).add(ind);
        }

        final speciesList = speciesMap.keys.toList()..sort();

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: speciesList.length,
          itemBuilder: (context, index) {
            final species = speciesList[index];
            final speciesIndividuals = speciesMap[species]!;

            return _SpeciesGroup(
              species: species,
              individuals: speciesIndividuals,
              colorScheme: colorScheme,
              onIndividualTap: _showIndividualDetail,
            );
          },
        );
      },
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
              Icons.pets,
              size: 80,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 24),
            Text(
              'No Individuals Yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Individual birds will appear here once they\'re recognized by your feeder.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showIndividualDetail(FeederIndividual individual) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _IndividualDetailSheet(individual: individual),
    );
  }
}

class _IndividualCard extends StatelessWidget {
  final FeederIndividual individual;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _IndividualCard({
    required this.individual,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: individual.thumbnailUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(
                          individual.thumbnailUrl!,
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
              const SizedBox(width: 16),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      individual.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      individual.formattedSpecies,
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _InfoChip(
                          icon: Icons.visibility,
                          label: '${individual.visitCount} visits',
                          colorScheme: colorScheme,
                        ),
                        const SizedBox(width: 8),
                        _InfoChip(
                          icon: Icons.percent,
                          label: '${(individual.confidence * 100).toStringAsFixed(0)}%',
                          color: individual.confidenceColor,
                          colorScheme: colorScheme,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Arrow
              Icon(
                Icons.chevron_right,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final ColorScheme colorScheme;

  const _InfoChip({
    required this.icon,
    required this.label,
    this.color,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (color ?? colorScheme.primary).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: color ?? colorScheme.primary,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color ?? colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeciesGroup extends StatelessWidget {
  final String species;
  final List<FeederIndividual> individuals;
  final ColorScheme colorScheme;
  final Function(FeederIndividual) onIndividualTap;

  const _SpeciesGroup({
    required this.species,
    required this.individuals,
    required this.colorScheme,
    required this.onIndividualTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withOpacity(0.5),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.category,
                    color: colorScheme.onPrimary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        species.replaceAll('_', ' '),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${individuals.length} individual${individuals.length != 1 ? 's' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // List
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: individuals.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final individual = individuals[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  child: Text(
                    '#${individual.id}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                title: Text(individual.name),
                subtitle: Text('${individual.visitCount} visits'),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: individual.confidenceColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${(individual.confidence * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: individual.confidenceColor,
                    ),
                  ),
                ),
                onTap: () => onIndividualTap(individual),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _IndividualDetailSheet extends StatelessWidget {
  final FeederIndividual individual;

  const _IndividualDetailSheet({required this.individual});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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

                // Header
                Row(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: individual.thumbnailUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Image.network(
                                individual.thumbnailUrl!,
                                fit: BoxFit.cover,
                              ),
                            )
                          : Icon(
                              Icons.flutter_dash,
                              size: 40,
                              color: colorScheme.onPrimaryContainer,
                            ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            individual.name,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            individual.formattedSpecies,
                            style: TextStyle(
                              fontSize: 16,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Stats
                Row(
                  children: [
                    Expanded(
                      child: _StatItem(
                        icon: Icons.visibility,
                        label: 'Total Visits',
                        value: '${individual.visitCount}',
                        colorScheme: colorScheme,
                      ),
                    ),
                    Expanded(
                      child: _StatItem(
                        icon: Icons.verified,
                        label: 'Confidence',
                        value: '${(individual.confidence * 100).toStringAsFixed(0)}%',
                        valueColor: individual.confidenceColor,
                        colorScheme: colorScheme,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Timeline
                _DetailSection(
                  title: 'Timeline',
                  colorScheme: colorScheme,
                  child: Column(
                    children: [
                      _TimelineItem(
                        icon: Icons.flag,
                        label: 'First seen',
                        value: _formatDate(individual.firstSeen),
                        colorScheme: colorScheme,
                      ),
                      const SizedBox(height: 12),
                      _TimelineItem(
                        icon: Icons.schedule,
                        label: 'Last seen',
                        value: _formatDate(individual.lastSeen),
                        colorScheme: colorScheme,
                      ),
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

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${date.month}/${date.day}/${date.year}';
    }
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final ColorScheme colorScheme;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: colorScheme.primary),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: valueColor ?? colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final Widget child;
  final ColorScheme colorScheme;

  const _DetailSection({
    required this.title,
    required this.child,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme colorScheme;

  const _TimelineItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
