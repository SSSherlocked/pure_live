import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/logging/app_log.dart';
import 'package:pure_live/app/router/app_pages.dart';
import 'package:pure_live/app/shell/app_shell.dart';
import 'package:pure_live/core/platform/file_utils.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:pure_live/app/bootstrap/initialized.dart';
import 'package:material_ui/material_ui.dart' as material;
import 'package:pure_live/core/platform/platform_utils.dart';
import 'package:pure_live/core/platform/desktop_manager.dart';
import 'package:pure_live/app/router/navigation_observer.dart';
import 'package:pure_live/core/utils/shared_media_intake.dart';
import 'package:pure_live/core/player/kernel/player_consts.dart';
import 'package:pure_live/core/player/models/player_engine.dart';
import 'package:pure_live/core/platform/share_command_handler.dart';
import 'package:pure_live/core/config/player_settings_controller.dart';
import 'package:pure_live/domains/live/domain/global_player_service.dart';
import 'package:pure_live/core/player/presentation/popup_route_tracker.dart';
import 'package:pure_live/domains/iptv/data/services/epg_import_manager.dart';
import 'package:pure_live/domains/live/data/link/shared_live_link_opener.dart';
import 'package:pure_live/domains/iptv/data/services/iptv_import_manager.dart';
import 'package:pure_live/domains/live/presentation/favorite/favorite_controller.dart';

void main(List<String> args) async {
  // Flutter abbreviates every framework error after the first one. In release
  // builds that abbreviation hides the actual exception behind a diagnostics
  // node, making a grey player surface impossible to diagnose from logcat.
  // Always retain the concrete exception and stack locally on the device.
  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details, forceReport: true);
  };

  Log.captureDebugPrint();
  await AppInitializer().initialize(args);

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('zh')],
      path: 'assets/translations',
      fallbackLocale: const Locale('zh'),
      assetLoader: const RootBundleAssetLoader(),
      child: MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with DesktopWindowMixin {
  SharedMediaReceiver? _sharedMediaReceiver;
  bool _themeChangeScheduled = false;
  ThemeData? _pendingLightTheme;
  ThemeData? _pendingDarkTheme;

  @override
  void initState() {
    super.initState();
    // Start favourite verification after the first Flutter frame instead of
    // waiting until HomePage is created; the first frame still wins over
    // network/JSON work. The controller already publishes the
    // settled room snapshot as one transaction, so cards do not reshuffle as
    // individual requests finish.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && Get.isRegistered<FavoriteController>()) {
        Get.find<FavoriteController>();
      }
    });
    if (PlatformUtils.isDesktop) {
      DesktopManager.initializeListeners(this);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(DesktopManager.updateTrayWhenLocalized());
      });
    }
    unawaited(initSharedMediaListener());
    unawaited(initGlobalPlayer());
  }

  Future<void> initGlobalPlayer() async {
    final String savedKey = SettingsService.to.player.videoPlayerKey.v;
    final String validKey = normalizeVideoPlayerKeyForPlatform(savedKey, defaultTargetPlatform);
    final PlayerEngine targetEngine = PlayerConsts.engines[validKey]!;
    final PlayerEngine defaultEngine;

    if (PlatformUtils.isDesktop) {
      defaultEngine = PlayerEngine.mediaKit;
    } else {
      defaultEngine = targetEngine;
    }
    await GlobalPlayerService.instance.initialize(defaultEngine: defaultEngine);
  }

  @override
  void dispose() {
    if (PlatformUtils.isDesktop) {
      DesktopManager.disposeListeners();
    }
    final receiver = _sharedMediaReceiver;
    if (receiver != null) unawaited(receiver.dispose());
    unawaited(GlobalPlayerService.instance.dispose());
    super.dispose();
  }

  Future<void> initSharedMediaListener() async {
    if (!Platform.isAndroid) return;

    final handler = ShareHandler.instance;
    final intake = SharedMediaIntake(
      isRoomCommand: ShareCommandHandler.isUsableCommand,
      consumeRoomCommand: handleIncomingShareCommand,
      importPlaylist: (path) => IptvImportManager().importFromSharedMedia(SharedMedia(content: path)),
      importEpg: (path) => EpgImportManager().importFromSharedMedia(SharedMedia(content: path)),
      releaseAttachment: (path) async {
        await FileUtils.cleanupOwnedSharedMediaFile(File(path));
      },
      notifyUnsupported: (key) => ToastUtil.show(i18n(key)),
      isLiveLink: SharedLiveLinkOpener.containsLiveLink,
      openLiveLink: SharedLiveLinkOpener(waitForNavigator: waitForShareNavigator).open,
      reportError: (error, stackTrace) => debugPrint('Shared media receiver failed: $error\n$stackTrace'),
    );
    final receiver = SharedMediaReceiver(
      readInitialMedia: handler.getInitialSharedMedia,
      resetInitialMedia: handler.resetInitialSharedMedia,
      mediaStream: handler.sharedMediaStream,
      intake: intake,
      reportError: (error, stackTrace) => debugPrint('Shared media channel failed: $error\n$stackTrace'),
    );
    _sharedMediaReceiver = receiver;
    await receiver.start();
  }

  /// Pushes the rebuilt themes into GetX after the frame.
  ///
  /// GetX reads `GetMaterialApp(theme:, darkTheme:)` only once, at startup, so
  /// a runtime change reaches the pages only through [Get.changeTheme]. Both
  /// themes are pushed: the active brightness cannot be read here (this context
  /// sits above the app's [Theme], so `Theme.of` answers the light fallback),
  /// and pushing only that one left dark-only settings such as 深色模式纯黑背景
  /// without effect.
  void _scheduleThemeChange(ThemeData lightTheme, ThemeData darkTheme) {
    _pendingLightTheme = lightTheme;
    _pendingDarkTheme = darkTheme;
    if (_themeChangeScheduled) return;
    _themeChangeScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _themeChangeScheduled = false;
      final light = _pendingLightTheme;
      final dark = _pendingDarkTheme;
      if (!mounted || light == null || dark == null) return;
      Get.changeTheme(light);
      Get.changeTheme(dark);
    });
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return Obx(() {
          final themeColor = SettingsService.to.theme.themeColor;
          final currentFactor = SettingsService.to.font.textScaleFactor.v;

          ThemeData lightTheme;
          ThemeData darkTheme;

          if (SettingsService.to.theme.enableDynamicTheme.v && lightDynamic != null && darkDynamic != null) {
            lightTheme = MyTheme(colorScheme: toFlutterColorScheme(lightDynamic)).lightThemeData;
            darkTheme = MyTheme(colorScheme: toFlutterColorScheme(darkDynamic)).darkThemeData;
          } else {
            lightTheme = MyTheme(primaryColor: themeColor).lightThemeData;
            darkTheme = MyTheme(primaryColor: themeColor).darkThemeData;
          }
          _scheduleThemeChange(lightTheme, darkTheme);

          return GetMaterialApp(
            // The localized title is rendered by CustomTitleBar. A stable
            // application title avoids asking EasyLocalization for a key
            // before its delegate has completed the first load.
            title: i18n('app_name'),
            navigatorKey: appNavigatorKey,
            scrollBehavior: MyCustomScrollBehavior(),
            debugShowCheckedModeBanner: false,
            themeMode: SettingsService.to.theme.themeMode,
            theme: lightTheme,
            darkTheme: darkTheme,
            locale: context.locale,
            navigatorObservers: [FlutterSmartDialog.observer, LiveRouteObserver(), PopupRouteTracker.instance],
            builder: FlutterSmartDialog.init(
              // Everything painted around the pages lives in [AppShell], which
              // keeps one widget shape so the Router is never remounted.
              builder: (context, child) => AppShell(textScaleFactor: currentFactor, child: child),
            ),
            supportedLocales: context.supportedLocales,
            localizationsDelegates: [
              ...context.localizationDelegates,
              // flex_color_picker 4.x and cached_network_image 4.x use the
              // decoupled Material library. Its localization type is distinct
              // from flutter/material.dart and must be registered alongside it.
              material.GlobalMaterialLocalizations.delegate,
            ],
            initialRoute: RoutePath.kInitial,
            defaultTransition: Transition.native,
            routingCallback: (routing) {
              if (routing != null) {
                RouteObserverController.to.updateRoute(routing.current);
              }
            },
            getPages: AppPages.routes,
          );
        });
      },
    );
  }
}
