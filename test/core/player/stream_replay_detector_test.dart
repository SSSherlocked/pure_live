import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/player/kernel/stream_replay_detector.dart';

void main() {
  StreamReplay? parse(String text, {String prefix = 'ad', String level = 'warn'}) =>
      StreamReplayDetector.parse(prefix: prefix, level: level, text: text);

  test('a jump back of a few seconds in the audio is a replay', () {
    final replay = parse('Invalid audio PTS: 669.651272 -> 662.522000');
    expect(replay, isNotNull);
    expect(replay!.seconds, closeTo(7.13, 0.01));
  });

  test('jitter and clock restarts are not replays', () {
    expect(parse('Invalid audio PTS: 663.706998 -> 662.522000'), isNull);
    expect(parse('Invalid audio PTS: 1557.7 -> 3.2'), isNull);
    expect(parse('Invalid audio PTS: 10.0 -> 20.0'), isNull);
  });

  test('only the audio decoder warning counts', () {
    expect(parse('Invalid audio PTS: 669.6 -> 662.5', prefix: 'cplayer'), isNull);
    expect(parse('Invalid audio PTS: 669.6 -> 662.5', level: 'error'), isNull);
    expect(parse('Invalid video timestamp: 669.6 -> 662.5'), isNull);
  });

  test('observe passes a replay on', () async {
    final seen = <StreamReplay>[];
    final sub = StreamReplayDetector.replays.listen(seen.add);
    StreamReplayDetector.observe(prefix: 'ad', level: 'warn', text: 'Invalid audio PTS: 1557.734658 -> 1550.606000');
    StreamReplayDetector.observe(prefix: 'ad', level: 'warn', text: 'Reset playback due to audio timestamp reset.');
    await sub.cancel();
    expect(seen, hasLength(1));
  });
}
