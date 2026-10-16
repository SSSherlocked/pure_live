import 'package:flutter/gestures.dart' show DeviceGestureSettings, kTouchSlop;
import 'package:flutter/material.dart';

/// A [TabBarView] that a slightly slanted vertical scroll does not turn.
///
/// A list's vertical drag and the pager's horizontal drag compete for every
/// touch, and whichever passes the touch slop first along its own axis wins.
/// With both at the platform slop, a vertical scroll that drifted sideways a
/// little turned the page. The pager's drag here needs [slopFactor] times the
/// slop; the pages keep the platform's own, restored around each of them.
class CalmTabBarView extends StatelessWidget {
  const CalmTabBarView({super.key, required this.children, this.controller, this.physics});

  final List<Widget> children;
  final TabController? controller;
  final ScrollPhysics? physics;

  static const double slopFactor = 2.5;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final settings = media.gestureSettings;
    final slop = settings.touchSlop ?? kTouchSlop;
    return MediaQuery(
      data: media.copyWith(gestureSettings: DeviceGestureSettings(touchSlop: slop * slopFactor)),
      child: TabBarView(
        controller: controller,
        physics: physics,
        children: [
          for (final page in children) MediaQuery(data: media, child: page),
        ],
      ),
    );
  }
}
