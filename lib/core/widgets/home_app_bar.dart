import 'package:flutter/material.dart';
import 'package:pure_live/core/widgets/menu_button.dart';
import 'package:pure_live/core/widgets/common_appbar_actions.dart';

/// Marks the home shell, whose page carries the shell's two menus.
///
/// 分区 / 热门 / 历史记录 and the rest are opened from those menus as their
/// own routes, outside this scope, and show a back button instead.
class HomeShellScope extends InheritedWidget {
  const HomeShellScope({super.key, required super.child});

  /// Whether the page is the home shell's and carries its menus.
  static bool showsPageActionsOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<HomeShellScope>() != null;

  @override
  bool updateShouldNotify(HomeShellScope oldWidget) => false;
}

/// The app bar of the home page: the page's [title] between the shell's
/// top-left menu and top-right menu.
class HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HomeAppBar({super.key, required this.title, this.centerTitle = true, this.pageAction});

  final Widget title;
  final bool centerTitle;

  /// The page's own entry at the end of the top-right menu.
  final HomePageMenuAction? pageAction;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final showActions = HomeShellScope.showsPageActionsOf(context);
    return AppBar(
      centerTitle: centerTitle,
      leading: showActions ? const MenuButton() : null,
      actions: showActions ? [CommonAppBarActions(pageAction: pageAction)] : null,
      title: title,
    );
  }
}
