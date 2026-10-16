import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/core/layout/app_layout.dart';
import 'package:pure_live/core/storage/hive_rx.dart';
import 'package:pure_live/core/storage/hive_pref_util.dart';
import 'package:pure_live/core/config/profiled_settings.dart';
import 'package:pure_live/core/config/font_settings_controller.dart';
import 'package:pure_live/core/config/theme_settings_controller.dart';
import 'package:pure_live/core/config/danmaku_settings_controller.dart';
import 'package:pure_live/core/config/room_card_settings_controller.dart';

final _sizeSpec = ProfiledSpec<double>('size', fallback: 12, read: ProfiledSpec.number(min: 10, max: 20));
final _boldSpec = ProfiledSpec<bool>('bold', fallback: false, read: ProfiledSpec.flag);

/// Lets queued Rx notifications (and the writes they trigger) run.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

Map<String, dynamic> _profileOf(Map<String, dynamic> section, String key, DisplayProfile profile) =>
    Map<String, dynamic>.from((section[key] as Map)[profile.name] as Map);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Hive.openBox<dynamic>('app_settings', bytes: Uint8List(0));
    await HivePrefUtil.init();
  });

  setUp(() async {
    await HivePrefUtil.clear();
  });

  tearDownAll(() async {
    await Hive.close();
  });

  group('显示档位', () {
    test('窄屏是手机，宽屏触控是平板，宽屏鼠标是桌面', () {
      expect(DisplayProfile.of(const AppLayout(wide: false, pointer: true)), DisplayProfile.phone);
      expect(DisplayProfile.of(const AppLayout(wide: false, pointer: false)), DisplayProfile.phone);
      expect(DisplayProfile.of(const AppLayout(wide: true, pointer: false)), DisplayProfile.tablet);
      expect(DisplayProfile.of(const AppLayout(wide: true, pointer: true)), DisplayProfile.desktop);
    });

    test('跟随屏幕时手机横过来仍是手机档位；平板按最短边；指定模式照旧', () {
      const wideTouch = AppLayout(wide: true, pointer: false);
      expect(
        DisplayProfile.resolve(mode: DisplayMode.auto, layout: wideTouch, shortestSide: 411, mobilePlatform: true),
        DisplayProfile.phone,
      );
      expect(
        DisplayProfile.resolve(mode: DisplayMode.auto, layout: wideTouch, shortestSide: 800, mobilePlatform: true),
        DisplayProfile.tablet,
      );
      expect(
        DisplayProfile.resolve(mode: DisplayMode.tablet, layout: wideTouch, shortestSide: 411, mobilePlatform: true),
        DisplayProfile.tablet,
      );
      expect(
        DisplayProfile.resolve(
          mode: DisplayMode.auto,
          layout: const AppLayout(wide: true, pointer: true),
          shortestSide: 411,
          mobilePlatform: false,
        ),
        DisplayProfile.desktop,
      );
    });
  });

  group('ProfiledSettings', () {
    test('首次运行把当前值写进三套；切换先存下未捕获的编辑，再只载入目标那套', () async {
      final size = RxDouble(14);
      final bold = RxBool(false);
      final settings = ProfiledSettings('testProfile', [_sizeSpec.bind(size), _boldSpec.bind(bold)])..init();
      await _settle();
      for (final profile in DisplayProfile.values) {
        expect(jsonDecode(HivePrefUtil.getString('testProfile_${profile.name}')!), {'size': 14.0, 'bold': false});
      }
      expect(settings.profile.value, DisplayProfile.phone);

      size.v = 18;
      expect(settings.use(DisplayProfile.desktop), isTrue);
      expect(size.v, 14);
      size.v = 11;
      bold.v = true;
      await _settle();
      expect(settings.mapFor(DisplayProfile.phone)['size'], 18);
      expect(settings.mapFor(DisplayProfile.tablet)['size'], 14);
      expect(jsonDecode(HivePrefUtil.getString('testProfile_desktop')!), {'size': 11.0, 'bold': true});

      expect(settings.use(DisplayProfile.phone), isTrue);
      expect(size.v, 18);
      expect(bold.v, isFalse);
      await _settle();
      expect(settings.mapFor(DisplayProfile.desktop), {'size': 11.0, 'bold': true});
      expect(settings.use(DisplayProfile.phone), isFalse);
      settings.dispose();
    });

    test('已保存的档位下次启动读回，越界的限界，坏值取当前值', () async {
      await HivePrefUtil.setString('testProfile_tablet', jsonEncode({'size': 99, 'bold': 'x'}));
      final size = RxDouble(14);
      final bold = RxBool(true);
      final settings = ProfiledSettings('testProfile', [_sizeSpec.bind(size), _boldSpec.bind(bold)])
        ..init(initial: DisplayProfile.tablet);
      expect(size.v, 20);
      expect(bold.v, isTrue);
      expect(settings.mapFor(DisplayProfile.phone), {'size': 14.0, 'bold': true});
      settings.dispose();
    });

    test('上次用过的档位作为启动档位', () async {
      await HivePrefUtil.setString(ProfiledSettings.lastProfileKey, 'desktop');
      expect(ProfiledSettings.lastProfile, DisplayProfile.desktop);
      final size = RxDouble(14);
      final settings = ProfiledSettings('testProfile', [_sizeSpec.bind(size)])..init();
      expect(settings.profile.value, DisplayProfile.desktop);
      settings.dispose();
    });

    test('备份：缺少的档位取旧备份的单值，缺少的单值取默认', () {
      final specs = [_sizeSpec, _boldSpec];
      final legacy = ProfiledSettings.parse(specs, null, legacy: (_) => {'size': 16, 'bold': true});
      for (final profile in DisplayProfile.values) {
        expect(legacy[profile.name], {'size': 16.0, 'bold': true});
      }
      final mixed = ProfiledSettings.parse(specs, {
        'desktop': {'size': 12},
        'tablet': 'not a map',
      }, legacy: (_) => {'size': 16});
      expect(mixed['desktop'], {'size': 12.0, 'bold': false});
      expect(mixed['tablet'], {'size': 16.0, 'bold': false});
      expect(mixed['phone'], {'size': 16.0, 'bold': false});
    });
  });

  group('弹幕设置', () {
    const key = DanmakuSettingsController.profilesKey;

    test('旧备份只有单值：三套都取这份', () {
      final parsed = DanmakuSettingsController.parseConfig({
        'danmakuSpeed': 200,
        'danmakuFontSize': 22.0,
        'enableDanmakuStroke': false,
        'chatListFontSize': 18,
        'superChatOpacity': 0.8,
        'hideDanmaku': true,
      });
      for (final profile in DisplayProfile.values) {
        final values = _profileOf(parsed, key, profile);
        expect(values['danmakuSpeed'], 200);
        expect(values['danmakuFontSize'], 22);
        expect(values['enableDanmakuStroke'], isFalse);
        expect(values['chatListFontSize'], 18);
        expect(values['superChatOpacity'], closeTo(0.8, 1e-9));
        expect(values.containsKey('hideDanmaku'), isFalse);
      }
    });

    test('各档位读取并限界，坏值回落到单值', () {
      final parsed = DanmakuSettingsController.parseConfig({
        'danmakuSpeed': 150,
        key: {
          'phone': {'danmakuSpeed': 999, 'danmakuArea': 0.33, 'danmakuFontWeight': 'bold', 'danmakuOpacity': double.nan},
          'tablet': 'not a map',
        },
      });
      final phone = _profileOf(parsed, key, DisplayProfile.phone);
      expect(phone['danmakuSpeed'], 400);
      expect(phone['danmakuArea'], closeTo(0.35, 1e-9));
      expect(phone['danmakuFontWeight'], DanmakuSettingsController.defaultDanmakuFontWeight);
      expect(phone['danmakuOpacity'], DanmakuSettingsController.defaultDanmakuOpacity);
      expect(_profileOf(parsed, key, DisplayProfile.tablet)['danmakuSpeed'], 150);
      expect(_profileOf(parsed, key, DisplayProfile.desktop)['danmakuSpeed'], 150);
    });

    test('extractConfig 带出三套，可以写进 JSON', () {
      final extracted = DanmakuSettingsController.extractConfig({
        'danmaku': {
          'danmakuSpeed': 180,
          key: {
            'desktop': {'danmakuSpeed': 60},
          },
        },
      });
      expect(() => jsonEncode(extracted), returnsNormally);
      expect(_profileOf(extracted, key, DisplayProfile.phone)['danmakuSpeed'], 180);
      expect(_profileOf(extracted, key, DisplayProfile.desktop)['danmakuSpeed'], 60);
    });

    test('切换只载入另一套，离开的那套保持不变；导出带出三套', () async {
      final settings = DanmakuSettingsController()..onStart();
      expect(settings.profile.value, DisplayProfile.phone);

      settings.danmakuSpeed.v = 200;
      settings.chatListFontSize.v = 20;
      // 编辑还没被异步捕获就切换：切换前先把它记进手机那套。
      settings.useProfile(DisplayProfile.tablet);
      expect(settings.profile.value, DisplayProfile.tablet);
      expect(settings.profiles.mapFor(DisplayProfile.phone)['danmakuSpeed'], 200);
      expect(settings.danmakuSpeed.v, DanmakuSettingsController.defaultDanmakuSpeed);
      expect(settings.chatListFontSize.v, DanmakuSettingsController.defaultChatListFontSize);

      settings.danmakuSpeed.v = 90;
      settings.superChatFontScale.v = 1.4;
      await _settle();
      expect(settings.profiles.mapFor(DisplayProfile.tablet)['danmakuSpeed'], 90);
      expect(settings.profiles.mapFor(DisplayProfile.desktop)['danmakuSpeed'], DanmakuSettingsController.defaultDanmakuSpeed);

      settings.useProfile(DisplayProfile.phone);
      expect(settings.danmakuSpeed.v, 200);
      expect(settings.chatListFontSize.v, 20);
      expect(settings.superChatFontScale.v, DanmakuSettingsController.defaultSuperChatFontScale);
      await _settle();

      final exported = settings.toJson();
      expect(exported['danmakuSpeed'], 200);
      expect(_profileOf(exported, key, DisplayProfile.phone)['danmakuSpeed'], 200);
      expect(_profileOf(exported, key, DisplayProfile.tablet)['danmakuSpeed'], 90);
      expect(_profileOf(exported, key, DisplayProfile.tablet)['superChatFontScale'], closeTo(1.4, 1e-9));
      settings.profiles.dispose();
    });

    test('导入旧备份：三套都换成备份里的单值', () async {
      final settings = DanmakuSettingsController()..onStart();
      settings.fromJson({'danmakuSpeed': 300, 'danmakuOpacity': 0.5, 'superChatOpacity': 0.7});
      expect(settings.danmakuSpeed.v, 300);
      expect(settings.superChatOpacity.v, closeTo(0.7, 1e-9));
      for (final profile in DisplayProfile.values) {
        final values = settings.profiles.mapFor(profile);
        expect(values['danmakuSpeed'], 300);
        expect(values['danmakuOpacity'], 0.5);
      }
      await _settle();
      settings.profiles.dispose();
    });

    test('开发版的窄屏/宽屏样式作为首次运行的来源：窄屏给手机，宽屏给平板和桌面', () async {
      await HivePrefUtil.setString('danmakuStyleNarrow', jsonEncode({'speed': 60, 'stroke': false}));
      await HivePrefUtil.setString('danmakuStyleWide', jsonEncode({'speed': 300}));
      final settings = DanmakuSettingsController()..onStart();
      expect(settings.danmakuSpeed.v, 60);
      expect(settings.enableDanmakuStroke.v, isFalse);
      expect(settings.profiles.mapFor(DisplayProfile.tablet)['danmakuSpeed'], 300);
      expect(settings.profiles.mapFor(DisplayProfile.desktop)['danmakuSpeed'], 300);
      expect(settings.profiles.mapFor(DisplayProfile.desktop)['enableDanmakuStroke'], isTrue);
      await _settle();
      expect(HivePrefUtil.containsKey('danmakuStyleNarrow'), isFalse);
      expect(HivePrefUtil.containsKey('danmakuStyleWide'), isFalse);
      settings.profiles.dispose();
    });
  });

  group('房间卡片', () {
    const key = RoomCardSettingsController.profilesKey;

    test('旧备份：窄屏给手机，宽屏给平板和桌面', () {
      final parsed = RoomCardSettingsController.parseConfig({
        'mobileConfig': RoomCardAppearance.compact.toJson(),
        'desktopConfig': RoomCardAppearance.detailed.toJson(),
        'mobileColumns': 2,
        'desktopCardWidth': 300,
      });
      // The one look of an old backup starts both layouts' looks; the
      // layout it had is the one 主页关注 shows.
      final phone = _profileOf(parsed, key, DisplayProfile.phone);
      expect(phone['favoriteLayout'], 'compact');
      expect(phone['compactConfig'], RoomCardAppearance.compact.toJson());
      expect(phone['compactColumns'], 2);
      expect(phone['coverColumns'], 2);
      expect(phone['compactCardWidth'], RoomCardSettingsController.autoCardWidth);
      for (final profile in [DisplayProfile.tablet, DisplayProfile.desktop]) {
        final values = _profileOf(parsed, key, profile);
        expect(values['favoriteLayout'], 'cover');
        expect(values['coverConfig'], RoomCardAppearance.detailed.toJson());
        expect(values['coverCardWidth'], 300);
        expect(values['compactCardWidth'], 300);
        expect(values['coverColumns'], RoomCardSettingsController.autoColumns);
      }
    });

    test('新备份的三套各自读回', () {
      final parsed = RoomCardSettingsController.parseConfig({
        key: {
          'tablet': {'config': RoomCardAppearance.compact.toJson(), 'columns': 99},
        },
      });
      final tablet = _profileOf(parsed, key, DisplayProfile.tablet);
      expect(tablet['favoriteLayout'], 'compact');
      expect(tablet['compactConfig'], RoomCardAppearance.compact.toJson());
      expect(tablet['compactColumns'], RoomCardSettingsController.maxColumns);
      expect(_profileOf(parsed, key, DisplayProfile.desktop)['coverConfig'], RoomCardAppearance.standard.toJson());
      final extracted = RoomCardSettingsController.extractConfig({
        'roomCard': {
          key: {
            'desktop': {'cardWidth': 50},
          },
        },
      });
      expect(() => jsonEncode(extracted), returnsNormally);
      expect(_profileOf(extracted, key, DisplayProfile.desktop)['coverCardWidth'], RoomCardSettingsController.minCardWidth);
    });

    test('首次运行从旧的窄屏/宽屏设置播种；编辑只改当前档位', () async {
      await HivePrefUtil.setString('room_card_desktop_config', jsonEncode(RoomCardAppearance.detailed.toJson()));
      await HivePrefUtil.setInt('room_card_desktop_columns', 3);
      final settings = RoomCardSettingsController()..onStart();
      expect(settings.profile.value, DisplayProfile.phone);
      expect(settings.resolve(), RoomCardAppearance.compact);

      settings.useProfile(DisplayProfile.desktop);
      expect(settings.resolve(), RoomCardAppearance.detailed);
      expect(settings.currentColumns, 3);
      settings.updateConfig(RoomCardAppearance.detailed.copyWith(cornerRadius: 8));
      settings.setColumns(RoomCardLayout.cover, 5);
      await _settle();
      expect(settings.profiles.mapFor(DisplayProfile.tablet)['coverConfig'], RoomCardAppearance.detailed.toJson());
      expect(settings.profiles.mapFor(DisplayProfile.tablet)['coverColumns'], 3);
      // The other layout keeps its own look.
      expect(settings.appearanceFor(RoomCardLayout.compact).layout, RoomCardLayout.compact);
      expect(settings.columnsFor(RoomCardLayout.compact), 3);

      settings.reset();
      expect(settings.resolve(), RoomCardAppearance.standard);
      settings.useProfile(DisplayProfile.phone);
      final exported = settings.toJson();
      expect(exported['mobileConfig'], RoomCardAppearance.compact.toJson());
      expect(exported['desktopConfig'], RoomCardAppearance.standard.toJson());
      expect(exported['desktopColumns'], 5);
      settings.profiles.dispose();
    });
  });

  group('字体与主题', () {
    test('旧备份的字号和间距填满三套，新备份按档位读回', () {
      final font = FontSettingsController.parseConfig({
        'textScaleFactor': 1.3,
        FontSettingsController.profilesKey: {
          'desktop': {'textScaleFactor': 0.9},
        },
      });
      expect(_profileOf(font, FontSettingsController.profilesKey, DisplayProfile.phone)['textScaleFactor'], 1.3);
      expect(_profileOf(font, FontSettingsController.profilesKey, DisplayProfile.desktop)['textScaleFactor'], 0.9);

      final theme = ThemeSettingsController.parseConfig({'crossAxisSpacing': 10, 'livePanelWidth': 9999});
      for (final profile in DisplayProfile.values) {
        final values = _profileOf(theme, ThemeSettingsController.profilesKey, profile);
        expect(values['crossAxisSpacing'], 10);
        expect(values['livePanelWidth'], 720);
      }
    });
  });
}
