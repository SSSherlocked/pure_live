import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/domains/live/presentation/favorite/favorite_sort.dart';
import 'package:pure_live/domains/live/presentation/favorite/room_grid_view.dart';
import 'package:pure_live/domains/live/presentation/favorite/favorite_controller.dart';
import 'package:pure_live/domains/live/data/platforms/sites.dart';
import 'package:pure_live/domains/live/data/favorite_room_controller.dart';
import 'package:pure_live/domains/live/presentation/widgets/platform_tab.dart';

class FavoritePage extends GetView<FavoriteController> {
  const FavoritePage({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraint) {
        return Obx(() {
          final availableSitesList = controller.availableFavoriteSites;
          final siteKey = ValueKey(availableSitesList.map((e) => e.id).join('|'));

          return Scaffold(
            appBar: HomeAppBar(
              title: Row(
                children: [
                  Expanded(
                    child: ScrollableTabBar(
                      key: const ValueKey('favorite-status-tabs'),
                      controller: controller.tabController,
                      isScrollable: false,
                      tabAlignment: TabAlignment.center,
                      physics: const PureLiveBoundedScrollPhysics(),
                      tabs: [
                        Tab(text: i18n("online_room_title")),
                        Tab(text: i18n("recording_room_title")),
                        Tab(text: i18n("offline_room_title")),
                      ],
                    ),
                  ),
                  const FavoriteSortButton(key: ValueKey('favorite-sort')),
                ],
              ),
            ),
            body: _FavoriteSiteTabs(key: siteKey, controller: controller, availableSitesList: availableSitesList),
          );
        });
      },
    );
  }
}

@visibleForTesting
int resolveFavoriteSiteIndex({required List<String> siteIds, required String selectedSiteId, required int fallback}) {
  if (siteIds.isEmpty) return 0;
  final selectedIndex = siteIds.indexOf(selectedSiteId);
  return selectedIndex >= 0 ? selectedIndex : fallback.clamp(0, siteIds.length - 1).toInt();
}

/// Owns one stable site [TabController] across reactive data publications.
///
/// It also preserves the selected site by id when the configured platform
/// order changes, instead of resetting the visual controller to index zero
/// while the data controller still points at an older numeric index.
class _FavoriteSiteTabs extends StatefulWidget {
  const _FavoriteSiteTabs({super.key, required this.controller, required this.availableSitesList});

  final FavoriteController controller;
  final List<Site> availableSitesList;

  @override
  State<_FavoriteSiteTabs> createState() => _FavoriteSiteTabsState();
}

class _FavoriteSiteTabsState extends State<_FavoriteSiteTabs> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Map<String, ScrollController> _siteScrollControllers = {};

  ScrollController _scrollControllerFor(String siteId) =>
      _siteScrollControllers.putIfAbsent(siteId, () => createPureLiveScrollController());

  @override
  void initState() {
    super.initState();
    final initialIndex = resolveFavoriteSiteIndex(
      siteIds: widget.availableSitesList.map((site) => site.id).toList(growable: false),
      selectedSiteId: widget.controller.selectedPlatformId,
      fallback: widget.controller.tabSiteIndex.value,
    );
    _tabController = TabController(
      length: widget.availableSitesList.length,
      initialIndex: initialIndex,
      vsync: this,
      animationDuration: pureLiveTabTransitionDuration,
    )..addListener(_handleTabChanged);
    widget.controller.bindActiveScrollController(_scrollControllerFor(widget.availableSitesList[initialIndex].id));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.selectSiteIndex(initialIndex);
    });
  }

  void _handleTabChanged() {
    final tabController = _tabController;
    if (tabController.indexIsChanging) return;
    final animationValue = tabController.animation?.value ?? tabController.index.toDouble();
    if ((animationValue - tabController.index).abs() > 0.001) return;
    final controller = widget.controller;
    if (tabController.index < 0 || tabController.index >= widget.availableSitesList.length) return;
    controller.bindActiveScrollController(_scrollControllerFor(widget.availableSitesList[tabController.index].id));
    controller.selectSiteIndex(tabController.index);
  }

  /// A horizontal fling steps through the status tabs: left to the next,
  /// right to the previous.
  void _swipeStatus(double velocity) {
    const threshold = 300.0;
    final status = widget.controller.tabController;
    if (status.indexIsChanging || velocity.abs() < threshold) return;
    final next = (status.index + (velocity < 0 ? 1 : -1)).clamp(0, status.length - 1);
    if (next != status.index) status.animateTo(next);
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    widget.controller.bindActiveScrollController(null);
    for (final controller in _siteScrollControllers.values) {
      controller.dispose();
    }
    _siteScrollControllers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final availableSitesList = widget.availableSitesList;
    return Column(
      children: [
        Obx(() {
          final showTabs = SettingsService.to.roomCard.showFavoritePlatformTabs.v;
          final allIndex = availableSitesList.indexWhere((site) => site.id == Sites.allSite);
          // Without the tab bar the page lists every platform: move to 全部.
          if (!showTabs && allIndex >= 0 && _tabController.index != allIndex) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _tabController.index != allIndex) _tabController.index = allIndex;
            });
          }
          final refresh = AppLayout.of(context).pagedLists;
          if (!showTabs && !refresh) return const SizedBox.shrink();
          return Row(
            children: [
              if (showTabs)
                Expanded(
                  child: ScrollableTabBar(
                    key: const ValueKey('favorite-platform-tabs'),
                    controller: _tabController,
                    isScrollable: true,
                    physics: const PureLiveBoundedScrollPhysics(),
                    tabs: availableSitesList.map((e) => PlatformTab(site: e)).toList(),
                  ),
                )
              else
                const Spacer(),
              // Desktop has no pull-to-refresh; the refresh that lived in the
              // page bar sits at the end of the tab bar.
              if (AppLayout.of(context).pagedLists)
                Obx(
                  () => IconButton(
                    key: const ValueKey('favorite-refresh'),
                    tooltip: i18n('refresh'),
                    onPressed: controller.loadding.value ? null : () => controller.refreshData(),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ),
            ],
          );
        }),
        Expanded(
          child: BasePageView<FavoriteController, LiveRoom>(
            controller: controller,
            enableRefresh: true,
            enableLoadMore: true,
            wrapMobileRefresh: false,
            preserveContentWhenEmpty: true,
            contentBuilder: (context, list, _) {
              final activeSiteIndex = controller.tabSiteIndex.value;
              final platformTabsShown = SettingsService.to.roomCard.showFavoritePlatformTabs.v;
              final pages = TabBarView(
                controller: _tabController,
                // With the platform tabs hidden a swipe changes the status
                // tab (已开播 / 录播 / 未开播) instead; see below.
                physics: platformTabsShown
                    ? const PureLiveBoundedScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                children: availableSitesList.asMap().entries.map((entry) {
                  final site = entry.value;
                  return Builder(
                    key: ValueKey('favorite_site_${site.id}'),
                    builder: (context) {
                      // PageView mounts only the active/nearby pages. Defer
                      // platform filtering and ScrollController allocation to
                      // that point rather than doing both for every platform
                      // on each reactive rebuild.
                      final isCurrentSite = entry.key == activeSiteIndex;
                      final pageList = isCurrentSite ? list : controller.filteredSyncedRoomsForSite(site.id);
                      return RoomGridView(
                        siteId: site.id,
                        scrollController: _scrollControllerFor(site.id),
                        displayList: pageList,
                        emptyBuilder: (context) => _FavoriteEmptyState(controller: controller, siteId: site.id),
                      );
                    },
                  );
                }).toList(),
              );
              if (platformTabsShown) return pages;
              return GestureDetector(
                key: const ValueKey('favorite-status-swipe'),
                behavior: HitTestBehavior.translucent,
                onHorizontalDragEnd: (details) => _swipeStatus(details.primaryVelocity ?? 0),
                child: pages,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FavoriteEmptyState extends StatelessWidget {
  const _FavoriteEmptyState({required this.controller, required this.siteId});

  final FavoriteController controller;
  final String siteId;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final statusIndex = controller.tabOnlineIndex.value;
      final totalForSite = controller.favoriteCountForSite(siteId);
      final globalTotal = FavoriteRoomController.to.favoriteRooms.v.length;
      final offlineForSite = controller.favoriteCountForSite(siteId, statusIndex: 2);

      if (globalTotal == 0) {
        return AppStatusView(
          type: AppStatusType.empty,
          icon: Remix.heart_3_fill,
          title: i18n('empty_favorite_online_title'),
          subtitle: i18n('empty_favorite_online_subtitle'),
          buttonText: i18n('retry'),
          onButtonPressed: controller.refreshData,
        );
      }

      final title = switch (statusIndex) {
        1 => i18n('favorite_empty_recording_title'),
        2 => i18n('favorite_empty_offline_title'),
        _ => i18n('favorite_empty_online_title'),
      };
      final subtitleKey = totalForSite == 0 ? 'favorite_empty_platform_subtitle' : 'favorite_empty_filter_subtitle';
      final subtitle = i18n(subtitleKey).replaceAll('{count}', totalForSite.toString());
      final canShowOffline = statusIndex != 2 && offlineForSite > 0;

      return AppStatusView(
        type: AppStatusType.empty,
        icon: Remix.heart_3_fill,
        title: title,
        subtitle: subtitle,
        buttonText: canShowOffline ? i18n('favorite_show_offline') : i18n('retry'),
        onButtonPressed: canShowOffline ? () => controller.animateToStatusIndex(2) : controller.refreshData,
      );
    });
  }
}
