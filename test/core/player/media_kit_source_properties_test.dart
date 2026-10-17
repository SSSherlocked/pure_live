import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart';
import 'package:pure_live/core/player/core/playback_source_hints.dart';
import 'package:pure_live/core/player/kernel/media_kit_live_properties.dart';

const _proxy = 'http://127.0.0.1:7897';

Map<String, String> _properties(String url, {String? declared}) =>
    MediaKitLiveProperties.sourceProperties(uri: Uri.parse(url), declaredFormat: declared, proxy: _proxy);

void main() {
  group('全局引擎属性', () {
    test('探测参数回到 FFmpeg 默认值，只砍掉帧率分析', () {
      // 1 MiB / 1 s 的探测窗口会把晚到的视频轨一起截掉（B 站有声无画，
      // 见 docs/PLAYBACK_CORE.md）；首帧快的真正来源是不再攒 20 帧做帧率分析。
      final properties = MediaKitLiveProperties.build();
      expect(properties.containsKey('demuxer-lavf-probesize'), isFalse);
      expect(properties.containsKey('demuxer-lavf-analyzeduration'), isFalse);
      // 单条键值以字符串写入，与 stream-lavf-o 同一写法（见 build 的注释）。
      expect(properties['demuxer-lavf-o'], 'fpsprobesize=0');
    });
  });

  group('按源决定的引擎属性', () {
    test('上游 HLS 指死解复用器，不可拖动', () {
      expect(_properties('https://cdn.example.com/live/index.m3u8'), {
        'http-proxy': _proxy,
        'demuxer-lavf-format': 'hls',
        'force-seekable': 'no',
        'stream-lavf-o': MediaKitLiveProperties.playlistReconnectOptions,
      });
    });

    test('远端渐进式源保持可拖动', () {
      expect(_properties('https://cdn.example.com/live/room.flv'), {
        'http-proxy': _proxy,
        'demuxer-lavf-format': '',
        // Seekable on purpose: Android's surface-attach seek must not be
        // refused, or the kernel drops the line (see sourceProperties).
        'force-seekable': 'yes',
        'stream-lavf-o': MediaKitLiveProperties.progressiveReconnectOptions,
      });
    });

    test('cache-pause 不再按源决定', () {
      // 全局开启、补 1 秒再续播（见 MediaKitLiveProperties.build），
      // 直播、本机中继和本地文件一视同仁。
      for (final url in const [
        'https://cdn.example.com/live/index.m3u8',
        'https://cdn.example.com/live/room.flv',
        'http://127.0.0.1:4321/abc/live.flv',
      ]) {
        expect(_properties(url).containsKey('cache-pause'), isFalse, reason: url);
      }
    });

    test('平台声明优先于 URL 形状', () {
      // 声明是 flv，就算地址长得像清单也不能按 HLS 解。
      expect(_properties('https://cdn.example.com/live/index.m3u8', declared: 'flv')['demuxer-lavf-format'], '');
      // 声明是 hls，就算地址没有后缀（Twitch 把签名塞在路径里）也要指死。
      expect(
        _properties('https://apn12.playlist.ttvnw.net/v1/playlist/Co0GAIs', declared: 'hls')['demuxer-lavf-format'],
        'hls',
      );
      // 声明 other（IPTV 的 ts、udpxy）不当清单。
      expect(_properties('https://cdn.example.com/live/index.m3u8', declared: 'other')['demuxer-lavf-format'], '');
    });

    test('HLS 清单不把读到结尾当断线', () {
      // 分块传输的清单每次读完都是 End of file；reconnect_streamed 会把它当断线，
      // 在最后一个字节处反复重连（Twitch 10 秒 70 次），清单永远读不完。
      expect(MediaKitLiveProperties.playlistReconnectOptions, isNot(contains('reconnect_streamed')));
      expect(
        _properties('https://apn12.playlist.ttvnw.net/v1/playlist/Co0GAIs', declared: 'hls')['stream-lavf-o'],
        MediaKitLiveProperties.playlistReconnectOptions,
      );
      // 渐进式直播断流仍由 ffmpeg 自己续上。
      expect(MediaKitLiveProperties.progressiveReconnectOptions, contains('reconnect_streamed=1'));
    });

    test('非 HLS 上游清空强制值，不漏给下一条源', () {
      // 引擎跨源复用：上一条源强制的 hls 必须被清掉，否则这条 FLV 会被按 HLS 解。
      expect(_properties('https://cdn.example.com/live/room.flv')['demuxer-lavf-format'], '');
      expect(_properties('http://192.168.1.5:1234/udp/239.0.0.1:5140')['demuxer-lavf-format'], '');
    });

    test('本机输入既不送代理也不猜容器', () {
      // 回环中继：代理转发本机端口既多一跳，也会被拒绝本地目标的代理打死；
      // 而 Dart 重写的 HEVC FLV 中继输出的根本不是 HLS，指死解复用器只会打死它。
      expect(_properties('http://127.0.0.1:4321/ingest/index.m3u8'), {
        'http-proxy': '',
        'demuxer-lavf-format': '',
        // 内容仍然是直播清单，照样不可拖动。
        'force-seekable': 'no',
        'stream-lavf-o': MediaKitLiveProperties.playlistReconnectOptions,
      });
      expect(_properties('http://localhost:4321/live.flv'), {
        'http-proxy': '',
        'demuxer-lavf-format': '',
        'force-seekable': 'yes',
        'stream-lavf-o': MediaKitLiveProperties.progressiveReconnectOptions,
      });
      expect(_properties('http://[::1]:4321/index.m3u8')['http-proxy'], '');
      expect(isPrivatePlaybackInput(Uri(scheme: 'owned', path: 'room')), isTrue);
    });

    test('声明随源的 metadata 往返', () {
      final stamped = PlayerSource(
        id: SourceId('live-1'),
        uri: Uri.parse('https://cdn.example.com/index.m3u8'),
        metadata: playbackStreamFormatMetadata('hls'),
      );
      expect(declaredStreamFormatOf(stamped), 'hls');

      final bare = PlayerSource(id: SourceId('live-2'), uri: Uri.parse('https://cdn.example.com/room.flv'));
      expect(playbackStreamFormatMetadata(null), isEmpty);
      expect(declaredStreamFormatOf(bare), isNull);
    });
  });
}
