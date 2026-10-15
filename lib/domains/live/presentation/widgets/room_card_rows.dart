import 'package:pure_live/core/index.dart';
import 'package:pure_live/domains/live/presentation/widgets/room_card.dart';
import 'package:pure_live/domains/live/presentation/widgets/room_grid_sizing.dart';

/// Rooms laid out as 主页关注 lays them out: its card density, the 房间卡片设置
/// columns or card width, its spacing, and rows as tall as their cards.
///
/// A sliver, for pages that list rooms in a [CustomScrollView] (search, an
/// area's rooms), so every list of rooms looks the same.
class RoomCardRows extends StatelessWidget {
  const RoomCardRows({super.key, required this.width, required this.rooms, this.bottomPadding = 12});

  /// The width the rows are laid out in (the scroll view's).
  final double width;

  final List<LiveRoom> rooms;

  /// Space under the last row (clear of a floating button, say).
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final dense = SettingsService.to.app.enableDenseFavorites.v;
      final compact = SettingsService.to.roomCard.isCompactLayout;
      final spacing = SettingsService.to.theme.cardCrossSpacing(compact: compact);
      final rowSpacing = SettingsService.to.theme.cardMainSpacing(compact: compact);
      final sizing = resolveRoomGridSizing(
        width: width,
        autoColumns: roomGridAutoColumns(width, dense: dense),
        spacing: spacing,
        basePadding: 12,
        fixedCardWidth: SettingsService.to.roomCard.currentCardWidth,
        columns: SettingsService.to.roomCard.currentColumns,
      );
      final columns = sizing.columns;
      final rows = (rooms.length + columns - 1) ~/ columns;
      return SliverPadding(
        padding: EdgeInsets.fromLTRB(sizing.horizontalPadding, 12, sizing.horizontalPadding, bottomPadding),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, row) => Padding(
              padding: EdgeInsets.only(bottom: row + 1 < rows ? rowSpacing : 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var column = 0; column < columns; column++) ...[
                    if (column > 0) SizedBox(width: spacing),
                    Expanded(
                      child: row * columns + column < rooms.length
                          ? RepaintBoundary(
                              child: IndexedSemantics(
                                index: row * columns + column,
                                child: RoomCard(
                                  key: ValueKey(
                                    '${rooms[row * columns + column].platform}:${rooms[row * columns + column].roomId}',
                                  ),
                                  room: rooms[row * columns + column],
                                  dense: dense,
                                ),
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
      );
    });
  }
}
