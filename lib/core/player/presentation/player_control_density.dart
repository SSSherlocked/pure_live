import 'package:flutter/material.dart';

/// Hit-target extent of a player action in the compact layout.
const double compactPlayerActionExtent = 36;

/// How much the compact layout shrinks icons (24 → 20, 28 → 23).
const double compactPlayerIconScale = 0.82;

/// Whether a player uses the compact control layout: the phone layout when the
/// player is not fullscreen. The inline player is then a strip of the page, so
/// its floating controls are smaller and closer together; fullscreen keeps the
/// full size.
bool useCompactInlinePlayerControls({required bool fullscreen, required bool phoneLayout}) {
  return phoneLayout && !fullscreen;
}

/// Tells the player's action buttons below it whether to use the compact
/// layout, so the bars switch every button at once instead of threading a flag
/// through each one.
class PlayerControlDensity extends InheritedWidget {
  const PlayerControlDensity({super.key, required this.compact, required super.child});

  /// The density scope plus, when [compact], a smaller default icon for every
  /// [IconButton] below that does not set its own size.
  static Widget scope({required bool compact, required Widget child}) {
    return PlayerControlDensity(
      compact: compact,
      child: compact
          ? IconButtonTheme(
              data: IconButtonThemeData(
                style: ButtonStyle(iconSize: WidgetStatePropertyAll<double>(24 * compactPlayerIconScale)),
              ),
              child: child,
            )
          : child,
    );
  }

  final bool compact;

  static bool compactOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlayerControlDensity>()?.compact ?? false;

  /// The minimum size of one player action button.
  static BoxConstraints actionConstraints(BuildContext context) {
    final extent = compactOf(context) ? compactPlayerActionExtent : kMinInteractiveDimension;
    return BoxConstraints(minWidth: extent, minHeight: extent);
  }

  /// An icon size a button sets explicitly, scaled for the compact layout.
  static double iconSize(BuildContext context, double normal) {
    return compactOf(context) ? (normal * compactPlayerIconScale).roundToDouble() : normal;
  }

  @override
  bool updateShouldNotify(PlayerControlDensity oldWidget) => oldWidget.compact != compact;
}
