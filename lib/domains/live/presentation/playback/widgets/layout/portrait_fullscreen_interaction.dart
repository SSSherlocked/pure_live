import 'package:pure_live/core/index.dart';

/// The least a portrait fullscreen's control bars keep from the screen's
/// bottom and side edges. Android reports no inset for a phone's rounded
/// display corners (and none for the hidden gesture bar in immersive mode), so
/// a bar at the very edge had its end buttons cut by the corners.
const double portraitFullscreenCornerBottomInset = 20;
const double portraitFullscreenCornerSideInset = 16;

bool canEnterPortraitPanelFullscreen({
  required bool isPortraitSource,
  required bool adaptationEnabled,
  required bool adaptiveHeightEnabled,
  required bool compatibilityLayout,
  required bool mobilePlatform,
}) {
  return mobilePlatform && isPortraitSource && adaptationEnabled && adaptiveHeightEnabled && !compatibilityLayout;
}

bool shouldRestorePortraitPanelFromSwipe({required double upwardDistance, required double velocity}) {
  return upwardDistance >= 64 || (velocity <= -850 && upwardDistance >= 24);
}

/// Keeps the portrait-fullscreen restore gesture reachable while the visible
/// bottom controller bar is on top of the full-surface brightness/volume
/// gesture layer. Child buttons still receive taps; a deliberate upward drag
/// wins the gesture arena and restores the room panel.
class PortraitFullscreenRestoreGestureRegion extends StatefulWidget {
  const PortraitFullscreenRestoreGestureRegion({
    super.key,
    required this.enabled,
    required this.onRestore,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onRestore;
  final Widget child;

  @override
  State<PortraitFullscreenRestoreGestureRegion> createState() => _PortraitFullscreenRestoreGestureRegionState();
}

class _PortraitFullscreenRestoreGestureRegionState extends State<PortraitFullscreenRestoreGestureRegion> {
  double _upwardDistance = 0;

  void _reset() {
    _upwardDistance = 0;
  }

  void _update(DragUpdateDetails details) {
    _upwardDistance = (_upwardDistance - details.delta.dy).clamp(0.0, double.infinity).toDouble();
  }

  void _finish(DragEndDetails details) {
    final shouldRestore = shouldRestorePortraitPanelFromSwipe(
      upwardDistance: _upwardDistance,
      velocity: details.primaryVelocity ?? 0,
    );
    _reset();
    if (shouldRestore) widget.onRestore();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: (_) => _reset(),
      onVerticalDragUpdate: _update,
      onVerticalDragEnd: _finish,
      onVerticalDragCancel: _reset,
      child: widget.child,
    );
  }
}
