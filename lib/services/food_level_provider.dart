import 'dart:async';
import 'dart:math';

/// Snapshot of feeder food level.
class FoodLevelReading {
  final double percentFull;
  final DateTime timestamp;

  const FoodLevelReading({required this.percentFull, required this.timestamp});

  bool get isEmpty => percentFull <= 0;
}

/// Abstraction for future real sensors (e.g., ToF / weight sensors).
abstract class FoodLevelProvider {
  Stream<FoodLevelReading> watchLevels();
  Future<void> dispose();
}

/// Simple mock that drains over time; useful for emulator + debug testing.
class MockFoodLevelProvider implements FoodLevelProvider {
  MockFoodLevelProvider({this.startPercent = 82, this.drainPerTick = 4, this.tick = const Duration(seconds: 5)});

  final double startPercent;
  final double drainPerTick;
  final Duration tick;

  StreamSubscription? _ticker;
  final _controller = StreamController<FoodLevelReading>.broadcast();

  @override
  Stream<FoodLevelReading> watchLevels() {
    double current = startPercent.clamp(0, 100);
    _ticker?.cancel();
    _ticker = Stream.periodic(tick, (_) => _).listen((_) {
      current = max(0, current - drainPerTick);
      _controller.add(FoodLevelReading(percentFull: current, timestamp: DateTime.now()));
      if (current <= 0) {
        // Pause a bit at empty then refill to keep demo running.
        Future.delayed(tick * 2, () {
          current = 95;
        });
      }
    });
    // Emit initial value
    Future.microtask(() => _controller.add(FoodLevelReading(percentFull: current, timestamp: DateTime.now())));
    return _controller.stream;
  }

  @override
  Future<void> dispose() async {
    await _ticker?.cancel();
    await _controller.close();
  }
}
