import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/models/live_message.dart';
import 'package:pure_live/domains/live/domain/danmaku_block_filter.dart';

LiveMessage _chat(String text, {String user = 'viewer'}) =>
    LiveMessage(type: LiveMessageType.chat, userName: user, message: text, color: LiveMessageColor.white);

void main() {
  group('弹幕屏蔽', () {
    test('普通关键词不分大小写包含匹配', () {
      final filter = DanmakuBlockFilter(users: const [], keywords: const ['Spoiler']);
      expect(filter.blocks(_chat('no SPOILERS please')), isTrue);
      expect(filter.blocks(_chat('hello')), isFalse);
    });

    test('/…/ 关键词按正则匹配，不分大小写', () {
      final filter = DanmakuBlockFilter(users: const [], keywords: const ['/^[0-9]+\$/', '/a+b/']);
      expect(filter.blocks(_chat('6666')), isTrue);
      expect(filter.blocks(_chat('666 nice')), isFalse);
      expect(filter.blocks(_chat('xAAB')), isTrue);
    });

    test('写法错误或会拖慢的正则被拒绝，也不会参与匹配', () {
      expect(DanmakuBlockFilter.validate('/[abc/'), 'keyword_regex_invalid');
      expect(DanmakuBlockFilter.validate('/(a+)+b/'), 'keyword_regex_slow');
      expect(DanmakuBlockFilter.validate('/(.*)*/'), 'keyword_regex_slow');
      expect(DanmakuBlockFilter.validate('/^[0-9]+\$/'), isNull);
      expect(DanmakuBlockFilter.validate('plain'), isNull);
      final filter = DanmakuBlockFilter(users: const [], keywords: const ['/[abc/']);
      expect(filter.blocks(_chat('[abc')), isFalse);
    });

    test('单独的 / 或 // 按普通文字处理', () {
      expect(DanmakuBlockFilter.regexBody('/'), isNull);
      expect(DanmakuBlockFilter.regexBody('//'), isNull);
      final filter = DanmakuBlockFilter(users: const [], keywords: const ['//']);
      expect(filter.blocks(_chat('see https://x')), isTrue);
    });

    test('用户名整名匹配，不分大小写；打码的名字不屏蔽', () {
      final filter = DanmakuBlockFilter(users: const ['Alice', '张**'], keywords: const []);
      expect(filter.blocks(_chat('hi', user: 'alice')), isTrue);
      expect(filter.blocks(_chat('hi', user: 'alice2')), isFalse);
      expect(filter.blocks(_chat('hi', user: '张**')), isFalse);
    });
  });
}
