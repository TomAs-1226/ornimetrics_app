import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ornimetrics_app/models/feeder_models.dart';
import 'package:ornimetrics_app/services/feeder_api_service.dart';
import 'package:ornimetrics_app/screens/feeder_tab_screen.dart';
import 'package:ornimetrics_app/screens/feeder_activity_screen.dart';
import 'package:ornimetrics_app/screens/feeder_welfare_screen.dart';
import 'package:ornimetrics_app/screens/feeder_individuals_screen.dart';
import 'package:ornimetrics_app/screens/feeder_individual_profile_screen.dart';
import 'package:ornimetrics_app/screens/feeder_audio_screen.dart';
import 'package:ornimetrics_app/screens/feeder_about_screen.dart';
import 'package:ornimetrics_app/screens/feeder_settings_screen.dart';

/// Renders every feeder screen with demo data across a matrix of widths, both
/// themes, and a large text scale, failing on any RenderFlex overflow.
void main() {
  final device = PairedFeeder(
    deviceId: 'demo-feeder-001',
    deviceName: 'Ornimetrics',
    feederName: 'Backyard Feeder',
    staticIp: '192.168.1.200',
    version: '2.3.0',
    pairedAt: DateTime.now(),
    userId: 'local',
  );

  // Narrow phones up to a wide one; 3-column tiles get tight (~116dp) mid-range.
  const sizes = [Size(320, 640), Size(360, 690), Size(411, 731), Size(480, 800)];
  const scales = [1.0, 1.3];

  setUp(() => FeederApiService.instance.enableDemo());

  Widget screenFor(String name) => switch (name) {
        'home' => Scaffold(
            body: FeederHomeView(device: device, onRefresh: () async {}, onRemove: () {}),
          ),
        'activity' => const FeederActivityScreen(),
        'welfare' => const FeederWelfareScreen(),
        'individuals' => const FeederIndividualsScreen(),
        'profile' => const FeederIndividualProfileScreen(individualId: '#1'),
        'audio' => const FeederAudioScreen(),
        'about' => FeederAboutScreen(device: device),
        'settings' => FeederSettingsScreen(device: device, onRemoved: () {}),
        _ => const SizedBox(),
      };

  const screens = ['home', 'activity', 'welfare', 'individuals', 'profile', 'audio', 'about', 'settings'];

  Future<void> check(WidgetTester tester, String name, Size size, Brightness b, double ts) async {
    final details = <FlutterErrorDetails>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      details.add(d);
      FlutterError.dumpErrorToConsole(d);
    };
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.green, brightness: b), useMaterial3: true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(ts)),
          child: child!,
        ),
        home: screenFor(name),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 800));
    FlutterError.onError = prev;
    if (details.isNotEmpty) {
      for (final d in details) {
        debugPrint('### OVERFLOW $name @ $size ${b.name} x$ts ###');
        debugPrint(d.toString());
      }
    }
    expect(details, isEmpty, reason: 'Overflow: $name @ $size ${b.name} x$ts');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('feeder screens: no overflow across sizes/themes/text scale', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final name in screens) {
      for (final size in sizes) {
        for (final b in Brightness.values) {
          for (final ts in scales) {
            await check(tester, name, size, b, ts);
          }
        }
      }
    }
  });
}
