import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart';
import 'package:pure_live/domains/live/data/stream/line_preflight.dart';

PlayerSource _source(String url) => PlayerSource(id: SourceId('live-$url'), uri: Uri.parse(url), type: SourceType.live);

List<String> _urls(List<PlayerSource> sources) => [for (final source in sources) source.uri.toString()];

void main() {
  const v6Dead = 'https://d1--ov-gotcha07.bilivideo.com/live/a.flv?x=1';
  const v6DeadBackup = 'https://d1--ov-gotcha07b.bilivideo.com/live/a.flv?x=1';
  const silent = 'https://d1--ov-gotcha105.bilivideo.com/live/a.m3u8?x=1';
  const healthy = 'https://d1--ov-gotcha207.bilivideo.com/live/index.m3u8?x=1';

  LinePreflight preflight(Map<String, bool> answers, {List<String>? asked}) => LinePreflight(
    probe: (uri, _) async {
      asked?.add(uri.host);
      final answer = answers[uri.host];
      if (answer == null) throw StateError('no answer for ${uri.host}');
      return answer;
    },
  );

  group('线路预检', () {
    test('连不上的线路排到最后，两边各自保持原顺序', () async {
      final ordered = await preflight({
        'd1--ov-gotcha07.bilivideo.com': false,
        'd1--ov-gotcha07b.bilivideo.com': false,
        'd1--ov-gotcha105.bilivideo.com': false,
        'd1--ov-gotcha207.bilivideo.com': true,
      }).order([_source(v6Dead), _source(v6DeadBackup), _source(silent), _source(healthy)]);

      expect(_urls(ordered), [healthy, v6Dead, v6DeadBackup, silent]);
    });

    test('全部可达或全部不可达时原样返回', () async {
      final sources = [_source(v6Dead), _source(healthy)];
      final allUp = await preflight({for (final s in sources) s.uri.host: true}).order(sources);
      final allDown = await preflight({for (final s in sources) s.uri.host: false}).order(sources);
      expect(identical(allUp, sources), isTrue);
      expect(identical(allDown, sources), isTrue);
    });

    test('只有一条可探测的线路时不探测', () async {
      final asked = <String>[];
      final sources = [_source(healthy), _source('http://127.0.0.1:4321/relay/live.flv')];
      final ordered = await preflight({}, asked: asked).order(sources);
      expect(identical(ordered, sources), isTrue);
      expect(asked, isEmpty);
    });

    test('探测抛错按不可达处理', () async {
      final ordered = await preflight({'d1--ov-gotcha207.bilivideo.com': true}).order([
        _source(v6Dead),
        _source(healthy),
      ]);
      expect(_urls(ordered), [healthy, v6Dead]);
    });

    test('同一主机在有效期内只探测一次', () async {
      final asked = <String>[];
      final instance = preflight({
        'd1--ov-gotcha07.bilibili.test': false,
        'd1--ov-gotcha207.bilibili.test': true,
      }, asked: asked);
      final sources = [
        _source('https://d1--ov-gotcha07.bilibili.test/a'),
        _source('https://d1--ov-gotcha207.bilibili.test/b'),
      ];
      await instance.order(sources);
      await instance.order(sources);
      expect(asked, ['d1--ov-gotcha07.bilibili.test', 'd1--ov-gotcha207.bilibili.test']);
    });
  });
}
