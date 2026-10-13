import 'package:flutter/material.dart';
import 'package:pure_live/core/player/presentation/player_menu_choice.dart';

/// Width of a player submenu whose labels are not given.
const double playerSubmenuWidth = 152;

/// The leading column of a player menu entry: a fixed-width slot for the
/// submenu arrow (empty on plain entries), then the entry's icon. Every entry
/// of a menu that has a [LeftSubmenuButton] uses it, so icons and labels line
/// up whether or not an entry opens a submenu.
Widget playerMenuLeading(Widget? icon, {bool arrow = false}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(width: 18, child: arrow ? const Icon(Icons.arrow_left, size: 18) : null),
      if (icon != null) ...[const SizedBox(width: 2), icon],
    ],
  );
}

/// A [SubmenuButton] whose submenu opens to the left of its menu.
///
/// The player's menus sit at the right edge of the picture (the ⋯ button,
/// the quality/line chip), so a submenu opening to the right lands on the
/// side panel or off the screen. The submenu is anchored at the entry's start
/// edge and shifted left by its width, so it sits flush against the menu; its
/// arrow sits before the label and points the way it opens. Where there is no
/// room on the left either, the menu layout still keeps it on screen.
class LeftSubmenuButton extends StatelessWidget {
  const LeftSubmenuButton({
    super.key,
    required this.menuChildren,
    required this.child,
    this.leadingIcon,
    this.labels,
    this.entryLeadingWidth = 0,
  });

  final List<Widget> menuChildren;
  final Widget child;
  final Widget? leadingIcon;

  /// The submenu's labels, when its entries are [PlayerMenuChoice]s: the
  /// submenu is then as wide as the longest one plus the entry padding.
  final List<String>? labels;

  /// Extra width per entry when the submenu's entries carry a leading icon
  /// (icon plus gap) besides their [labels].
  final double entryLeadingWidth;

  @override
  Widget build(BuildContext context) {
    final names = labels;
    final width = names == null
        ? playerSubmenuWidth
        : menuLabelWidth(context, names, PlayerMenuChoice.styleOf(context)) + playerMenuItemPadding + entryLeadingWidth;
    return SubmenuButton(
      leadingIcon: playerMenuLeading(leadingIcon, arrow: true),
      // The arrow is drawn before the label instead.
      submenuIcon: const WidgetStatePropertyAll(SizedBox.shrink()),
      alignmentOffset: Offset(-width, 0),
      menuStyle: const MenuStyle(
        alignment: AlignmentDirectional.topStart,
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 8)),
      ),
      // The offset above assumes this exact width. MenuStyle's minimum size
      // does not reach a submenu panel, which shrank to its labels and left a
      // gap as wide as the difference; sizing every entry pins the panel.
      menuChildren: [for (final item in menuChildren) SizedBox(width: width, child: item)],
      child: child,
    );
  }
}
