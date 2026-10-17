import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/domains/live/data/stream/flv_legacy_hevc_relay.dart';

Uint8List _header(int flags) => Uint8List.fromList([0x46, 0x4c, 0x56, 1, flags, 0, 0, 0, 9, 0, 0, 0, 0]);

void main() {
  test('an audio-only FLV header is served declaring video too', () {
    final out = withVideoDeclared(_header(0x04));
    expect(out[4], 0x05);
    // The rest of the header is untouched.
    expect(out.sublist(0, 4), [0x46, 0x4c, 0x56, 1]);
    expect(out.sublist(5), _header(0x04).sublist(5));
  });

  test('a header that already declares video is passed through', () {
    final header = _header(0x05);
    expect(identical(withVideoDeclared(header), header), isTrue);
  });
}
