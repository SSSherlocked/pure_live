import 'package:flutter/material.dart';
import 'package:pure_live/core/widgets/menu_button.dart';
import 'package:pure_live/core/widgets/common_appbar_actions.dart';

/// The home shell's current layout, published to the pages it shows.
///
/// The shell decides phone versus wide layout from its own constraints, once;
/// pages read that decision instead of each measuring the screen. A page that
/// measured `Get.width` itself kept whatever it saw last — e.g. a landscape
/// width captured while a room was fullscreen — and lost its icons after
/// returning to portrait.
class HomeShellScope extends InheritedWidget {
  const HomeShellScope({super.key, required this.wide, required super.child});

  /// The wide (navigation rail) layout; false for the phone layout.
  final bool wide;

  /// Null outside the home shell (a page opened on its own route).
  static bool? wideOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<HomeShellScope>()?.wide;

  /// Whether the page carries the shell's entries — the settings gear and the
  /// top-right menu. Only the phone layout does: the wide one has its rail.
  static bool showsPageActionsOf(BuildContext context) => wideOf(context) == false;

  @override
  bool updateShouldNotify(HomeShellScope oldWidget) => oldWidget.wide != wide;
}

/// The app bar of a home page: the page's [title], plus the shell's settings
/// gear and top-right menu whenever the shell is in its phone layout.
///
/// Every home page uses this one widget, so the two icons follow the shell's
/// layout in one place rather than in a copy per page.
class HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HomeAppBar({super.key, required this.title, this.centerTitle = true});

  final Widget title;
  final bool centerTitle;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final showActions = HomeShellScope.showsPageActionsOf(context);
    return AppBar(
      centerTitle: centerTitle,
      leading: showActions ? const MenuButton() : null,
      actions: showActions ? const [CommonAppBarActions()] : null,
      title: title,
    );
  }
}
