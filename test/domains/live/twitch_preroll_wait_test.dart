import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/domains/live/data/stream/twitch_preroll_wait.dart';
import 'package:pure_live/domains/live/domain/twitch_ad_breaks.dart';

String _segment(int n, {bool ad = false}) => '#EXTINF:2.000,${ad ? 'Amazon|1' : 'live'}\nhttps://seg/$n.ts\n';

String _playlist(int first, List<bool> ads) =>
    '#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:$first\n'
    '${[for (int i = 0; i < ads.length; i++) _segment(first + i, ad: ads[i])].join()}';

const String _master =
    '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=6000000\nhttps://edge/source.m3u8\n'
    '#EXT-X-STREAM-INF:BANDWIDTH=1000000\nhttps://edge/480p.m3u8\n';

void main() {
  test('一开播就是片头广告：等到广告后的直播攒够三段才放行', () async {
    final List<String> media = <String>[
      _playlist(1, [true, true, true]),
      _playlist(2, [true, true, false]),
      _playlist(3, [true, false, false, false]),
    ];
    final List<String> reads = <String>[];
    final List<TwitchAdReport> reports = <TwitchAdReport>[];
    final sub = TwitchAdBreaks.reports.listen(reports.add);
    addTearDown(sub.cancel);

    await waitOutTwitchPreroll(
      'https://usher/master.m3u8',
      headers: const {},
      current: () => true,
      interval: Duration.zero,
      read: (url, _) async {
        reads.add(url);
        return url.endsWith('master.m3u8') ? _master : media.removeAt(0);
      },
    );

    // 读的是第一个清晰度，三次媒体清单之后放行。
    expect(reads, ['https://usher/master.m3u8', ...List.filled(3, 'https://edge/source.m3u8')]);
    expect(reports.where((r) => r.ongoing && r.holding), hasLength(2));
    expect(reports.last.ongoing, isFalse);
  });

  test('没有广告、或广告前还有直播可放时立即放行', () async {
    int reads = 0;
    await waitOutTwitchPreroll(
      'https://edge/source.m3u8',
      headers: const {},
      current: () => true,
      interval: Duration.zero,
      read: (_, _) async {
        reads++;
        return _playlist(1, [false, false, true]);
      },
    );
    expect(reads, 1);
  });

  test('离开直播间后不再等待', () async {
    int reads = 0;
    bool open = true;
    await waitOutTwitchPreroll(
      'https://edge/source.m3u8',
      headers: const {},
      current: () => open,
      interval: Duration.zero,
      read: (_, _) async {
        reads++;
        if (reads == 2) open = false;
        return _playlist(1, [true, true]);
      },
    );
    expect(reads, 2);
  });
}
