import 'package:flutter/material.dart';

/// Width of a player submenu (qualities, lines, 画面比例).
const double playerSubmenuWidth = 152;

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
  });

  final List<Widget> menuChildren;
  final Widget child;
  final Widget? leadingIcon;

  @override
  Widget build(BuildContext context) {
    return SubmenuButton(
      leadingIcon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.arrow_left, size: 18),
          if (leadingIcon != null) ...[const SizedBox(width: 2), leadingIcon!],
        ],
      ),
      // The arrow is drawn before the label instead.
      submenuIcon: const WidgetStatePropertyAll(SizedBox.shrink()),
      alignmentOffset: const Offset(-playerSubmenuWidth, 0),
      menuStyle: const MenuStyle(
        alignment: AlignmentDirectional.topStart,
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 8)),
      ),
      // The offset above assumes this exact width. MenuStyle's minimum size
      // does not reach a submenu panel, which shrank to its labels and left a
      // gap as wide as the difference; sizing every entry pins the panel.
      menuChildren: [for (final item in menuChildren) SizedBox(width: playerSubmenuWidth, child: item)],
      child: child,
    );
  }
}
