import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/domains/live/presentation/playback/controllers/danmaku_stall_watchdog.dart';

void main() {
  final start = DateTime(2026, 10, 12, 20);
  DateTime at(int seconds) => start.add(Duration(seconds: seconds));

  test('a busy room that goes silent is a stall, at about six of its usual gaps', () {
    final watchdog = DanmakuStallWatchdog();
    for (var i = 0; i < 20; i++) {
      watchdog.record(at(i * 10)); // one message every 10 s
    }
    expect(watchdog.threshold, const Duration(seconds: 60));
    expect(watchdog.shouldRecover(at(190 + 30)), isFalse);
    expect(watchdog.shouldRecover(at(190 + 61)), isTrue);
  });

  test('a room too quiet to have a pace is never judged', () {
    final watchdog = DanmakuStallWatchdog();
    for (var i = 0; i < 5; i++) {
      watchdog.record(at(i * 60));
    }
    expect(watchdog.threshold, isNull);
    expect(watchdog.shouldRecover(at(3600)), isFalse);
  });

  test('the threshold stays between 45 seconds and 5 minutes', () {
    final burst = DanmakuStallWatchdog();
    for (var i = 0; i < 10; i++) {
      burst.record(at(i));
    }
    expect(burst.threshold, const Duration(seconds: 45));

    final slow = DanmakuStallWatchdog();
    for (var i = 0; i < 10; i++) {
      slow.record(at(i * 120));
    }
    expect(slow.threshold, const Duration(minutes: 5));
  });

  test('after a recovery the pace is relearned and the cooldown holds', () {
    final watchdog = DanmakuStallWatchdog();
    for (var i = 0; i < 10; i++) {
      watchdog.record(at(i * 5));
    }
    expect(watchdog.shouldRecover(at(200)), isTrue);
    watchdog.markRecovered(at(200));
    expect(watchdog.shouldRecover(at(400)), isFalse, reason: 'no pace yet');

    for (var i = 0; i < 10; i++) {
      watchdog.record(at(210 + i));
    }
    expect(watchdog.shouldRecover(at(270)), isFalse, reason: 'cooldown since the last recovery');
    expect(watchdog.shouldRecover(at(330)), isTrue);
  });
}
