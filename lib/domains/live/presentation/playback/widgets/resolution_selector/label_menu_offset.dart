import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/player/presentation/player_control_density.dart';

/// Where a quality or line menu opens: right under its label. The button's
/// tap target is taller than the label centred in it, so opening under the
/// button left a gap below the text. [maxHeight] is the height the button's
/// parent allows, which can hold it below its usual tap-target height.
Offset labelMenuOffset(BuildContext context, TextStyle style, double maxHeight) {
  final painter = TextPainter(
    text: TextSpan(text: 'Ag', style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final lineHeight = painter.height;
  painter.dispose();
  final minHeight = PlayerControlDensity.actionConstraints(context).minHeight;
  final target = maxHeight.isFinite && maxHeight < minHeight ? maxHeight : minHeight;
  final gap = ((target - lineHeight) / 2).clamp(0.0, target).toDouble();
  return Offset(0, -gap);
}
