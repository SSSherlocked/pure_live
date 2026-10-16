import 'package:flutter/gestures.dart' show DeviceGestureSettings, kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' show SpringDescription;

/// A [TabBarView] that a slightly slanted vertical scroll does not turn.
///
/// A list's vertical drag and the pager's horizontal drag compete for every
/// touch, and whichever passes the touch slop first along its own axis wins.
/// With both at the platform slop, a vertical scroll that drifted sideways a
/// little turned the page. The pager's drag here needs [slopFactor] times the
/// slop; the pages keep the platform's own, restored around each of them.
///
/// A page settling after a swipe takes no touch until it has settled (the
/// pager holds the pointer while it animates), so the settle is quick
/// ([_SnappyPagePhysics]): the new page answers a vertical scroll or a tap
/// almost as soon as the finger lets go.
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
        physics: _SnappyPagePhysics(parent: physics),
        children: [
          for (final page in children) MediaQuery(data: media, child: page),
        ],
      ),
    );
  }
}

/// [physics] with a stiffer spring: TabBarView's page snapping takes its
/// spring from here, and the default one took about half a second to settle.
class _SnappyPagePhysics extends ScrollPhysics {
  const _SnappyPagePhysics({super.parent});

  @override
  _SnappyPagePhysics applyTo(ScrollPhysics? ancestor) => _SnappyPagePhysics(parent: buildParent(ancestor));

  @override
  SpringDescription get spring => SpringDescription.withDampingRatio(mass: 0.5, stiffness: 450, ratio: 1.0);
}
