import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/player/core/background_playback_keeper.dart';

/// A manual clock: [elapse] moves time and fires the timers that came due.
class _FakeClock {
  DateTime now = DateTime(2026, 10, 14, 20);
  final List<_FakeTimer> _timers = [];

  Timer timer(Duration delay, void Function() callback) {
    final timer = _FakeTimer(now.add(delay), callback);
    _timers.add(timer);
    return timer;
  }

  void elapse(Duration duration) {
    final end = now.add(duration);
    while (true) {
      final due = _timers.where((t) => t.isActive && !t.at.isAfter(end)).toList()
        ..sort((a, b) => a.at.compareTo(b.at));
      if (due.isEmpty) break;
      final next = due.first;
      now = next.at;
      next.fire();
    }
    now = end;
  }

  int get pending => _timers.where((t) => t.isActive).length;
}

class _FakeTimer implements Timer {
  _FakeTimer(this.at, this._callback);

  final DateTime at;
  final void Function() _callback;
  bool _active = true;

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

BackgroundKeeperInput _input({
  bool away = true,
  BackgroundPlayerPhase phase = BackgroundPlayerPhase.playing,
  bool reconnecting = false,
  bool roomOffline = false,
  bool interrupted = false,
}) => BackgroundKeeperInput(
  away: away,
  phase: phase,
  reconnecting: reconnecting,
  roomOffline: roomOffline,
  interrupted: interrupted,
);

void main() {
  late _FakeClock clock;
  late int changes;
  late BackgroundPlaybackKeeper keeper;

  setUp(() {
    clock = _FakeClock();
    changes = 0;
    keeper = BackgroundPlaybackKeeper(onChanged: () => changes++, now: () => clock.now, timer: clock.timer);
  });

  tearDown(() => keeper.dispose());

  test('in front of the app nothing is held and the room may always start', () {
    expect(keeper.update(_input(away: false)), BackgroundHold.none);
    expect(keeper.mayStartPlayback, isTrue);
    expect(keeper.update(_input(away: false, phase: BackgroundPlayerPhase.failed)), BackgroundHold.none);
    expect(keeper.mayStartPlayback, isTrue);
  });

  test('a room playing when the app leaves is held while it plays', () {
    keeper.update(_input(away: false));
    expect(keeper.update(_input()), BackgroundHold.playing);
    expect(keeper.update(_input(phase: BackgroundPlayerPhase.starting)), BackgroundHold.playing);
    expect(keeper.mayStartPlayback, isTrue);
  });

  test('a room not playing when the app left is not held and may not start by itself', () {
    keeper.update(_input(away: false, phase: BackgroundPlayerPhase.failed));
    expect(keeper.update(_input(phase: BackgroundPlayerPhase.failed, reconnecting: true)), BackgroundHold.none);
    expect(keeper.mayStartPlayback, isFalse);
    expect(keeper.update(_input(phase: BackgroundPlayerPhase.idle, roomOffline: true)), BackgroundHold.none);
    expect(keeper.mayStartPlayback, isFalse);

    // Back in front: it may start again.
    keeper.update(_input(away: false, phase: BackgroundPlayerPhase.idle));
    expect(keeper.mayStartPlayback, isTrue);
  });

  test('a reconnect keeps the hold for 30 minutes, then gives up', () {
    keeper.update(_input());
    expect(
      keeper.update(_input(phase: BackgroundPlayerPhase.failed, reconnecting: true)),
      BackgroundHold.recovering,
    );
    // A refresh pauses the old player and reopens: still recovering.
    expect(
      keeper.update(_input(phase: BackgroundPlayerPhase.paused, reconnecting: true)),
      BackgroundHold.recovering,
    );
    clock.elapse(const Duration(minutes: 29));
    expect(keeper.hold, BackgroundHold.recovering);
    expect(changes, 0);
    clock.elapse(const Duration(minutes: 2));
    expect(keeper.hold, BackgroundHold.none);
    expect(changes, 1);
    expect(keeper.mayStartPlayback, isFalse);
  });

  test('retries that open but fail again do not restart the budget', () {
    keeper.update(_input());
    keeper.update(_input(phase: BackgroundPlayerPhase.failed, reconnecting: true));
    clock.elapse(const Duration(minutes: 20));
    expect(keeper.update(_input(phase: BackgroundPlayerPhase.starting, reconnecting: true)), BackgroundHold.playing);
    keeper.update(_input(phase: BackgroundPlayerPhase.failed, reconnecting: true));
    clock.elapse(const Duration(minutes: 11));
    expect(keeper.hold, BackgroundHold.none);
  });

  test('playing again resets the budget', () {
    keeper.update(_input());
    keeper.update(_input(phase: BackgroundPlayerPhase.failed, reconnecting: true));
    clock.elapse(const Duration(minutes: 20));
    keeper.update(_input());
    keeper.update(_input(phase: BackgroundPlayerPhase.failed, reconnecting: true));
    clock.elapse(const Duration(minutes: 20));
    expect(keeper.hold, BackgroundHold.recovering);
  });

  test('an offline streamer is waited for 10 minutes', () {
    keeper.update(_input());
    expect(
      keeper.update(_input(phase: BackgroundPlayerPhase.idle, reconnecting: true, roomOffline: true)),
      BackgroundHold.waiting,
    );
    clock.elapse(const Duration(minutes: 9));
    expect(keeper.hold, BackgroundHold.waiting);
    expect(keeper.mayStartPlayback, isTrue);
    clock.elapse(const Duration(minutes: 2));
    expect(keeper.hold, BackgroundHold.none);
    expect(keeper.mayStartPlayback, isFalse);
  });

  test('the streamer coming back within the wait plays on', () {
    keeper.update(_input());
    keeper.update(_input(phase: BackgroundPlayerPhase.idle, roomOffline: true));
    clock.elapse(const Duration(minutes: 5));
    expect(keeper.update(_input(phase: BackgroundPlayerPhase.starting)), BackgroundHold.playing);
    expect(keeper.update(_input()), BackgroundHold.playing);
    expect(clock.pending, 0);
  });

  test('a call keeps the hold for 30 minutes', () {
    keeper.update(_input());
    expect(
      keeper.update(_input(phase: BackgroundPlayerPhase.paused, interrupted: true)),
      BackgroundHold.interrupted,
    );
    clock.elapse(const Duration(minutes: 25));
    expect(keeper.hold, BackgroundHold.interrupted);
    expect(keeper.update(_input()), BackgroundHold.playing);
  });

  test('a call longer than 30 minutes gives up', () {
    keeper.update(_input());
    keeper.update(_input(phase: BackgroundPlayerPhase.paused, interrupted: true));
    clock.elapse(const Duration(minutes: 31));
    expect(keeper.hold, BackgroundHold.none);
  });

  test("the user's pause lets everything go until it plays again", () {
    keeper.update(_input());
    keeper.markUserPause();
    // The pause has not reached the player yet.
    expect(keeper.hold, BackgroundHold.playing);
    expect(keeper.update(_input(phase: BackgroundPlayerPhase.paused)), BackgroundHold.none);
    expect(keeper.mayStartPlayback, isFalse);
    expect(clock.pending, 0);

    // Played again from the notification.
    expect(keeper.update(_input()), BackgroundHold.playing);
    expect(keeper.update(_input(phase: BackgroundPlayerPhase.failed, reconnecting: true)), BackgroundHold.recovering);
  });

  test("the user's pause while reconnecting drops the hold at once", () {
    keeper.update(_input());
    keeper.update(_input(phase: BackgroundPlayerPhase.failed, reconnecting: true));
    keeper.markUserPause();
    expect(keeper.hold, BackgroundHold.none);
    expect(keeper.mayStartPlayback, isFalse);
    expect(clock.pending, 0);
  });

  test('a pause of unknown cause (a refresh between two opens) is waited out', () {
    keeper.update(_input());
    expect(keeper.update(_input(phase: BackgroundPlayerPhase.paused)), BackgroundHold.waiting);
    clock.elapse(const Duration(minutes: 11));
    expect(keeper.hold, BackgroundHold.none);
  });

  test('coming back and leaving again starts from what plays then', () {
    keeper.update(_input());
    keeper.update(_input(phase: BackgroundPlayerPhase.failed, reconnecting: true));
    clock.elapse(const Duration(minutes: 31));
    expect(keeper.hold, BackgroundHold.none);

    keeper.update(_input(away: false));
    expect(keeper.update(_input()), BackgroundHold.playing);
    expect(keeper.update(_input(phase: BackgroundPlayerPhase.failed, reconnecting: true)), BackgroundHold.recovering);
  });

  test('dispose stops the timers', () {
    keeper.update(_input());
    keeper.update(_input(phase: BackgroundPlayerPhase.failed, reconnecting: true));
    expect(clock.pending, 1);
    keeper.dispose();
    expect(clock.pending, 0);
    expect(keeper.hold, BackgroundHold.none);
  });

  group('ReconnectSchedule', () {
    const schedule = ReconnectSchedule();

    test('steps 2, 10, 20, 30, 60 s, then every minute', () {
      expect(
        [for (var attempt = 0; attempt < 8; attempt++) schedule.delayBefore(attempt).inSeconds],
        [2, 10, 20, 30, 60, 60, 60, 60],
      );
      expect(schedule.delayBefore(-1), const Duration(seconds: 2));
    });

    test('runs for 30 minutes', () {
      expect(schedule.isExhausted(const Duration(minutes: 30)), isFalse);
      expect(schedule.isExhausted(const Duration(minutes: 30, seconds: 1)), isTrue);
    });

    test('takes the steps it is given', () {
      const custom = ReconnectSchedule(delays: [Duration(seconds: 5)], window: Duration(minutes: 1));
      expect(custom.delayBefore(3), const Duration(seconds: 5));
      expect(custom.isExhausted(const Duration(minutes: 2)), isTrue);
    });
  });
}
