import 'package:flutter/material.dart';

/// Width of a player submenu (qualities, lines, 画面比例).
const double playerSubmenuWidth = 152;

/// A [SubmenuButton] whose submenu opens to the left of its menu.
///
/// The player's menus sit at the right edge of the picture (the ⋯ button,
/// the quality/line chip), so a submenu opening to the right lands on the
/// side panel or off the screen. The submenu gets a fixed width and is
/// anchored at the entry's start edge, shifted left by that width; its arrow
/// points the way it opens. Where there is no room on the left either, the
/// menu layout still keeps it on screen.
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
      leadingIcon: leadingIcon,
      submenuIcon: const WidgetStatePropertyAll(Icon(Icons.arrow_left, size: 18)),
      alignmentOffset: const Offset(-playerSubmenuWidth, 0),
      menuStyle: const MenuStyle(
        alignment: AlignmentDirectional.topStart,
        minimumSize: WidgetStatePropertyAll(Size(playerSubmenuWidth, 0)),
        maximumSize: WidgetStatePropertyAll(Size(playerSubmenuWidth, double.infinity)),
      ),
      menuChildren: menuChildren,
      child: child,
    );
  }
}
