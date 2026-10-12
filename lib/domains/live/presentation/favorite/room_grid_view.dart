import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:pure_live/core/index.dart';
import 'package:pure_live/domains/live/presentation/widgets/room_grid_sizing.dart';
import 'package:pure_live/domains/live/presentation/favorite/favorite_controller.dart';
import 'package:pure_live/domains/live/presentation/widgets/room_card.dart';
import 'package:pure_live/domains/live/presentation/widgets/room_card_layout.dart';

/// Pull-to-refresh belongs to every layout except paged lists (wide + pointer):
/// a touch tablet keeps it, a desktop window keeps its page bar.
@visibleForTesting
bool shouldWrapFavoritePullToRefresh(AppLayout layout) => !layout.pagedLists;

class RoomGridView extends GetView<FavoriteController> {
  const RoomGridView({
    super.key,
    required this.siteId,
    required this.scrollController,
    required this.displayList,
    this.emptyBuilder,
  });

  final String siteId;
  final ScrollController scrollController;
  final List<LiveRoom> displayList;
  final WidgetBuilder? emptyBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraint) {
        final width = constraint.maxWidth;
        return Obx(() {
          final dense = SettingsService.to.app.enableDenseFavorites.v;
          final spacing = SettingsService.to.theme.crossAxisSpacing.v;
          final mainAxisSpacing = SettingsService.to.theme.mainAxisSpacing.v;
          final roomCardAppearance = SettingsService.to.roomCard.resolve();
          final isVerifyingFavorites = controller.isVerifyingFavorites.value;
          final crossAxisCount = roomGridAutoColumns(width, dense: dense);
          final sizing = resolveRoomGridSizing(
            width: width,
            autoColumns: crossAxisCount,
            spacing: spacing,
            basePadding: 12,
            fixedCardWidth: SettingsService.to.roomCard.currentCardWidth,
            columns: SettingsService.to.roomCard.currentColumns,
          );

          Widget buildScrollable(ScrollPhysics physics) {
            if (displayList.isEmpty) {
              return CustomScrollView(
                controller: scrollController,
                physics: physics,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child:
                        emptyBuilder?.call(context) ??
                        AppStatusView(
                          type: AppStatusType.empty,
                          icon: Icons.favorite_rounded,
                          title: i18n('empty_favorite_online_title'),
                          subtitle: i18n('empty_favorite_online_subtitle'),
                        ),
                  ),
                ],
              );
            }

            final itemWidth = sizing.itemWidth;
            return GridView.builder(
              padding: EdgeInsets.symmetric(horizontal: sizing.horizontalPadding, vertical: 12),
              controller: scrollController,
              physics: physics,
              scrollCacheExtent: ScrollCacheExtent.pixels(width > 680 ? 480 : 320),
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: sizing.columns,
                crossAxisSpacing: spacing,
                mainAxisSpacing: mainAxisSpacing,
                mainAxisExtent: RoomCardLayoutMetrics.gridMainAxisExtent(
                  itemWidth: itemWidth,
                  appearance: roomCardAppearance,
                  dense: dense,
                  textScaler: MediaQuery.textScalerOf(context),
                ),
              ),
              itemCount: displayList.length,
              itemBuilder: (context, index) {
                final room = displayList[index];
                return RoomCard(
                  key: ValueKey('${room.platform}:${room.roomId}'),
                  room: room,
                  dense: dense,
                  statusPending: isVerifyingFavorites || room.isLiveStatusPending,
                  statusPendingLabel: isVerifyingFavorites
                      ? i18n('favorite_status_verifying')
                      : i18n('favorite_status_unknown'),
                );
              },
            );
          }

          if (!shouldWrapFavoritePullToRefresh(AppLayout.of(context))) {
            return buildScrollable(const PureLiveScrollPhysics(parent: AlwaysScrollableScrollPhysics()));
          }

          // EasyRefresh must own the exact physics installed on the vertical
          // child. Supplying PureLiveScrollPhysics directly made Android's
          // outer ClampingScrollPhysics consume boundary movement before the
          // refresh header could observe it, so the callback existed while the
          // pull animation never armed.
          return buildFavoritePullToRefresh(
            siteId: siteId,
            onRefresh: controller.refreshData,
            childBuilder: (_, physics) => buildScrollable(physics),
          );
        });
      },
    );
  }
}

@visibleForTesting
Widget buildFavoritePullToRefresh({
  required String siteId,
  required Future<void> Function() onRefresh,
  required ERChildBuilder childBuilder,
}) {
  return EasyRefresh.builder(
    key: ValueKey('favorite_pull_to_refresh_$siteId'),
    header: MaterialHeader(
      key: ValueKey('favorite_pull_to_refresh_indicator_$siteId'),
      triggerOffset: 72,
      triggerWhenRelease: true,
      clamping: true,
    ),
    triggerAxis: Axis.vertical,
    onRefresh: onRefresh,
    childBuilder: childBuilder,
  );
}
