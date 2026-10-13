import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/config/danmaku_settings_controller.dart';
import 'package:pure_live/core/models/live_message.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/video_player/player_super_chat_overlay.dart';

LiveSuperChatMessage _sc(String id, DateTime endTime) => LiveSuperChatMessage(
  messageId: id,
  backgroundBottomColor: '#2A60B2',
  backgroundColor: '#EDF5FF',
  endTime: endTime,
  face: '',
  message: 'message $id',
  price: 30,
  startTime: endTime.subtract(const Duration(minutes: 1)),
  userName: 'user $id',
);

void main() {
  final now = DateTime(2026, 1, 1, 12);

  test('a super chat stays on the picture for 15 seconds or until it ends', () {
    expect(playerSuperChatHideAt(_sc('a', now.add(const Duration(minutes: 5))), now), now.add(playerSuperChatDisplayDuration));
    final ending = now.add(const Duration(seconds: 4));
    expect(playerSuperChatHideAt(_sc('b', ending), now), ending);
  });

  test('visible super chats: leaving soonest on top, latest arrivals kept under the cap', () {
    final a = _sc('a', now.add(const Duration(minutes: 5)));
    final b = _sc('b', now.add(const Duration(minutes: 5)));
    final c = _sc('c', now.add(const Duration(minutes: 5)));
    final gone = _sc('gone', now.add(const Duration(minutes: 5)));
    final hideAt = {
      a: now.add(const Duration(seconds: 3)),
      b: now.add(const Duration(seconds: 8)),
      c: now.add(const Duration(seconds: 12)),
      gone: now.subtract(const Duration(seconds: 1)),
    };
    expect(visiblePlayerSuperChats(hideAt, now, maxVisible: 3), [a, b, c]);
    expect(visiblePlayerSuperChats(hideAt, now, maxVisible: 2), [b, c]);
    expect(visiblePlayerSuperChats({gone: hideAt[gone]!}, now, maxVisible: 2), isEmpty);
  });

  test('super chat opacity and text size are bounded and snapped', () {
    expect(DanmakuSettingsController.normalizeSuperChatOpacity(null), DanmakuSettingsController.defaultSuperChatOpacity);
    expect(DanmakuSettingsController.normalizeSuperChatOpacity(0.1), DanmakuSettingsController.minSuperChatOpacity);
    expect(DanmakuSettingsController.normalizeSuperChatOpacity(0.72), closeTo(0.7, 1e-9));
    expect(DanmakuSettingsController.normalizeSuperChatOpacity(double.nan), DanmakuSettingsController.defaultSuperChatOpacity);
    expect(DanmakuSettingsController.normalizeSuperChatFontScale(null), 1.0);
    expect(DanmakuSettingsController.normalizeSuperChatFontScale(3), DanmakuSettingsController.maxSuperChatFontScale);
    expect(DanmakuSettingsController.normalizeSuperChatFontScale(1.24), closeTo(1.2, 1e-9));
  });
}
