import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/features/settings/pages/local_config_preview_page.dart';

/// The config preview must never put a credential on screen.
void main() {
  test('masks the cookie section, credential keys and nothing else', () {
    final masked = maskConfigSecrets({
      'backupVersion': 3,
      'cookie': {
        'bilibiliCookie': 'SESSDATA=secret-bili',
        'douyuLtp0': 'secret-ltp0',
        'douyuDid': 'secret-did',
        'douyuCookieSavedAt': 1760000000,
        'huyaCookie': '',
      },
      'webdav': {
        'configs': [
          {'name': 'home', 'address': 'https://dav.example', 'username': 'me', 'password': 'secret-pass'},
        ],
      },
      'favorite': {
        'favoriteRooms': [
          {'nick': 'streamer', 'author': 'visible-author'},
        ],
      },
    });

    final rendered = jsonEncode(masked);
    for (final secret in ['secret-bili', 'secret-ltp0', 'secret-did', 'secret-pass']) {
      expect(rendered, isNot(contains(secret)), reason: '$secret reached the preview');
    }

    final cookie = masked['cookie'] as Map;
    // Numbers and empty values say nothing secret and stay as they are.
    expect(cookie['douyuCookieSavedAt'], 1760000000);
    expect(cookie['huyaCookie'], '');

    final webdav = ((masked['webdav'] as Map)['configs'] as List).single as Map;
    expect(webdav['address'], 'https://dav.example');
    expect(webdav['username'], 'me');

    final room = ((masked['favorite'] as Map)['favoriteRooms'] as List).single as Map;
    expect(room['nick'], 'streamer');
    expect(room['author'], 'visible-author');
    expect(masked['backupVersion'], 3);
  });
}
