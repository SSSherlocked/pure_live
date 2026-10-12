import 'package:flutter/material.dart';

/// Inline (non-fullscreen) phone players on screens narrower than this tighten
/// their floating controls and leave out the quality/line chip.
const double compactInlinePlayerMaxScreenWidth = 400;

/// Hit-target extent of a player action in the compact layout: the bare
/// 24 px icon plus its default 8 px IconButton padding on each side.
const double compactPlayerActionExtent = 40;

/// Whether a player uses the compact control layout.
bool useCompactInlinePlayerControls({required double screenWidth, required bool fullscreen, required bool mobile}) {
  return mobile && !fullscreen && screenWidth < compactInlinePlayerMaxScreenWidth;
}

/// Tells the player's action buttons below it whether to use the compact
/// layout, so the bars switch every button at once instead of threading a flag
/// through each one.
class PlayerControlDensity extends InheritedWidget {
  const PlayerControlDensity({super.key, required this.compact, required super.child});

  final bool compact;

  static bool compactOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlayerControlDensity>()?.compact ?? false;

  /// The minimum size of one player action button.
  static BoxConstraints actionConstraints(BuildContext context) {
    final extent = compactOf(context) ? compactPlayerActionExtent : kMinInteractiveDimension;
    return BoxConstraints(minWidth: extent, minHeight: extent);
  }

  @override
  bool updateShouldNotify(PlayerControlDensity oldWidget) => oldWidget.compact != compact;
}
