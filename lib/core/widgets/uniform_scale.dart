import 'package:flutter/widgets.dart';

/// Shrinks (or enlarges) a whole subtree by [scale] while keeping it laid out
/// for the space it occupies.
///
/// The child is laid out in a box `1 / scale` times the available size and
/// painted scaled back down, so text, buttons, switches and paddings all
/// shrink together and the layout still fills the slot exactly. Hit testing
/// follows the transform.
class UniformScale extends StatelessWidget {
  const UniformScale({super.key, required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (scale == 1) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth / scale;
        final height = constraints.maxHeight / scale;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: width,
            maxWidth: width,
            minHeight: height,
            maxHeight: height,
            child: Transform.scale(scale: scale, alignment: Alignment.topLeft, child: child),
          ),
        );
      },
    );
  }
}
