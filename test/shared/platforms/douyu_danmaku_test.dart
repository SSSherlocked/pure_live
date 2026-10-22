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

  // STT nests a map in a value by escaping it: '/' as '@S', '@' as '@A'.
  // Names stay ASCII: the test serializer sizes frames by UTF-16 length.
  test('a paid comm_chatmsg is a super chat priced to the cent', () {
    final danmaku = engine();
    danmaku.decodeMessage(
      frame(danmaku, [
        'type@=comm_chatmsg/btype@=voiceDanmu/rid@=9999/now@=1700000000000/cet@=60/cprice@=3050/'
            'chatmsg@=nn@A=payer@Stxt@A=hello@Sic@A=avatar@S/',
      ]),
    );
    final chat = received.single;
    expect(chat.type, LiveMessageType.superChat);
    final data = chat.data as LiveSuperChatMessage;
    expect(data.price, 30.5);
    expect(data.message, 'hello');
    expect(data.userName, 'payer');
    expect(data.endTime.difference(data.startTime), const Duration(seconds: 60));
  });

  test('a comm_chatmsg notice without price, duration or text is not a super chat', () {
    final danmaku = engine();
    danmaku.decodeMessage(
      frame(danmaku, [
        'type@=comm_chatmsg/btype@=other/rid@=9999/now@=1700000000000/cet@=0/cprice@=0/chatmsg@=nn@A=someone@S/',
        'type@=comm_chatmsg/btype@=voiceDanmu/rid@=9999/now@=1700000000000/cet@=60/cprice@=3000/'
            'chatmsg@=nn@A=someone@Stxt@A=@S/',
      ]),
    );
    expect(received, isEmpty);
  });

  // A 高能弹幕 as Douyu sent it (captured 2026-10-22, names made ASCII): a
  // voice_trlt queue entry, escaped twice, and the same message again as a
  // comm_chatmsg. realPrice is 0; price is the price.
  const voiceEntry =
      'danmuShowSwitch@=1/mtype@=2/totalNum@=0/type@=voice_trlt/list@=vrId@AA=2113275878346604545@ASvocUrl@AA=@AS'
      'uat@AA=https:@AAS@AASapic.douyucdn.cn@AASupload@AASavatar_v3@AAS202602@AASabc_big.jpg@ASstime@AA=30@AS'
      'etimeV2@AA=1792679274@AScontent@AA=go go@ASvocNickUrl@AA=@ASuid@AA=546530475@ASprice@AA=1000@AS'
      'etime@AA=1792679274@ASacptime@AA=1792679244@ASun@AA=payer@ASmf@AA=0@ASisVoc@AA=0@ASrealPrice@AA=0@AS@S/isShow@=1/';
  const voiceChat =
      'vrid@=2113275878346604545/btype@=voiceDanmu/chatmsg@=nn@A=payer@Srid@A=9999@Suid@A=546530475@Stxt@A=go go@S'
      'ic@A=avatar_v3@AS202602@ASabc@S/range@=2/cprice@=1000/cmgType@=1/type@=comm_chatmsg/rid@=9999/gbtemp@=2/'
      'uid@=546530475/crealPrice@=0/cet@=30/now@=1792679244096/csuperScreen@=0/danmucr@=1/';

  test('a 高能弹幕 queue entry is a super chat at its list price, under its id', () {
    final danmaku = engine();
    danmaku.decodeMessage(frame(danmaku, [voiceEntry]));
    final data = received.single.data as LiveSuperChatMessage;
    expect(received.single.type, LiveMessageType.superChat);
    expect(data.price, 10);
    expect(data.message, 'go go');
    expect(data.userName, 'payer');
    expect(data.face, 'https://apic.douyucdn.cn/upload/avatar_v3/202602/abc_big.jpg');
    expect(data.endTime.difference(data.startTime), const Duration(seconds: 30));
    expect(data.messageId, 'douyu:vr:2113275878346604545');
  });

  test('both packets of one 高能弹幕 are the same message', () {
    final danmaku = engine();
    danmaku.decodeMessage(frame(danmaku, [voiceEntry, voiceChat]));
    expect(received, hasLength(2));
    final first = received[0].data as LiveSuperChatMessage;
    final second = received[1].data as LiveSuperChatMessage;
    expect(second.price, 10);
    expect(first, second);
    expect({first, second}, hasLength(1));
  });

  test('a 高能弹幕 leaving the queue is not a new super chat', () {
    final danmaku = engine();
    danmaku.decodeMessage(frame(danmaku, [voiceEntry.replaceFirst('mtype@=2', 'mtype@=3')]));
    expect(received, isEmpty);
  });
}
