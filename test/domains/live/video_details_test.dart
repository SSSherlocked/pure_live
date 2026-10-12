import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/domains/live/presentation/playback/dialogs/video_details_dialog.dart';

void main() {
  test('bitrates read as kbps or Mbps, and missing ones are left out', () {
    expect(formatBitrate('2500000'), '2.50 Mbps');
    expect(formatBitrate('128000'), '128 kbps');
    expect(formatBitrate(''), isNull);
    expect(formatBitrate('0'), isNull);
    expect(formatBitrate(null), isNull);
  });

  test('mpv values become rows; absent ones are skipped', () {
    final rows = buildVideoDetails(
      quality: '原画',
      line: '线路1',
      engine: 'media_kit',
      host: 'cdn.example.com',
      width: 1920,
      height: 1080,
      mpv: const {
        'video-codec': 'h264',
        'estimated-vf-fps': '59.94',
        'hwdec-current': 'mediacodec',
        'video-bitrate': '6000000',
        'audio-codec-name': 'aac',
        'audio-params/samplerate': '48000',
        'file-format': 'flv',
        'frame-drop-count': '2',
        'decoder-frame-drop-count': '1',
      },
    );
    final byKey = {for (final row in rows) row.labelKey: row.value};

    expect(byKey['video_details_resolution'], '1920 × 1080');
    expect(byKey['video_details_video_codec'], 'h264');
    expect(byKey['video_details_frame_rate'], '59.94 fps');
    expect(byKey['video_details_hwdec'], 'mediacodec');
    expect(byKey['video_details_video_bitrate'], '6.00 Mbps');
    expect(byKey['video_details_audio_format'], '48000 Hz');
    expect(byKey['video_details_container'], 'flv');
    expect(byKey['video_details_dropped'], '3');
    expect(byKey.containsKey('video_details_audio_bitrate'), isFalse);
    expect(byKey['video_details_host'], 'cdn.example.com');
  });

  test('engines without mpv show only what the player itself knows', () {
    final rows = buildVideoDetails(
      quality: '高清',
      line: '线路2',
      engine: 'exo',
      host: '',
      width: null,
      height: null,
      mpv: null,
    );
    expect(rows.map((row) => row.labelKey), [
      'video_details_quality',
      'video_details_line',
      'video_details_engine',
    ]);
  });
}
