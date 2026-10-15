import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/config/room_card_settings_controller.dart';
import 'package:pure_live/domains/live/presentation/widgets/room_card.dart';
import 'package:pure_live/domains/live/presentation/widgets/room_grid_sizing.dart';

/// A menu page's rooms (搜索, an area's rooms, 热门): in the layout chosen for
/// the page in 房间卡片设置 (紧凑信息 or 封面卡片, each with its own gaps),
/// with the 房间卡片设置 columns or card width, rows as tall as their cards.
///
/// A sliver, for a [CustomScrollView].
class RoomCardRows extends StatelessWidget {
  const RoomCardRows({
    super.key,
    required this.page,
    required this.width,
    required this.rooms,
    this.bottomPadding = 6,
  });

  final RoomListPage page;

  /// The width the rows are laid out in (the scroll view's).
  final double width;

  final List<LiveRoom> rooms;

  /// Space under the last row (clear of a floating button, say).
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final layout = SettingsService.to.roomCard.layoutFor(page);
      final compact = layout == RoomCardLayout.compact;
      final spacing = SettingsService.to.theme.cardCrossSpacing(compact: compact);
      final rowSpacing = SettingsService.to.theme.cardMainSpacing(compact: compact);
      final sizing = resolveRoomGridSizing(
        width: width,
        autoColumns: roomGridAutoColumns(width, dense: true),
        spacing: spacing,
        basePadding: 6,
        fixedCardWidth: SettingsService.to.roomCard.currentCardWidth,
        columns: SettingsService.to.roomCard.currentColumns,
      );
      final columns = sizing.columns;
      final rows = (rooms.length + columns - 1) ~/ columns;
      return SliverPadding(
        padding: EdgeInsets.fromLTRB(sizing.horizontalPadding, 6, sizing.horizontalPadding, bottomPadding),
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
                                  dense: true,
                                  layout: layout,
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
