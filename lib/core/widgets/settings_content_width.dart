import 'package:flutter/widgets.dart';

/// Holds a settings page body at a fixed content width.
///
/// Settings rows read badly when a wide desktop window stretches them edge to
/// edge, so the body keeps [width] and sits centred; narrower windows still
/// shrink it to fit.
class SettingsContentWidth extends StatelessWidget {
  const SettingsContentWidth({super.key, required this.child});

  static const double width = 720;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: width),
        child: child,
      ),
    );
  }
}
