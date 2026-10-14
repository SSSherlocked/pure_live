import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/models/live_message.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/layout/super_chat_card.dart';

LiveSuperChatMessage _sc(double price, [SuperChatCurrency currency = SuperChatCurrency.cny]) => LiveSuperChatMessage(
  backgroundBottomColor: '',
  backgroundColor: '',
  endTime: DateTime(2026),
  face: '',
  message: 'hi',
  price: price,
  currency: currency,
  startTime: DateTime(2026),
  userName: 'a',
);

void main() {
  test('whole yuan show without decimals', () {
    expect(_sc(30).priceLabel, '¥30');
  });

  test('fractions are kept to the cent', () {
    expect(_sc(30.5).priceLabel, '¥30.5');
    expect(_sc(12.345).priceLabel, '¥12.35');
  });

  test('foreign platforms show dollars', () {
    expect(_sc(4.99, SuperChatCurrency.usd).priceLabel, r'$4.99');
  });

  test('the same text in another currency is another super chat', () {
    expect(_sc(5) == _sc(5, SuperChatCurrency.usd), isFalse);
  });

  test("the platform's own price note is not shown", () {
    expect(superChatDisplayText('主播加油(来自一元上头条)'), '主播加油');
    expect(superChatDisplayText('主播加油（来自三十元上头条）\n'), '主播加油');
    expect(superChatDisplayText('正常留言'), '正常留言');
  });
}
