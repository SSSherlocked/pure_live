import 'dart:ui' show Size;

/// Scrolling-danmaku speed relative to the width it scrolls across.
///
/// The configured speed is in px/s, and it reads right in a phone's landscape
/// fullscreen. The inline player is the phone's width - roughly half of that -
/// so the same px/s made every message cross in half the time. On phones the
/// speed therefore scales with the surface width against the screen's long
/// side: a message takes the same time to cross the inline player as it does
/// the fullscreen one. Desktop windows keep the plain px/s value.
///
/// The surface that lays the barrage out records the scale per barrage
/// controller; everything else that sends speeds to that controller (its config
/// pushes, per-message styles) reads it back, so they never disagree.
abstract final class DanmakuSpeedScale {
  static final Expando<double> _scales = Expando<double>('danmaku-speed-scale');

  /// Slowest allowed factor, so a very narrow surface still moves.
  static const double minScale = 0.3;

  /// The scale for a surface [surfaceWidth] wide on a [screen].
  static double resolve({required double surfaceWidth, required Size screen, required bool mobile}) {
    final reference = screen.longestSide;
    if (!mobile || !surfaceWidth.isFinite || surfaceWidth <= 0 || reference <= 0) return 1.0;
    return (surfaceWidth / reference).clamp(minScale, 1.0).toDouble();
  }

  /// The last scale recorded for [controller], 1.0 before its first layout.
  static double of(Object controller) => _scales[controller] ?? 1.0;

  static void record(Object controller, double scale) => _scales[controller] = scale;
}
