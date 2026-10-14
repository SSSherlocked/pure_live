import 'package:flutter_test/flutter_test.dart';
import 'package:media_core_media_kit/media_core_media_kit.dart' show MediaKitPlayerAdapter;

void main() {
  test('mpv refusing a seek is not reported as an engine error', () {
    expect(MediaKitPlayerAdapter.isRefusedSeekMessage('Cannot seek in this stream.'), isTrue);
    expect(MediaKitPlayerAdapter.isRefusedSeekMessage("You can force it with '--force-seekable=yes'."), isTrue);
  });

  test('real playback failures still count', () {
    expect(MediaKitPlayerAdapter.isRefusedSeekMessage('Failed to open https://a.example/live.flv.'), isFalse);
    expect(MediaKitPlayerAdapter.isRefusedSeekMessage('tcp: Connection refused'), isFalse);
  });
}
