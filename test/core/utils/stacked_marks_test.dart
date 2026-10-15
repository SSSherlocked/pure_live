import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/models/live_message.dart';
import 'package:pure_live/core/utils/invisible_placeholders.dart';

void main() {
  test('a long stack of combining marks is cut to two', () {
    final line = 'J${'̩' * 40}';
    expect(limitStackedMarks(line), 'J̩̩');
  });

  test('ordinary accents are kept', () {
    expect(limitStackedMarks('Tiếng Việt café'), 'Tiếng Việt café');
    expect(limitStackedMarks('看点爆了👋'), '看点爆了👋');
  });

  test('chat messages are tamed when they are built', () {
    final message = LiveMessage(
      type: LiveMessageType.chat,
      userName: 'a${'͆' * 10}',
      message: '|${'̍' * 30}',
      color: LiveMessageColor.white,
    );
    expect(message.userName, 'a͆͆');
    expect(message.message, '|̍̍');
  });
}
