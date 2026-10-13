import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/consts/app_consts.dart';
import 'package:pure_live/core/player/presentation/left_submenu_button.dart';
import 'package:pure_live/core/player/presentation/player_menu_choice.dart';

/// A choice a home page adds at the end of the top-right menu, such as the
/// 关注 page's 排序: a submenu of [choices] opening to the left, like the
/// player's submenus, the [selected] one bold in the primary colour.
class HomePageMenuAction {
  const HomePageMenuAction({
    required this.icon,
    required this.label,
    required this.choices,
    required this.selected,
    required this.onSelected,
  });

  final IconData icon;
  final String label;
  final List<String> choices;

  /// The index of the current choice; read inside an [Obx].
  final int Function() selected;
  final ValueChanged<int> onSelected;
}

/// The home page's top-right menu: 搜索, 分区 and 热门 (each unless hidden in
/// 设置 › 通用 › 房间卡片设置 › 菜单), 历史 and, after a divider, the page's own
/// [pageAction]. The rest is in the top-left menu ([MenuButton]).
class CommonAppBarActions extends StatelessWidget {
  const CommonAppBarActions({super.key, this.pageAction});

  final HomePageMenuAction? pageAction;

  @override
  Widget build(BuildContext context) {
    final app = SettingsService.to.app;
    final action = pageAction;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MenuAnchor(
          style: homeMenuStyle,
          alignmentOffset: const Offset(0, 4),
          menuChildren: [
            homeMenuItem(
              context,
              icon: Remix.search_line,
              text: i18n("search_live"),
              onPressed: () => Get.toNamed(RoutePath.kSearch),
            ),
            if (app.showsMenu(HomeMenu.areas))
              homeMenuItem(
                context,
                icon: Remix.apps_2_line,
                text: i18n("areas_title"),
                  onPressed: () => Get.toNamed(RoutePath.kAreas),
              ),
            if (app.showsMenu(HomeMenu.popular))
              homeMenuItem(
                context,
                icon: Remix.fire_line,
                text: i18n("popular_title"),
                  onPressed: () => Get.toNamed(RoutePath.kPopular),
              ),
            homeMenuItem(
              context,
              icon: Remix.history_line,
              text: i18n("history"),
              onPressed: () => Get.toNamed(RoutePath.kHistory),
            ),
            if (action != null) ...[
              const Divider(height: 16),
              LeftSubmenuButton(
                key: const ValueKey('home-page-menu-action'),
                style: homeMenuItemStyle,
                leadingIcon: homeMenuIcon(context, action.icon),
                labels: action.choices,
                menuChildren: [
                  for (final (index, choice) in action.choices.indexed)
                    Obx(
                      () => PlayerMenuChoice(
                        key: ValueKey('home-page-menu-choice-$index'),
                        label: choice,
                        labels: action.choices,
                        selected: action.selected() == index,
                        onPressed: () => action.onSelected(index),
                      ),
                    ),
                ],
                child: Text(action.label, style: homeMenuTextStyle(context)),
              ),
            ],
          ],
          builder: (context, menu, _) => homeMenuToggle(
            menu,
            key: const ValueKey('home-more-menu'),
            icon: Remix.menu_search_line,
            tooltip: i18n("more"),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
