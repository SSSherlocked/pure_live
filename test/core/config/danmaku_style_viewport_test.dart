import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/core/config/danmaku_settings_controller.dart';
import 'package:pure_live/core/storage/hive_pref_util.dart';
import 'package:pure_live/core/storage/hive_rx.dart';

const _narrowKey = DanmakuSettingsController.narrowStyleKey;
const _wideKey = DanmakuSettingsController.wideStyleKey;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Hive.openBox<dynamic>('app_settings', bytes: Uint8List(0));
    await HivePrefUtil.init();
  });

  tearDownAll(() async {
    await Hive.close();
  });

  group('弹幕样式备份', () {
    test('旧备份只有单份样式：窄屏和宽屏都取这份', () {
      final parsed = DanmakuSettingsController.parseConfig({
        'danmakuSpeed': 200,
        'danmakuFontSize': 22.0,
        'enableDanmakuStroke': false,
      });
      final narrow = parsed[_narrowKey] as DanmakuOverlayStyle;
      final wide = parsed[_wideKey] as DanmakuOverlayStyle;
      expect(narrow.speed, 200);
      expect(narrow.fontSize, 22);
      expect(narrow.stroke, isFalse);
      expect(wide, narrow);
    });

    test('两份样式各自读取并限界，坏值回落到单份的值', () {
      final parsed = DanmakuSettingsController.parseConfig({
        'danmakuSpeed': 150,
        _narrowKey: {'speed': 999, 'fontSize': 12, 'area': 0.33, 'fontWeight': 'bold', 'opacity': double.nan},
        _wideKey: 'not a map',
      });
      final narrow = parsed[_narrowKey] as DanmakuOverlayStyle;
      final wide = parsed[_wideKey] as DanmakuOverlayStyle;
      expect(narrow.speed, 400);
      expect(narrow.fontSize, 12);
      expect(narrow.area, closeTo(0.35, 1e-9));
      expect(narrow.fontWeight, DanmakuSettingsController.defaultDanmakuFontWeight);
      expect(narrow.opacity, DanmakuSettingsController.defaultDanmakuOpacity);
      expect(wide.speed, 150);
    });

    test('extractConfig 带出两份样式，值是可以写进 JSON 的 Map', () {
      final extracted = DanmakuSettingsController.extractConfig({
        'danmaku': {
          'danmakuSpeed': 180,
          _wideKey: {'speed': 60},
        },
      });
      expect(extracted[_narrowKey], isA<Map<String, dynamic>>());
      expect((extracted[_narrowKey] as Map)['speed'], 180);
      expect((extracted[_wideKey] as Map)['speed'], 60);
    });
  });

  group('按布局切换', () {
    test('切换只载入另一份，离开的那份保持不变', () async {
      final settings = DanmakuSettingsController()..onStart();
      settings.useViewport(false);

      settings.danmakuSpeed.v = 200;
      // 编辑还没被异步捕获就切换布局：切换前先把它记进窄屏那份。
      settings.useViewport(true);
      expect(settings.styleViewportWide.value, isTrue);
      expect(settings.narrowStyle.value.speed, 200);
      expect(settings.danmakuSpeed.v, settings.wideStyle.value.speed);

      settings.danmakuSpeed.v = 90;
      settings.danmakuFontSize.v = 25;
      await Future<void>.delayed(Duration.zero);
      expect(settings.wideStyle.value.speed, 90);
      expect(settings.wideStyle.value.fontSize, 25);
      expect(settings.narrowStyle.value.speed, 200);

      settings.useViewport(false);
      expect(settings.danmakuSpeed.v, 200);
      expect(settings.danmakuFontSize.v, settings.narrowStyle.value.fontSize);
      await Future<void>.delayed(Duration.zero);
      expect(settings.wideStyle.value.speed, 90);

      final exported = settings.toJson();
      expect((exported[_narrowKey] as Map)['speed'], 200);
      expect((exported[_wideKey] as Map)['speed'], 90);
    });

    test('导入旧备份：两份样式都换成备份里的单份值', () async {
      final settings = DanmakuSettingsController()..onStart();
      settings.useViewport(false);
      settings.fromJson({'danmakuSpeed': 300, 'danmakuOpacity': 0.5});
      expect(settings.danmakuSpeed.v, 300);
      expect(settings.danmakuOpacity.v, 0.5);
      expect(settings.narrowStyle.value.speed, 300);
      expect(settings.wideStyle.value.speed, 300);
      expect(settings.wideStyle.value.opacity, 0.5);
    });
  });
}
