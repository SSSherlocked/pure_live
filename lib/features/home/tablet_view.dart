import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/consts/app_consts.dart';

class HomeTabletView extends StatelessWidget {
  final Widget body;
  final int index;
  final List<String> activeMenuIds;
  final bool showRecord;
  final void Function(int) onDestinationSelected;

  const HomeTabletView({
    super.key,
    required this.body,
    required this.index,
    required this.activeMenuIds,
    required this.showRecord,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Builder(
          builder: (context) {
            final List<NavigationRailDestination> destinations = [];
            final List<int> virtualToRealMap = [];

            for (String id in activeMenuIds) {
              final menu = HomeMenu.fromId(id);
              if (menu != null) {
                virtualToRealMap.add(menu.index);

                switch (menu) {
                  case HomeMenu.favorites:
                    destinations.add(
                      NavigationRailDestination(
                        icon: const Icon(Remix.heart_3_line),
                        selectedIcon: const Icon(Remix.heart_3_fill),
                        label: Text(i18n('favorites_title')),
                      ),
                    );
                    break;
                  case HomeMenu.popular:
                    destinations.add(
                      NavigationRailDestination(
                        icon: const Icon(Remix.fire_line),
                        selectedIcon: const Icon(Remix.fire_fill),
                        label: Text(i18n('popular_title')),
                      ),
                    );
                    break;
                  case HomeMenu.areas:
                    destinations.add(
                      NavigationRailDestination(
                        icon: const Icon(Remix.apps_2_line),
                        selectedIcon: const Icon(Remix.apps_2_fill),
                        label: Text(i18n('areas_title')),
                      ),
                    );
                    break;
                  case HomeMenu.record:
                    destinations.add(
                      NavigationRailDestination(
                        icon: const Icon(Remix.download_2_line),
                        selectedIcon: const Icon(Remix.download_2_fill),
                        label: Text(i18n('record_center')),
                      ),
                    );
                    break;
                }
              }
            }

            int? activeSelectedIndex;
            final pos = virtualToRealMap.indexOf(index);
            if (pos >= 0 && pos < destinations.length) {
              activeSelectedIndex = pos;
            } else {
              activeSelectedIndex = null;
            }

            return Row(
              children: [
                NavigationRail(
                  // Destinations follow the menu button directly; 设置 sits at
                  // the bottom edge. 多画面 / 链接解析 / 全平台搜索 / 录制中心
                  // live in the menu.
                  groupAlignment: -1,
                  minWidth: 64,
                  labelType: NavigationRailLabelType.all,
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: MenuButton(railActions: true, showRecord: showRecord),
                  ),
                  trailing: Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: IconButton(
                          key: const ValueKey('home-rail-settings'),
                          tooltip: i18n('settings_title'),
                          onPressed: () => Get.toNamed(RoutePath.kSettings),
                          icon: const Icon(Remix.settings_5_line),
                        ),
                      ),
                    ),
                  ),
                  destinations: destinations,
                  selectedIndex: activeSelectedIndex,
                  onDestinationSelected: (int virtualIndex) {
                    if (virtualIndex >= 0 && virtualIndex < virtualToRealMap.length) {
                      onDestinationSelected(virtualToRealMap[virtualIndex]);
                    }
                  },
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: destinations.isEmpty
                      ? AppStatusView(
                          type: AppStatusType.empty,
                          icon: Remix.menu_2_fill,
                          title: i18n('no_menu_title'),
                          subtitle: i18n('no_menu_subtitle'),
                        )
                      : body,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
