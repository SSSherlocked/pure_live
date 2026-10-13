import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/consts/app_consts.dart';

/// An entry a home page adds at the top of the top-right menu, such as the
/// 关注 page's 排序. [onSelected] gets the menu button's context, so a
/// follow-up menu can open where the top-right menu was.
class HomePageMenuAction {
  const HomePageMenuAction({required this.icon, required this.label, required this.onSelected});

  final IconData icon;
  final String label;
  final void Function(BuildContext anchor) onSelected;
}

/// The home page's top-right menu: the page's own [pageAction], then 搜索直播,
/// 分区 and 热门 (each unless hidden in 设置 › 菜单) and 历史记录. The rest
/// is in the top-left menu ([MenuButton]).
class CommonAppBarActions extends StatelessWidget {
  const CommonAppBarActions({super.key, this.pageAction});

  final HomePageMenuAction? pageAction;

  @override
  Widget build(BuildContext context) {
    final app = SettingsService.to.app;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Builder(
          builder: (anchor) => PopupMenuButton<String>(
            key: const ValueKey('home-more-menu'),
            tooltip: i18n("more"),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            offset: const Offset(0, 10),
            position: PopupMenuPosition.under,
            onSelected: (action) {
              switch (action) {
                case 'page':
                  pageAction?.onSelected(anchor);
                case 'search':
                  Get.toNamed(RoutePath.kSearch);
                case 'areas':
                  Get.toNamed(RoutePath.kAreas);
                case 'popular':
                  Get.toNamed(RoutePath.kPopular);
                case 'history':
                  Get.toNamed(RoutePath.kHistory);
              }
            },
            itemBuilder: (context) => [
              if (pageAction case final action?) ...[
                homeMenuItem(context, 'page', action.icon, action.label),
                const PopupMenuDivider(),
              ],
              homeMenuItem(context, 'search', Remix.search_line, i18n("search_live")),
              if (app.showsMenu(HomeMenu.areas)) homeMenuItem(context, 'areas', Remix.apps_2_line, i18n("areas_title")),
              if (app.showsMenu(HomeMenu.popular))
                homeMenuItem(context, 'popular', Remix.fire_line, i18n("popular_title")),
              homeMenuItem(context, 'history', Remix.history_line, i18n("history")),
            ],
            child: const SizedBox.square(
              dimension: kMinInteractiveDimension,
              child: Icon(Remix.menu_search_line, size: 24),
            ),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
