import 'package:flutter/material.dart';

/// Hit-target extent of a player action in the compact layout: the 20 px
/// icon keeps 6 px either side, so neighbouring icons sit 12 px apart.
const double compactPlayerActionExtent = 32;

/// How much the compact layout shrinks icons (24 → 20, 28 → 23).
const double compactPlayerIconScale = 0.82;

/// Tells the player's action buttons below it whether to use the compact
/// layout, so the bars switch every button at once instead of threading a flag
/// through each one.
class PlayerControlDensity extends InheritedWidget {
  const PlayerControlDensity({super.key, required this.compact, required super.child});

  /// The density scope plus, when [compact], a smaller default icon for every
  /// [IconButton] below that does not set its own size.
  ///
  /// Compact buttons also drop Material's padded 48 px tap target and their
  /// own 8 px padding: either one alone kept every button at least 36-48 px
  /// wide, so [compactPlayerActionExtent] never took effect and the narrow
  /// inline bar stayed as spread out as the fullscreen one.
  static Widget scope({required bool compact, required Widget child}) {
    return PlayerControlDensity(
      compact: compact,
      child: compact
          ? IconButtonTheme(
              data: IconButtonThemeData(
                style: ButtonStyle(
                  iconSize: WidgetStatePropertyAll<double>(24 * compactPlayerIconScale),
                  padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(EdgeInsets.zero),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
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
