import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/platform/background_guide.dart';

BackgroundStatus _status(
  RomFamily family, {
  bool notifications = true,
  bool? mediaChannel,
  bool batteryUnrestricted = true,
  bool backgroundRestricted = false,
  DataSaver dataSaver = DataSaver.off,
}) => BackgroundStatus(
  rom: RomInfo(family: family),
  notifications: notifications,
  mediaChannel: mediaChannel,
  batteryUnrestricted: batteryUnrestricted,
  backgroundRestricted: backgroundRestricted,
  dataSaver: dataSaver,
);

void main() {
  group('romFamilyOf', () {
    test('knows the vendors by manufacturer or brand, in any case', () {
      expect(romFamilyOf('Xiaomi'), RomFamily.xiaomi);
      expect(romFamilyOf('unknown', 'Redmi'), RomFamily.xiaomi);
      expect(romFamilyOf('OnePlus'), RomFamily.oppo);
      expect(romFamilyOf('OPPO'), RomFamily.oppo);
      expect(romFamilyOf('realme'), RomFamily.oppo);
      expect(romFamilyOf('vivo'), RomFamily.vivo);
      expect(romFamilyOf('HUAWEI'), RomFamily.huawei);
      expect(romFamilyOf('HONOR'), RomFamily.honor);
      expect(romFamilyOf('samsung'), RomFamily.samsung);
      expect(romFamilyOf('Meizu'), RomFamily.meizu);
      expect(romFamilyOf('Google', 'google'), RomFamily.other);
    });
  });

  group('detectRom', () {
    test('a OnePlus on ColorOS 15 (CPH2723)', () {
      final rom = detectRom(
        manufacturer: 'OnePlus',
        brand: 'OnePlus',
        model: 'CPH2723',
        sdk: 35,
        props: const {'ro.build.version.oplusrom': 'V15.0.0', 'ro.build.version.oplusrom.display': 'ColorOS 15.0'},
      );
      expect(rom.family, RomFamily.oppo);
      expect(rom.romLabel, 'ColorOS 15.0');
      expect(rom.androidVersion, '15');
    });

    test('ColorOS without the display property uses the version code', () {
      final rom = detectRom(manufacturer: 'OPPO', props: const {'ro.build.version.oplusrom': 'V14.0.1'});
      expect(rom.romLabel, 'ColorOS 14.0.1');
    });

    test('OxygenOS when the build says so', () {
      expect(
        detectRom(manufacturer: 'OnePlus', props: const {'ro.build.version.oplusrom.display': 'OxygenOS 15.0'}).romLabel,
        'OxygenOS 15.0',
      );
      expect(detectRom(manufacturer: 'OnePlus', props: const {'ro.oxygen.version': '11.0.4'}).romLabel, 'OxygenOS 11.0.4');
    });

    test('realme UI', () {
      expect(detectRom(manufacturer: 'realme', props: const {'ro.build.version.realmeui': 'V5.0'}).romLabel, 'realme UI 5.0');
    });

    test('HyperOS and MIUI', () {
      expect(detectRom(manufacturer: 'Xiaomi', props: const {'ro.mi.os.version.name': 'OS2.0'}).romLabel, 'HyperOS 2.0');
      expect(detectRom(manufacturer: 'Xiaomi', props: const {'ro.miui.ui.version.name': 'V125'}).romLabel, 'MIUI 12.5');
      expect(detectRom(manufacturer: 'Xiaomi', props: const {'ro.miui.ui.version.name': 'V140'}).romLabel, 'MIUI 14');
    });

    test('vivo, Huawei, Honor, Samsung, Meizu', () {
      expect(
        detectRom(
          manufacturer: 'vivo',
          props: const {'ro.vivo.os.name': 'OriginOS', 'ro.vivo.os.version': '5.0'},
        ).romLabel,
        'OriginOS 5.0',
      );
      expect(detectRom(manufacturer: 'HUAWEI', props: const {'hw_sc.build.platform.version': '4.2.0'}).romLabel, 'HarmonyOS 4.2.0');
      expect(detectRom(manufacturer: 'HONOR', props: const {'ro.build.version.magic': 'MagicOS_9.0'}).romLabel, 'MagicOS 9.0');
      expect(detectRom(manufacturer: 'samsung', props: const {'ro.build.version.oneui': '60100'}).romLabel, 'One UI 6.1');
      expect(detectRom(manufacturer: 'Meizu', display: 'Flyme 10.5.0.1A').romLabel, 'Flyme 10.5.0.1');
    });

    test('an unknown build shows the manufacturer', () {
      final rom = detectRom(manufacturer: 'Google', model: 'Pixel 9', sdk: 36);
      expect(rom.family, RomFamily.other);
      expect(rom.romLabel, 'Google');
      expect(rom.androidVersion, '16');
    });
  });

  group('BackgroundStatus.fromMap', () {
    test('reads the channel map', () {
      final status = BackgroundStatus.fromMap({
        'sdk': 35,
        'manufacturer': 'OnePlus',
        'brand': 'OnePlus',
        'model': 'CPH2723',
        'display': 'CPH2723_15.0.0.400',
        'props': <Object?, Object?>{'ro.build.version.oplusrom.display': 'ColorOS 15.0', 'ignored': 3},
        'notifications': true,
        'mediaChannel': 'off',
        'batteryUnrestricted': false,
        'backgroundRestricted': true,
        'dataSaver': 'restricted',
        'powerSave': true,
      });
      expect(status.rom.romLabel, 'ColorOS 15.0');
      expect(status.rom.model, 'CPH2723');
      expect(status.mediaChannel, isFalse);
      expect(status.batteryUnrestricted, isFalse);
      expect(status.backgroundRestricted, isTrue);
      expect(status.dataSaver, DataSaver.restricted);
      expect(status.powerSave, isTrue);
    });

    test('missing values read as fine', () {
      final status = BackgroundStatus.fromMap(const {});
      expect(status.notifications, isTrue);
      expect(status.mediaChannel, isNull);
      expect(status.batteryUnrestricted, isTrue);
      expect(status.backgroundRestricted, isFalse);
      expect(status.dataSaver, DataSaver.off);
      expect(status.rom.family, RomFamily.other);
    });
  });

  group('guideSteps', () {
    test('a phone where everything readable is fine', () {
      final steps = guideSteps(_status(RomFamily.other));
      expect(steps.map((step) => step.id), ['notifications', 'battery']);
      expect(pendingSteps(steps), 0);
    });

    test('what is in the way is pending', () {
      final steps = guideSteps(
        _status(
          RomFamily.other,
          batteryUnrestricted: false,
          backgroundRestricted: true,
          dataSaver: DataSaver.restricted,
        ),
      );
      expect(steps.map((step) => step.id), ['notifications', 'battery', 'restricted', 'data_saver']);
      expect(pendingSteps(steps), 3);
    });

    test('notifications off asks for the permission; a muted media channel opens its page', () {
      final off = guideSteps(_status(RomFamily.other, notifications: false)).first;
      expect(off.check, GuideCheck.todo);
      expect(off.action, GuideAction.notifications);

      final muted = guideSteps(_status(RomFamily.other, mediaChannel: false)).first;
      expect(muted.check, GuideCheck.todo);
      expect(muted.action, GuideAction.pages);
      expect(muted.pages.first.extras['android.provider.extra.CHANNEL_ID'], mediaNotificationChannel);
      expect(mediaNotificationChannel, 'media_core.video');
    });

    test('ColorOS gets battery, auto-start and lock-in-recents steps', () {
      final steps = guideSteps(_status(RomFamily.oppo));
      expect(steps.map((step) => step.id), ['notifications', 'battery', 'oppo_battery', 'oppo_autostart', 'lock_recents']);
      expect(steps.where((step) => step.isVendor).length, 3);
    });

    test('every vendor list of pages ends with the app details page', () {
      for (final family in RomFamily.values) {
        for (final step in guideSteps(_status(family))) {
          if (step.action == GuideAction.none) {
            expect(step.pages, isEmpty, reason: step.id);
            continue;
          }
          expect(step.pages, isNotEmpty, reason: step.id);
          expect(step.pages.last.isAppDetails, isTrue, reason: step.id);
        }
      }
    });

    test('only the vendor builds offer the one-time hint', () {
      expect(hasVendorSteps(RomFamily.oppo), isTrue);
      expect(hasVendorSteps(RomFamily.xiaomi), isTrue);
      expect(hasVendorSteps(RomFamily.other), isFalse);
    });

    test('every step text exists in both languages', () {
      Map<String, dynamic> bundle(String lang) =>
          jsonDecode(File('assets/translations/$lang.json').readAsStringSync()) as Map<String, dynamic>;
      final zh = bundle('zh');
      final en = bundle('en');
      for (final family in RomFamily.values) {
        final statuses = [
          _status(family),
          _status(family, notifications: false, batteryUnrestricted: false),
          _status(family, mediaChannel: false, backgroundRestricted: true, dataSaver: DataSaver.restricted),
        ];
        for (final status in statuses) {
          for (final step in guideSteps(status)) {
            for (final key in [step.titleKey, step.howKey, if (step.problemKey != null) step.problemKey!]) {
              expect(zh.containsKey(key), isTrue, reason: key);
              expect(en.containsKey(key), isTrue, reason: key);
            }
          }
        }
      }
    });
  });

  group('BackgroundGuideChannel', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('pure_live/background_guide_test');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    test('is empty off Android', () async {
      const guide = BackgroundGuideChannel(channel: channel, android: false);
      expect(await guide.status(), isNull);
      expect(await guide.open(const [SystemPage.appDetails]), -1);
    });

    test('sends the pages and answers the index that opened', () async {
      Object? sent;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'open') {
          sent = call.arguments;
          return 1;
        }
        return {'manufacturer': 'OnePlus', 'sdk': 35};
      });
      const guide = BackgroundGuideChannel(channel: channel, android: true);
      expect((await guide.status())?.rom.family, RomFamily.oppo);
      final opened = await guide.open(const [
        SystemPage(package: 'com.oplus.battery', className: 'X'),
        SystemPage.appDetails,
      ]);
      expect(opened, 1);
      final pages = (sent! as Map)['pages'] as List;
      expect(pages, hasLength(2));
      expect((pages.last as Map)['packageUri'], isTrue);
    });

    test('a failing native side reads as nothing', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: 'boom'),
      );
      const guide = BackgroundGuideChannel(channel: channel, android: true);
      expect(await guide.status(), isNull);
      expect(await guide.open(const [SystemPage.appDetails]), -1);
    });
  });
}
