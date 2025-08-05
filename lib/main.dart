import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:pie_chart/pie_chart.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';

void main() async {
  // Ensure Flutter and Firebase are initialized, and load .env file
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const WildlifeApp());
}

class WildlifeApp extends StatelessWidget {
  const WildlifeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ornimetrics Tracker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F7F6),
        cardTheme: CardTheme(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      home: const WildlifeTrackerScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class WildlifeTrackerScreen extends StatefulWidget {
  const WildlifeTrackerScreen({super.key});

  @override
  State<WildlifeTrackerScreen> createState() => _WildlifeTrackerScreenState();
}

class _WildlifeTrackerScreenState extends State<WildlifeTrackerScreen> {
  // State variables for data
  Map<String, double> _speciesDataMap = {};
  int _totalDetections = 0;
  bool _isLoading = true;
  String _error = '';

  // State variables for AI Analysis
  Map<String, dynamic>? _aiAnalysisResult;
  bool _isAnalyzing = false;

  @override
  void initState() {
    super.initState();
    _fetchDetectionData();
  }

  Future<void> _fetchDetectionData() async {
    final dbRef = FirebaseDatabase.instance.ref('detections/2025-07-26/session_1/summary');

    try {
      final snapshot = await dbRef.get();
      if (snapshot.exists && snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        final Map<String, double> processedData = {};
        int total = 0;

        data.forEach((species, count) {
          if (count is int) {
            processedData[species] = count.toDouble();
            total += count;
          }
        });

        setState(() {
          _speciesDataMap = processedData;
          _totalDetections = total;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'No data found for the specified path.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load data: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _runAiAnalysis() async {
    if (_isAnalyzing || _speciesDataMap.isEmpty) return;
    setState(() {
      _isAnalyzing = true;
      _aiAnalysisResult = null; // Reset the map
    });

    final speciesSummary = _speciesDataMap.entries
        .map((entry) => '${entry.key}: ${entry.value.toInt()}')
        .join('\n');

    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer ${dotenv.env['OPENAI_API_KEY']}',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          "model": "gpt-4o-mini",
          // This tells the API to return a JSON object
          "response_format": {"type": "json_object"},
          "messages": [
            {
              "role": "system",
              // The new prompt asking for a specific JSON structure
              "content": """
You are an expert wildlife biologist. Analyze the provided species data.
Return your findings as a JSON object with the following exact schema:
{
  "analysis": "A summary of the species diversity and numbers.",
  "assessment": "A brief health assessment of the ecosystem based on the data.",
  "recommendations": ["A list of three data-driven recommendations or insights for a life scientist."]
}
"""
            },
            {
              "role": "user",
              "content": "Here is the species data for the session:\n$speciesSummary"
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // The content is a string containing JSON, so we decode it again
        final content = json.decode(data['choices'][0]['message']['content']);
        setState(() {
          _aiAnalysisResult = content;
        });
      } else {
        final errorBody = json.decode(response.body);
        throw Exception(
            'Failed to get analysis: ${errorBody['error']['message']}');
      }
    } catch (e) {
      setState(() {
        _aiAnalysisResult = {
          "error": "Could not fetch or parse AI analysis.\n$e"
        };
      });
    } finally {
      setState(() {
        _isAnalyzing = false;
      });
    }
  }

  IconData _getIconForSpecies(String species) {
    species = species.toLowerCase();
    if (species.contains('deer')) return Icons.pets;
    if (species.contains('bird')) return Icons.flutter_dash;
    if (species.contains('rabbit')) return Icons.cruelty_free;
    if (species.contains('squirrel')) return Icons.bug_report;
    return Icons.question_mark;
  }

  String _formatSpeciesName(String rawName) {
    return rawName
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ornimetrics Tracker', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 1,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(child: Text(_error, style: const TextStyle(color: Colors.red)))
          : RefreshIndicator(
        onRefresh: _fetchDetectionData,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            const Text(
              'Live Animal Detection',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Real-time data from park sensors',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            _buildSummaryCards(),
            const SizedBox(height: 24),
            const Text(
              'Species Distribution',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            _buildDistributionCard(),
            const SizedBox(height: 24),
            _buildAiAnalysisCard(), // The AI analysis feature
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Row(
      children: [
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$_totalDetections',
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Row(
                    children: [
                      Text('Total Detections', style: TextStyle(color: Colors.grey)),
                      Spacer(),
                      Icon(Icons.track_changes, color: Colors.green),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_speciesDataMap.length}',
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Row(
                    children: [
                      Text('Unique Species', style: TextStyle(color: Colors.grey)),
                      Spacer(),
                      Icon(Icons.pets, color: Colors.blue),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDistributionCard() {
    final sortedEntries = _speciesDataMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (_speciesDataMap.isNotEmpty)
              PieChart(
                dataMap: _speciesDataMap,
                animationDuration: const Duration(milliseconds: 800),
                chartLegendSpacing: 48,
                chartRadius: MediaQuery.of(context).size.width / 3.2,
                legendOptions: const LegendOptions(showLegends: false),
                chartValuesOptions: const ChartValuesOptions(
                  showChartValuesInPercentage: true,
                  showChartValues: true,
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40.0),
                child: Text("No species data to display."),
              ),
            const SizedBox(height: 24),
            const Divider(),
            for (var entry in sortedEntries)
              _buildSpeciesListItem(
                icon: _getIconForSpecies(entry.key),
                name: _formatSpeciesName(entry.key),
                count: entry.value.toInt(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeciesListItem({
    required IconData icon,
    required String name,
    required int count,
  }) {
    final percentage = (_totalDetections > 0) ? (count / _totalDetections) * 100 : 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.black54),
          const SizedBox(width: 16),
          Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          const Spacer(),
          Text(
            '${percentage.toStringAsFixed(0)}% ($count)',
            style: const TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  // This is the main widget that replaces the old one
  // This is the main widget that replaces the old one
  Widget _buildAiAnalysisCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.deepPurple),
            SizedBox(width: 8),
            Text("Ecological AI Analysis",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 16),

        // --- UI logic based on state ---

        // 1. Show a loading indicator while analyzing
        if (_isAnalyzing) const Center(child: CircularProgressIndicator()),

        // 2. Show a prompt if there's no result yet
        if (!_isAnalyzing && _aiAnalysisResult == null)
          const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20.0),
                child: Text("Click below to generate an AI analysis."),
              )),

        // 3. If we have a result, display it
        if (_aiAnalysisResult != null && !_isAnalyzing)
        // THE FIX: First, check if the result is a Map as expected.
          if (_aiAnalysisResult is Map<String, dynamic>)
          // If it's a Map, check for the 'error' key.
            if (_aiAnalysisResult!['error'] != null)
              _buildInfoCard(
                title: "Error",
                content: Text(
                  _aiAnalysisResult!['error'].toString(),
                  style: const TextStyle(color: Colors.red),
                ),
              )
            else
            // If it's a valid Map without an error, build the success layout.
              Column(
                children: [
                  _buildInfoCard(
                    title: "Current Analysis",
                    content: Text(
                      _aiAnalysisResult!['analysis'] ?? 'No analysis available.',
                      style: const TextStyle(height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildInfoCard(
                    title: "Ecosystem Assessment",
                    content: Text(
                      _aiAnalysisResult!['assessment'] ?? 'No assessment available.',
                      style: const TextStyle(height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildInfoCard(
                    title: "Recommendations",
                    content: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: (_aiAnalysisResult!['recommendations'] as List<dynamic>)
                          .map((rec) => Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("• ", style: TextStyle(fontWeight: FontWeight.bold)),
                            Expanded(child: Text(rec.toString())),
                          ],
                        ),
                      ))
                          .toList(),
                    ),
                  ),
                ],
              )
          // If the result is NOT a Map, show a friendly error instead of crashing.
          else
            _buildInfoCard(
                title: "Unexpected AI Response",
                content: Text(
                    "The data from the AI was in an unexpected format. Please try again.\n\nDetails: ${_aiAnalysisResult.toString()}")),

        const SizedBox(height: 24),

        // The button remains the same
        ElevatedButton.icon(
          onPressed: _runAiAnalysis,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple.shade400,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          icon: Icon(_isAnalyzing ? Icons.sync : Icons.insights),
          label: Text(_isAnalyzing ? "Analyzing..." : "Run AI Analysis"),
        ),
      ],
    );
  }

// Helper widget to reduce code duplication for the cards
  Widget _buildInfoCard({required String title, required Widget content}) {
    return Card(
      color: Colors.white,
      elevation: 2,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF006D65)),
            ),
            const SizedBox(height: 10),
            content,
          ],
        ),
      ),
    );
  }
}