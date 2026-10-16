import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/domains/live/domain/stream_replay_policy.dart';

void main() {
  // The order the Huya preflight leaves when hs.flv is dead.
  final huya = [
    Uri.parse('https://al.flv.huya.com/src/a.flv'),
    Uri.parse('https://tx.flv.huya.com/src/a.flv'),
    Uri.parse('https://al.hls.huya.com/src/a.m3u8'),
    Uri.parse('https://tx.hls.huya.com/src/a.m3u8'),
    Uri.parse('https://hs.hls.huya.com/src/a.m3u8'),
    Uri.parse('https://hs.flv.huya.com/src/a.flv'),
  ];

  test('a replaying FLV line moves to the next FLV line on another host', () {
    expect(lineAfterReplay(huya, 0), 1);
    expect(lineAfterReplay(huya, 1), 5);
  });

  test('a replaying manifest moves to the next manifest on another host', () {
    expect(lineAfterReplay(huya, 2), 3);
  });

  test('another kind on another host before the same host', () {
    final lines = [
      Uri.parse('https://a.example/x.flv'),
      Uri.parse('https://a.example/y.flv'),
      Uri.parse('https://b.example/x.m3u8'),
    ];
    expect(lineAfterReplay(lines, 0), 2);
  });

  test('the same host when nothing else is there; nothing for a single line', () {
    final lines = [Uri.parse('https://a.example/x.flv'), Uri.parse('https://a.example/y.flv')];
    expect(lineAfterReplay(lines, 0), 1);
    expect(lineAfterReplay([lines.first], 0), isNull);
    expect(lineAfterReplay(lines, 5), isNull);
  });
}
