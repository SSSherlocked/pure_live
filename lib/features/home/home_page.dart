import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/domains/live/presentation/favorite/favorite_page.dart';
import 'package:pure_live/features/about/app_update.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      if (Platform.isAndroid) {
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Theme.of(context).navigationBarTheme.backgroundColor,
          ),
        );
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
      // Once the start-up work has settled, look for a newer release.
      Future<void>.delayed(const Duration(seconds: 3), AppUpdate.checkOnStartup);
    });
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
    // No PopScope here: the home route must stay poppable so Flutter tells
    // Android it does not handle Back at the root. On Android 13+ the system
    // then runs its own back-to-home animation with the app's live window;
    // intercepting here and moving the task to back ourselves made the window
    // vanish in one frame and the launcher flash (black, then its icon card).
    // Where Back still reaches Flutter at the root (Android 12 and older, or a
    // hardware key), `SystemNavigator.pop` ends in MainActivity's
    // `popSystemNavigator`, which moves the task to back instead of finishing.
    return HomeShellScope(
      child: ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: limit),
            child: const FavoritePage(),
          ),
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
