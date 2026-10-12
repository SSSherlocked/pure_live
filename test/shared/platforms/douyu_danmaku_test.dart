import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/models/live_message.dart';
import 'package:pure_live/shared/platforms/douyu/douyu_danmaku.dart';

void main() {
  late List<LiveMessage> received;
  late List<String> closed;

  DouyuDanmaku engine({bool filterAutomated = false}) {
    final danmaku = DouyuDanmaku(filterSuspectedAutomatedMessages: () => filterAutomated)
      ..debugSetRoomId('9999')
      ..onMessage = received.add
      ..onClose = closed.add;
    return danmaku;
  }

  // Server and client frames share the length layout, so the engine's own
  // serializer builds test frames.
  List<int> frame(DouyuDanmaku danmaku, List<String> bodies) =>
      [for (final body in bodies) ...danmaku.serializeDouyu(body)];

  setUp(() {
    received = [];
    closed = [];
  });

  test('every packet of a batched frame is decoded, not only the first', () {
    final danmaku = engine();
    danmaku.decodeMessage(
      frame(danmaku, [
        'type@=chatmsg/rid@=9999/uid@=1/nn@=a/txt@=one/dms@=3/',
        'type@=chatmsg/rid@=9999/uid@=2/nn@=b/txt@=two/dms@=3/',
        'type@=chatmsg/rid@=9999/uid@=3/nn@=c/txt@=three/dms@=3/',
      ]),
    );
    expect(received.map((m) => m.message), ['one', 'two', 'three']);
    expect(received.first.userId, '1');
  });

  test('ordinary viewers are kept; suspected automated chat only goes when the filter is on', () {
    const viewer = 'type@=chatmsg/rid@=9999/nn@=a/txt@=hello/dms@=3/';
    const automated = 'type@=chatmsg/rid@=9999/nn@=b/txt@=spam/';

    final open = engine();
    open.decodeMessage(frame(open, [viewer, automated]));
    expect(received.map((m) => m.message), ['hello', 'spam']);

    received.clear();
    final filtered = engine(filterAutomated: true);
    filtered.decodeMessage(frame(filtered, [viewer, automated]));
    expect(received.map((m) => m.message), ['hello']);
  });

  test('another room and empty text are dropped', () {
    final danmaku = engine();
    danmaku.decodeMessage(
      frame(danmaku, ['type@=chatmsg/rid@=1234/nn@=a/txt@=elsewhere/dms@=3/', 'type@=chatmsg/rid@=9999/nn@=a/txt@=/']),
    );
    expect(received, isEmpty);
  });

  test('a stream-ended status is a notice and keeps the session open', () {
    final danmaku = engine();
    danmaku.decodeMessage(frame(danmaku, ['type@=rss/rid@=9999/ss@=0/']));
    expect(received.single.type, LiveMessageType.notice);
    expect(closed, isEmpty);
    // Chat after it still arrives.
    danmaku.decodeMessage(frame(danmaku, ['type@=chatmsg/rid@=9999/nn@=a/txt@=back/dms@=3/']));
    expect(received.last.message, 'back');
  });
}
