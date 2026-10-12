import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The pull-to-refresh icon while the list is being pulled: the three arcs of
/// the app's loading animation (三重连环, `threeArchedCircle`), turned by the
/// pull instead of a timer.
///
/// [progress] is the pull distance over the trigger distance. The arcs grow
/// from dots to full length and turn 240° by the trigger point; the figure
/// repeats every 120°, so at release it matches the spinner's first frame
/// and the spinner takes over without a jump. Same size, stroke and colour as
/// `AppStatusView`'s mini spinner.
class PullArcsIndicator extends StatelessWidget {
  const PullArcsIndicator({super.key, required this.progress, this.size = 24, this.color});

  final double progress;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = progress.isFinite ? progress.clamp(0.0, 1.5).toDouble() : 0.0;
    return SizedBox.square(
      dimension: size,
      child: Padding(
        // The spinner's own inset.
        padding: EdgeInsets.all(size * 0.04),
        child: CustomPaint(
          painter: _PullArcsPainter(
            progress: p,
            color: color ?? Theme.of(context).colorScheme.primary,
            strokeWidth: size * 0.08,
          ),
        ),
      ),
    );
  }
}

class _PullArcsPainter extends CustomPainter {
  _PullArcsPainter({required this.progress, required this.color, required this.strokeWidth});

  final double progress;
  final Color color;
  final double strokeWidth;

  // The spinner's geometry (loading_animation_widget's ThreeArchedCircle).
  static const double _gapAngle = math.pi / 12;
  static const double _minSweep = math.pi / 36;
  static const double _fullSweep = 2 * math.pi / 3 - _gapAngle;
  static const List<double> _starts = [7 * math.pi / 6, math.pi / 2, -math.pi / 6];

  @override
  void paint(Canvas canvas, Size size) {
    final grow = Curves.easeOut.transform(progress.clamp(0.0, 1.0));
    final sweep = _minSweep + (_fullSweep - _minSweep) * grow;
    final turn = progress * 4 * math.pi / 3;
    final center = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: center, radius: size.shortestSide / 2);
    final paint = Paint()
      ..color = color.withValues(alpha: 0.35 + 0.65 * grow)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;
    for (final start in _starts) {
      canvas.drawArc(rect, start + turn, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(_PullArcsPainter old) =>
      old.progress != progress || old.color != color || old.strokeWidth != strokeWidth;
}
