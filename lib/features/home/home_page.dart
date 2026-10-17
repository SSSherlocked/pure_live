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
    // No PopScope here: Back at the home route is Flutter's default,
    // `SystemNavigator.pop`, which finishes the activity like a plain
    // FlutterActivity (see MainActivity.onBackPressed).
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
