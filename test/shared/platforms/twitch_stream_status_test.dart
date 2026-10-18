import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/models/live_room.dart';
import 'package:pure_live/shared/platforms/twitch/twitch_stream_status.dart';

void main() {
  test('Twitch 的重播（rerun）是录播，直播是直播，没有流是未开播', () {
    expect(twitchStreamStatus(hasStream: true, type: 'live'), LiveStatus.live);
    expect(twitchStreamStatus(hasStream: true, type: 'rerun'), LiveStatus.replay);
    expect(twitchStreamStatus(hasStream: true, type: 'RERUN'), LiveStatus.replay);
    expect(twitchStreamStatus(hasStream: false, type: 'rerun'), LiveStatus.offline);
  });

  test('类型不明时按调用处的默认：频道元数据算未开播，分区列表算直播', () {
    expect(twitchStreamStatus(hasStream: true), LiveStatus.offline);
    expect(twitchStreamStatus(hasStream: true, fallback: LiveStatus.live), LiveStatus.live);
    expect(twitchStreamStatus(hasStream: true, type: 'rerun', fallback: LiveStatus.live), LiveStatus.replay);
  });
}
