import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

/// The app's one indeterminate loading animation (三重连环,
/// `threeArchedCircle`), used wherever a Material spinner would go.
///
/// Colour defaults to the theme's primary colour.
class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator({super.key, this.size = large, this.color, this.semanticsLabel});

  /// For buttons, list tiles and other inline spots.
  static const double small = 18;

  /// For pages, dialogs and the player.
  static const double large = 32;

  final double size;
  final Color? color;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final indicator = SizedBox.square(
      dimension: size,
      child: Center(
        child: LoadingAnimationWidget.threeArchedCircle(
          color: color ?? Theme.of(context).colorScheme.primary,
          size: size,
        ),
      ),
    );
    if (semanticsLabel == null) return indicator;
    return Semantics(label: semanticsLabel, child: indicator);
  }
}
