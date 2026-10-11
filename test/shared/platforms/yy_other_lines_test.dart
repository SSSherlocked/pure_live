import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/shared/platforms/yy/yy_site.dart';

void main() {
  test('otherLines lists the stream lines it was not served on, in server order', () {
    final payload = {
      'avp_info_res': {
        'stream_line_addr': {
          'stream_a': {
            'line_seq': 10,
            'cdn_info': {'url': 'https://tx.example/a.flv'},
          },
        },
        'stream_line_list': {
          'stream_a': {
            'line_infos': [
              {'line_seq': 10},
              {'line_seq': 14},
              {'line_seq': -1},
              {'line_seq': 14},
              {'line_seq': 22},
            ],
          },
        },
      },
    };
    expect(YYSite.otherLines(payload), [14, 22]);
  });

  test('otherLines is empty without a line list', () {
    expect(YYSite.otherLines(const {}), isEmpty);
    expect(
      YYSite.otherLines({
        'avp_info_res': {
          'stream_line_addr': {
            'stream_a': {'line_seq': 10},
          },
        },
      }),
      isEmpty,
    );
  });
}
