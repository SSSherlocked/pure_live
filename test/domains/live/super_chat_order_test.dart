import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/models/live_message.dart';
import 'package:pure_live/domains/live/presentation/playback/controllers/live_play_controller.dart';

LiveSuperChatMessage _sc(String id, int paidSecond, {int seconds = 30}) {
  final start = DateTime.utc(2026, 10, 27, 12, 0, paidSecond);
  return LiveSuperChatMessage(
    messageId: id,
    backgroundBottomColor: '#000000',
    backgroundColor: '#ffffff',
    startTime: start,
    endTime: start.add(Duration(seconds: seconds)),
    face: '',
    message: id,
    price: 10,
    userName: id,
  );
}

void main() {
  test('付费留言按付款时间排列，最新的在最上面，不按到达先后和剩余时间', () {
    final ordered = LivePlayController.superChatsNewestFirst([
      _sc('a', 10, seconds: 300),
      _sc('b', 30),
      _sc('c', 20, seconds: 300),
    ]);
    expect(ordered.map((m) => m.messageId), ['b', 'c', 'a']);
  });

  test('同一条只留第一份；同一时刻付款的，后到的在上面', () {
    final ordered = LivePlayController.superChatsNewestFirst([
      _sc('a', 10),
      _sc('b', 10),
      _sc('a', 10),
    ]);
    expect(ordered.map((m) => m.messageId), ['b', 'a']);
  });
}
