import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/player/core/live_audio_service.dart';

class _FakeTimer implements Timer {
  _FakeTimer(this.delay, this.callback);

  final Duration delay;
  final void Function() callback;
  bool _active = true;

  void fire() {
    if (!_active) return;
    _active = false;
    callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

void main() {
  late List<_FakeTimer> timers;
  late List<String> calls;

  setUp(() {
    timers = [];
    calls = [];
    LiveAudioService.timerFactory = (delay, callback) {
      final timer = _FakeTimer(delay, callback);
      timers.add(timer);
      return timer;
    };
    LiveAudioService.configurePlaybackCommands(pause: () async => calls.add('pause'));
    LiveAudioService.onSleepTimerPause = () => calls.add('userPause');
  });

  tearDown(() async {
    await LiveAudioService.configureSleepTimer(enabled: false, minutes: 60);
    LiveAudioService.timerFactory = Timer.new;
    LiveAudioService.onSleepTimerPause = null;
  });

  test('the sleep timer pauses playback when it ends', () async {
    await LiveAudioService.configureSleepTimer(enabled: true, minutes: 30);
    expect(LiveAudioService.isSleepSessionActive, isTrue);
    expect(timers.single.delay, const Duration(minutes: 30));

    timers.single.fire();
    await Future<void>.delayed(Duration.zero);

    expect(calls, ['userPause', 'pause']);
    expect(LiveAudioService.isSleepSessionActive, isFalse);
  });

  test('turning the sleep session off cancels the timer', () async {
    await LiveAudioService.configureSleepTimer(enabled: true, minutes: 30);
    await LiveAudioService.configureSleepTimer(enabled: false, minutes: 30);
    expect(timers.single.isActive, isFalse);
    timers.single.fire();
    expect(calls, isEmpty);
  });

  test('re-arming replaces the running timer', () async {
    await LiveAudioService.configureSleepTimer(enabled: true, minutes: 30);
    await LiveAudioService.configureSleepTimer(enabled: true, minutes: 10);
    expect(timers.first.isActive, isFalse);
    expect(timers.last.delay, const Duration(minutes: 10));
  });
}
