import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/models/live_message.dart';
import 'package:pure_live/domains/live/presentation/playback/controllers/danmaku_repeat_merger.dart';

LiveMessage chat(String text, {String user = 'u', bool local = false}) => LiveMessage(
  type: LiveMessageType.chat,
  userName: user,
  message: text,
  color: LiveMessageColor.white,
  isLocal: local,
);

void main() {
  const window = Duration(seconds: 5);
  final t0 = DateTime(2026, 1, 1, 12);

  test('the first copy is shown and later copies fold into it', () {
    final merger = DanmakuRepeatMerger();
    final first = chat('666', user: 'a');
    expect(merger.repeatOf(first, window: window, now: t0), isNull);
    for (final (user, seconds) in [('b', 1), ('c', 2)]) {
      final at = t0.add(Duration(seconds: seconds));
      expect(merger.repeatOf(chat('666', user: user), window: window, now: at), same(first));
    }
  });

  test('whitespace and case are ignored', () {
    final merger = DanmakuRepeatMerger();
    final first = chat('Hello  World');
    merger.repeatOf(first, window: window, now: t0);
    expect(merger.repeatOf(chat(' hello world '), window: window, now: t0), same(first));
  });

  test('a burst lasts while copies keep arriving', () {
    final merger = DanmakuRepeatMerger();
    final first = chat('冲');
    merger.repeatOf(first, window: window, now: t0);
    var at = t0;
    for (var i = 0; i < 10; i++) {
      at = at.add(const Duration(seconds: 4));
      expect(merger.repeatOf(chat('冲'), window: window, now: at), same(first));
    }
  });

  test('after a quiet window the text is shown again', () {
    final merger = DanmakuRepeatMerger();
    merger.repeatOf(chat('hi'), window: window, now: t0);
    final again = chat('hi');
    expect(merger.repeatOf(again, window: window, now: t0.add(const Duration(seconds: 6))), isNull);
    expect(merger.repeatOf(chat('hi'), window: window, now: t0.add(const Duration(seconds: 7))), same(again));
  });

  test('local messages, other types and empty text are never folded', () {
    final merger = DanmakuRepeatMerger();
    merger.repeatOf(chat('x'), window: window, now: t0);
    expect(merger.repeatOf(chat('x', local: true), window: window, now: t0), isNull);
    final gift = LiveMessage(type: LiveMessageType.gift, userName: 'g', message: 'x', color: LiveMessageColor.white);
    expect(merger.repeatOf(gift, window: window, now: t0), isNull);
    expect(merger.repeatOf(chat('  '), window: window, now: t0), isNull);
    expect(merger.repeatOf(chat('  '), window: window, now: t0), isNull);
  });

  test('memory stays bounded', () {
    final merger = DanmakuRepeatMerger(maxEntries: 3);
    for (var i = 0; i < 10; i++) {
      merger.repeatOf(chat('m$i'), window: window, now: t0);
    }
    expect(merger.size, 3);
  });

  test('clear forgets every burst', () {
    final merger = DanmakuRepeatMerger();
    merger.repeatOf(chat('a'), window: window, now: t0);
    merger.clear();
    expect(merger.repeatOf(chat('a'), window: window, now: t0), isNull);
  });
}
