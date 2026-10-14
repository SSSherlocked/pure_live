import 'dart:ui' show Size;

/// Scrolling-danmaku speed relative to the width it scrolls across.
///
/// The configured speed is in px/s, and it reads right in a fullscreen. The
/// inline player is much narrower - on a phone the screen's short side, on a
/// desktop the window minus the side panel - so the same px/s made every
/// message cross it far sooner. The speed therefore scales with the surface
/// width against the screen's (on a desktop, the window's) long side: a
/// message takes the same time to cross the inline player as the fullscreen
/// one, on every platform. Switching between the two rescales the messages
/// already on screen too (the barrage engine applies a new speed to them).
///
/// The surface that lays the barrage out records the scale per barrage
/// controller; everything else that sends speeds to that controller (its config
/// pushes, per-message styles) reads it back, so they never disagree.
abstract final class DanmakuSpeedScale {
  static final Expando<double> _scales = Expando<double>('danmaku-speed-scale');

  /// Slowest allowed factor, so a very narrow surface still moves.
  static const double minScale = 0.3;

  /// The scale for a surface [surfaceWidth] wide on a [screen].
  static double resolve({required double surfaceWidth, required Size screen}) {
    final reference = screen.longestSide;
    if (!surfaceWidth.isFinite || surfaceWidth <= 0 || reference <= 0) return 1.0;
    return (surfaceWidth / reference).clamp(minScale, 1.0).toDouble();
  }

  /// The last scale recorded for [controller], 1.0 before its first layout.
  static double of(Object controller) => _scales[controller] ?? 1.0;

  static void record(Object controller, double scale) => _scales[controller] = scale;
}
