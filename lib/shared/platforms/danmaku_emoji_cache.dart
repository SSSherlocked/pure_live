import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:pure_live/shared/platforms/danmaku_emoji.dart';

/// Pure helpers behind the on-disk danmaku emoji cache: where a platform's list
/// is refreshed from, how an image's cache file is named and which headers its
/// CDN expects. Kept free of Flutter so they can be unit tested as plain Dart.

const String _chromeUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

const Map<String, String> _platformReferers = <String, String>{
  'bilibili': 'https://live.bilibili.com/',
  'douyin': 'https://live.douyin.com/',
  'douyu': 'https://www.douyu.com/',
  'huya': 'https://www.huya.com/',
};

/// The emoji list on the repository's master branch, used to refresh the seed
/// bundled with the app.
String danmakuEmojiListUrl(String platform) =>
    'https://raw.githubusercontent.com/SSSherlocked/pure_live/master/assets/emo/json/$platform.json';

/// Cache file name of an emoji image: a SHA-1 of its URL plus the image's
/// extension, so the same URL always lands on the same file and a changed URL
/// never reuses a stale one.
String danmakuEmojiCacheFileName(UnifiedEmojiModel model) {
  final digest = sha1.convert(utf8.encode(model.url)).toString();
  return '$digest${danmakuEmojiFileExtension(model)}';
}

/// Lower-case extension (with the dot) taken from `localFile`, then from the URL
/// path; `.png` when neither carries one (Douyin URLs are extensionless).
String danmakuEmojiFileExtension(UnifiedEmojiModel model) {
  final fromLocalFile = _extensionOf(model.localFile);
  if (fromLocalFile != null) return fromLocalFile;
  final fromUrl = _extensionOf(Uri.tryParse(model.url)?.path ?? '');
  return fromUrl ?? '.png';
}

final RegExp _extensionPattern = RegExp(r'^\.[a-z0-9]{1,4}$');

String? _extensionOf(String name) {
  final slash = name.lastIndexOf('/');
  final dot = name.lastIndexOf('.');
  if (dot <= slash) return null;
  final extension = name.substring(dot).toLowerCase();
  return _extensionPattern.hasMatch(extension) ? extension : null;
}

/// Headers for downloading an emoji image. The CDNs check the referer against
/// their own site, and Dart's default `Dart/x.y` user agent is rejected by some
/// of them.
Map<String, String> danmakuEmojiDownloadHeaders(String platform) {
  final referer = _platformReferers[platform];
  return <String, String>{
    'User-Agent': _chromeUserAgent,
    if (referer != null) 'Referer': referer,
  };
}
