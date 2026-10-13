import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/shared/platforms/danmaku_emoji.dart';
import 'package:pure_live/shared/platforms/danmaku_emoji_cache.dart';

UnifiedEmojiModel _model(String url, {String localFile = ''}) =>
    UnifiedEmojiModel(primaryKey: '[dog]', text: '[dog]', url: url, localFile: localFile);

void main() {
  group('弹幕表情缓存文件名', () {
    test('同一 URL 总是同一个文件，内容是 URL 的 SHA-1', () {
      const url = 'http://i0.hdslb.com/bfs/live/4428c84e694fbf4e0ef6c06e958d9352c3582740.png';
      expect(
        danmakuEmojiCacheFileName(_model(url, localFile: 'dog.png')),
        'ffe289fbf25c184d8adc780f2c677bb5040f5c9a.png',
      );
      expect(danmakuEmojiCacheFileName(_model(url, localFile: 'dog.png')), danmakuEmojiCacheFileName(_model(url)));
      expect(danmakuEmojiCacheFileName(_model('$url?v=2')), isNot(danmakuEmojiCacheFileName(_model(url))));
    });

    test('扩展名先看 local_file，再看 URL 路径，都没有就当 png', () {
      expect(danmakuEmojiFileExtension(_model('https://a.cdn/x', localFile: 'smile.GIF')), '.gif');
      expect(danmakuEmojiFileExtension(_model('https://a.cdn/emo/smile.gif?i=1')), '.gif');
      // Douyin URLs carry no extension at all.
      expect(
        danmakuEmojiFileExtension(_model('https://p3-pc-sign.douyinpic.com/obj/tos-cn-i/54a0f6?lk3s=343&from=8')),
        '.png',
      );
      // A dot inside a directory name is not an extension, nor is a dot in a long tail.
      expect(danmakuEmojiFileExtension(_model('https://a.cdn/v1.2/emoji')), '.png');
      expect(danmakuEmojiFileExtension(_model('https://a.cdn/x', localFile: 'name.with.spaces here')), '.png');
    });
  });

  group('弹幕表情下载请求头', () {
    test('带浏览器 UA，并按平台带上自家 Referer', () {
      final bilibili = danmakuEmojiDownloadHeaders('bilibili');
      expect(bilibili['Referer'], 'https://live.bilibili.com/');
      expect(bilibili['User-Agent'], startsWith('Mozilla/5.0'));
      expect(danmakuEmojiDownloadHeaders('douyu')['Referer'], 'https://www.douyu.com/');
      expect(danmakuEmojiDownloadHeaders('huya')['Referer'], 'https://www.huya.com/');
      expect(danmakuEmojiDownloadHeaders('douyin')['Referer'], 'https://live.douyin.com/');
    });

    test('没有表情列表的平台只带 UA', () {
      final headers = danmakuEmojiDownloadHeaders('acfun');
      expect(headers.containsKey('Referer'), isFalse);
      expect(headers['User-Agent'], isNotEmpty);
    });
  });

  test('表情列表从本仓库 master 分支刷新', () {
    expect(
      danmakuEmojiListUrl('huya'),
      'https://raw.githubusercontent.com/SSSherlocked/pure_live/master/assets/emo/json/huya.json',
    );
  });
}
