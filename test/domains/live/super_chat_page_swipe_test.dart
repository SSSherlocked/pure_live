import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/core/config/danmaku_settings_controller.dart';
import 'package:pure_live/core/config/font_settings_controller.dart';
import 'package:pure_live/core/config/settings_service.dart';
import 'package:pure_live/core/models/live_message.dart';
import 'package:pure_live/core/storage/hive_pref_util.dart';
import 'package:pure_live/core/widgets/calm_tab_bar_view.dart';
import 'package:pure_live/domains/live/presentation/playback/pages/super_chat_page.dart';
import 'package:pure_live/get/get.dart';

void _ensureControllers() {
  Get.delete<SettingsService>(force: true);
  Get.delete<DanmakuSettingsController>(force: true);
  Get.delete<FontSettingsController>(force: true);
  Get.put(SettingsService(), permanent: true);
  Get.put(DanmakuSettingsController(), permanent: true);
  Get.put(FontSettingsController(), permanent: true);
}

// Already ended: the card starts no countdown timer, so nothing is pending
// when a test finishes. No avatar URL: no network image.
LiveSuperChatMessage _sc(String id) {
  final end = DateTime(2026, 1, 1, 12);
  return LiveSuperChatMessage(
    messageId: id,
    backgroundBottomColor: '#2A60B2',
    backgroundColor: '#EDF5FF',
    endTime: end,
    face: '',
    message: 'super chat message $id that spans the card',
    price: 30,
    startTime: end.subtract(const Duration(minutes: 1)),
    userName: 'user $id',
  );
}

Future<TabController> _pump(WidgetTester tester) async {
  _ensureControllers();
  late TabController controller;
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('zh', 'CN'),
      child: GetMaterialApp(
        home: Scaffold(
          body: DefaultTabController(
            length: 3,
            child: Builder(
              builder: (context) {
                controller = DefaultTabController.of(context);
                return CalmTabBarView(
                  children: [
                    const Center(child: Text('chat tab')),
                    SuperChatPage(messages: [_sc('a'), _sc('b')]),
                    const Center(child: Text('follow tab')),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  controller.index = 1;
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (call) async => call.method == 'getAll' ? <String, Object>{} : true,
    );
    await EasyLocalization.ensureInitialized();
    await Hive.openBox<dynamic>('app_settings', bytes: Uint8List(0));
    await HivePrefUtil.init();
    Get.testMode = true;
  });

  tearDownAll(() async {
    await Hive.close();
  });

  testWidgets('a left swipe on a super chat message turns to the next tab', (tester) async {
    final controller = await _pump(tester);

    await tester.fling(find.textContaining('super chat message a'), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();

    expect(controller.index, 2);
    expect(find.text('follow tab'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a right swipe on a super chat message turns to the previous tab', (tester) async {
    final controller = await _pump(tester);

    await tester.fling(find.textContaining('super chat message b'), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();

    expect(controller.index, 0);
    expect(find.text('chat tab'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the message text no longer claims horizontal drags', (tester) async {
    await _pump(tester);

    expect(find.byType(SelectableText), findsNothing);
  });
}
