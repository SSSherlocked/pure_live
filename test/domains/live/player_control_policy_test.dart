import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/layout/app_layout.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/video_player/player_control_policy.dart';

PlayerControlPolicy _policy({
  required AppLayout layout,
  required bool fullscreen,
  bool android = false,
  bool windows = false,
  bool mobilePlatform = false,
}) => PlayerControlPolicy(
  layout: layout,
  fullscreen: fullscreen,
  android: android,
  windows: windows,
  mobilePlatform: mobilePlatform,
);

void main() {
  const phone = AppLayout(wide: false, pointer: false);
  const tablet = AppLayout(wide: true, pointer: false);
  const desktop = AppLayout(wide: true, pointer: true);

  test('the phone inline player is compact, has no quality chip and a centred danmaku sheet', () {
    final inline = _policy(layout: phone, fullscreen: false, android: true, mobilePlatform: true);
    expect(inline.compactControls, isTrue);
    expect(inline.streamSelector, isFalse);
    expect(inline.dockedDanmakuPanel, isFalse);
    expect(inline.tapTogglesControls, isTrue);
  });

  test('fullscreen restores full size, the quality menu and the docked panel on any layout', () {
    for (final layout in [phone, tablet, desktop]) {
      final full = _policy(layout: layout, fullscreen: true);
      expect(full.compactControls, isFalse);
      expect(full.streamSelector, isTrue);
      expect(full.dockedDanmakuPanel, isTrue);
    }
  });

  test('the wide layout keeps the quality menu and docks the panel inline too', () {
    final inline = _policy(layout: tablet, fullscreen: false);
    expect(inline.streamSelector, isTrue);
    expect(inline.dockedDanmakuPanel, isTrue);
    expect(inline.compactControls, isFalse);
  });

  test('outside fullscreen the danmaku settings open in the side panel tab', () {
    for (final layout in [phone, tablet, desktop]) {
      expect(_policy(layout: layout, fullscreen: false).danmakuSettingsInPanel, isTrue);
      expect(_policy(layout: layout, fullscreen: true).danmakuSettingsInPanel, isFalse);
    }
  });

  test('casting is a menu entry on Android only, inline and fullscreen alike', () {
    expect(_policy(layout: phone, fullscreen: false, android: true).castInMoreMenu, isTrue);
    expect(_policy(layout: phone, fullscreen: true, android: true).castInMoreMenu, isTrue);
    expect(_policy(layout: desktop, fullscreen: false, windows: true).castInMoreMenu, isFalse);
  });

  test('top bar slots', () {
    expect(_policy(layout: phone, fullscreen: false, android: true).leadingSlots, isEmpty);
    expect(_policy(layout: phone, fullscreen: true, android: true).leadingSlots, [
      TopActionLeadingSlot.back,
      TopActionLeadingSlot.datetime,
      TopActionLeadingSlot.battery,
    ]);
    expect(_policy(layout: phone, fullscreen: false, android: true).trailingSlots, [TopActionTrailingSlot.pip]);
    expect(_policy(layout: desktop, fullscreen: true, windows: true).trailingSlots, [
      TopActionTrailingSlot.roomHistory,
      TopActionTrailingSlot.datetime,
      TopActionTrailingSlot.battery,
      TopActionTrailingSlot.pip,
    ]);
  });
}
