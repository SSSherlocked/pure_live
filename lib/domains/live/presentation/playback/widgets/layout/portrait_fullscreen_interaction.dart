import 'dart:async';
import 'dart:math' as math;

import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/player/presentation/player_control_density.dart';

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

/// Transient guidance shown only after the dedicated portrait fullscreen mode
/// has been entered. Player controls hide first; this affordance follows one
/// second later so the settled screen contains only video and overlay danmaku.
class PortraitFullscreenEntryHint extends StatefulWidget {
  const PortraitFullscreenEntryHint({super.key, this.visibleDuration = const Duration(seconds: 3)});

  final Duration visibleDuration;

  @override
  State<PortraitFullscreenEntryHint> createState() => _PortraitFullscreenEntryHintState();
}

class _PortraitFullscreenEntryHintState extends State<PortraitFullscreenEntryHint> {
  Timer? _hideTimer;
  bool _visible = true;

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(widget.visibleDuration, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void didUpdateWidget(covariant PortraitFullscreenEntryHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visibleDuration == widget.visibleDuration) return;
    _visible = true;
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Above the bottom control bar, which adds the system (or rounded-corner)
    // inset to its height.
    final inset = MediaQuery.viewPaddingOf(context);
    final bottom = math.max(inset.bottom, portraitFullscreenCornerBottomInset);
    return IgnorePointer(
      child: Padding(
        padding: EdgeInsets.fromLTRB(inset.left + 12, 0, inset.right + 12, bottom + compactPlayerBarHeight + 12),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedOpacity(
            key: const ValueKey('portrait-fullscreen-entry-hint-opacity'),
            opacity: _visible ? 1 : 0,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.66),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        i18n('portrait_fullscreen_restore_hint'),
                        key: const ValueKey('portrait-fullscreen-entry-hint'),
                        textAlign: TextAlign.center,
                        style: AppText.of(context).body.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
