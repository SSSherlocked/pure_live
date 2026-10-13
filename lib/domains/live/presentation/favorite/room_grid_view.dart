import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/widgets/refresh_indicators.dart';
import 'package:pure_live/domains/live/presentation/widgets/room_grid_sizing.dart';
import 'package:pure_live/domains/live/presentation/favorite/favorite_controller.dart';
import 'package:pure_live/domains/live/presentation/widgets/room_card.dart';

/// Pull-to-refresh belongs to every layout except the desktop one (wide + pointer):
/// a touch tablet keeps it, while the desktop layout reloads from the page's
/// floating refresh button.
@visibleForTesting
bool shouldWrapFavoritePullToRefresh(AppLayout layout) => !layout.refreshByButton;

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
          final compact = SettingsService.to.roomCard.isCompactLayout;
          final spacing = SettingsService.to.theme.cardCrossSpacing(compact: compact);
          final mainAxisSpacing = SettingsService.to.theme.cardMainSpacing(compact: compact);
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

            // Rows as tall as their cards, like 热门: a fixed grid extent that
            // disagreed with the card (a stale layout, a resolved appearance
            // other than the one drawn) left each card centred in a taller
            // cell, with a band of empty space under every row.
            final columns = sizing.columns;
            final rows = (displayList.length + columns - 1) ~/ columns;
            Widget card(LiveRoom room) => RoomCard(
              key: ValueKey('${room.platform}:${room.roomId}'),
              room: room,
              dense: dense,
              statusPending: isVerifyingFavorites || room.isLiveStatusPending,
              statusPendingLabel: isVerifyingFavorites
                  ? i18n('favorite_status_verifying')
                  : i18n('favorite_status_unknown'),
            );
            return CustomScrollView(
              controller: scrollController,
              physics: physics,
              scrollCacheExtent: ScrollCacheExtent.pixels(width > 680 ? 480 : 320),
              semanticChildCount: displayList.length,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: sizing.horizontalPadding, vertical: 12),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, row) => Padding(
                        padding: EdgeInsets.only(bottom: row + 1 < rows ? mainAxisSpacing : 0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var column = 0; column < columns; column++) ...[
                              if (column > 0) SizedBox(width: spacing),
                              Expanded(
                                child: row * columns + column < displayList.length
                                    ? RepaintBoundary(
                                        child: IndexedSemantics(
                                          index: row * columns + column,
                                          child: card(displayList[row * columns + column]),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ],
                        ),
                      ),
                      childCount: rows,
                      addAutomaticKeepAlives: false,
                      addRepaintBoundaries: false,
                      addSemanticIndexes: false,
                    ),
                  ),
                ),
              ],
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
            // A floating ball over the list rather than pulling the list down.
            header: floatingRefreshHeader(),
            onRefresh: controller.pullToRefresh,
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
  required Header header,
  required Future<void> Function() onRefresh,
  required ERChildBuilder childBuilder,
}) {
  return EasyRefresh.builder(
    key: ValueKey('favorite_pull_to_refresh_$siteId'),
    header: header,
    triggerAxis: Axis.vertical,
    onRefresh: onRefresh,
    childBuilder: childBuilder,
  );
}
