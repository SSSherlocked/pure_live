import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/config/display_mode_service.dart';
import 'package:pure_live/core/config/danmaku_settings_controller.dart';

DisplayModeInfo _display({double current = 60, double maximum = 0}) => DisplayModeInfo(
  enabled: true,
  currentRefreshRate: current,
  maxRefreshRate: maximum,
  preferredRefreshRate: maximum,
  supportedRefreshRates: const [],
);

void main() {
  group('resolveAdaptiveDanmakuFps', () {
    test('follows the display maximum, not a fixed 60', () {
      expect(DanmakuSettingsController.resolveAdaptiveDanmakuFps(_display(maximum: 120)), 120);
      expect(DanmakuSettingsController.resolveAdaptiveDanmakuFps(_display(maximum: 144)), 144);
      expect(DanmakuSettingsController.resolveAdaptiveDanmakuFps(_display(maximum: 90), pip: true), 90);
    });

    test('falls back to the current rate, then 60', () {
      expect(DanmakuSettingsController.resolveAdaptiveDanmakuFps(_display(current: 90)), 90);
      expect(DanmakuSettingsController.resolveAdaptiveDanmakuFps(null), 60);
    });

    test('stays within the renderer bounds', () {
      expect(DanmakuSettingsController.resolveAdaptiveDanmakuFps(_display(current: 24)), 30);
      expect(DanmakuSettingsController.resolveAdaptiveDanmakuFps(_display(current: 24), pip: true), 24);
      expect(DanmakuSettingsController.resolveAdaptiveDanmakuFps(_display(maximum: 360)), 240);
    });
  });
}
