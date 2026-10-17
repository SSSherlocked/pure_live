import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/widgets/stream_format_tag.dart';
import 'package:pure_live/shared/platforms/live_site.dart' show LiveStreamFormat;
import 'package:pure_live/domains/live/presentation/playback/states/player_state.dart';

void main() {
  test('the URL path tells FLV and HLS, and nothing else', () {
    expect(streamFormatTagOfUrl('https://cdn.example.com/live/room.flv?token=a.m3u8'), 'FLV');
    expect(streamFormatTagOfUrl('https://cdn.example.com/live/index.M3U8?t=1'), 'HLS');
    expect(streamFormatTagOfUrl('http://192.168.1.2:4022/rtp/239.0.0.1'), isNull);
    expect(streamFormatTagOfUrl(''), isNull);
  });

  test('a line takes the site facts first, then its path', () {
    const flvByFacts = 'https://cdn.example.com/stream?format=1';
    const hlsByPath = 'https://cdn.example.com/a/playlist.m3u8';
    const unknown = 'https://cdn.example.com/stream';
    final state = PlayerState(
      playUrls: const [flvByFacts, hlsByPath, unknown],
      streamFacts: const {flvByFacts: (format: LiveStreamFormat.flv, codec: null, unresolvedChildren: false)},
    );
    expect(state.lineFormatTags, ['FLV', 'HLS', null]);
    expect(state.lineFormatTag(3), isNull);
  });
}
