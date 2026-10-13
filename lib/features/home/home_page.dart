import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pure_live/core/index.dart';
import 'package:move_to_desktop/move_to_desktop.dart';
import 'package:pure_live/core/platform/initial_room_handoff.dart';
import 'package:pure_live/core/player/models/player_engine.dart';
import 'package:pure_live/domains/live/presentation/favorite/favorite_page.dart';
import 'package:pure_live/domains/live/domain/global_player_service.dart';

/// The home page: 关注, between the top-left and top-right menus. 分区, 热门
/// and every other page open from those menus as their own routes.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  /// Widest the phone layout grows: phone mode on a large screen keeps a
  /// phone-width column instead of stretching the cards.
  static const double maxPhoneContentWidth = 600;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with AutomaticKeepAliveClientMixin {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
      if (Platform.isAndroid) {
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Theme.of(context).navigationBarTheme.backgroundColor,
          ),
        );
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }

      final initialRoom = InitialRoomHandoff.take();
      if (initialRoom != null && mounted) {
        // MyApp prepares the global manager asynchronously while leaving the
        // native decoder cold. Reusing that same initialization Future keeps a
        // command-line room from racing a second manager into existence.
        if (!GlobalPlayerService.instance.initialized) {
          await GlobalPlayerService.instance.initialize(defaultEngine: PlayerEngine.mediaKit);
        }
        if (!mounted) return;
        await AppNavigator.toLiveRoomDetail(liveRoom: initialRoom);
      }
    });
  }

  void onBackButtonPressed(bool didPop, _) {
    if (!didPop) {
      MoveToDesktop().moveToDesktop();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // One widget shape at every width, so crossing the breakpoint never
    // remounts the page; only the width limit changes.
    final layout = AppLayout.of(context);
    final limit = layout.phone && MediaQuery.sizeOf(context).width > AppLayout.wideBreakpoint
        ? HomePage.maxPhoneContentWidth
        : double.infinity;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: onBackButtonPressed,
      child: HomeShellScope(
        child: ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: limit),
              child: const FavoritePage(),
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
