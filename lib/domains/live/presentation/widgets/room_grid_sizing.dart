/// Column count, card width and side padding for a grid of room cards.
class RoomGridSizing {
  const RoomGridSizing({required this.columns, required this.itemWidth, required this.horizontalPadding});

  final int columns;
  final double itemWidth;

  /// Padding on each side; with a fixed card width it also centres the grid.
  final double horizontalPadding;
}

/// Automatic column count of the followed-rooms and history grids.
int roomGridAutoColumns(double width, {required bool dense}) {
  if (dense) return width > 1280 ? 5 : (width > 960 ? 4 : (width > 640 ? 3 : 2));
  return width > 1280 ? 4 : (width > 960 ? 3 : (width > 640 ? 2 : 1));
}

/// Resolves the grid for [width].
///
/// [fixedCardWidth] of 0 lays out [columns] columns (or [autoColumns] when
/// [columns] is 0) that stretch to fill the width. A positive width keeps every card that
/// wide (shrinking only when even one column does not fit), places as many
/// columns as fit and centres the grid in the leftover space.
RoomGridSizing resolveRoomGridSizing({
  required double width,
  required int autoColumns,
  required double spacing,
  required double basePadding,
  required double fixedCardWidth,
  int columns = 0,
}) {
  final available = (width - basePadding * 2).clamp(0.0, double.infinity).toDouble();
  if (fixedCardWidth <= 0) {
    final count = columns > 0 ? columns : autoColumns;
    final columnCount = count < 1 ? 1 : count;
    final itemWidth = (available - spacing * (columnCount - 1)) / columnCount;
    return RoomGridSizing(
      columns: columnCount,
      itemWidth: itemWidth < 0 ? 0 : itemWidth,
      horizontalPadding: basePadding,
    );
  }
  var fitColumns = ((available + spacing) / (fixedCardWidth + spacing)).floor();
  if (fitColumns < 1) fitColumns = 1;
  final fitted = (available - spacing * (fitColumns - 1)) / fitColumns;
  final itemWidth = fitted < fixedCardWidth ? (fitted < 0 ? 0.0 : fitted) : fixedCardWidth;
  final used = itemWidth * fitColumns + spacing * (fitColumns - 1);
  final side = (width - used) / 2;
  return RoomGridSizing(
    columns: fitColumns,
    itemWidth: itemWidth,
    horizontalPadding: side < basePadding ? basePadding : side,
  );
}
