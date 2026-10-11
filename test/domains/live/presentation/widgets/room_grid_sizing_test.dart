import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/domains/live/presentation/widgets/room_grid_sizing.dart';

void main() {
  group('resolveRoomGridSizing', () {
    test('automatic width keeps the given columns and stretches them', () {
      final sizing = resolveRoomGridSizing(
        width: 1000,
        autoColumns: 3,
        spacing: 10,
        basePadding: 12,
        fixedCardWidth: 0,
      );
      expect(sizing.columns, 3);
      expect(sizing.horizontalPadding, 12);
      expect(sizing.itemWidth, closeTo((1000 - 24 - 20) / 3, 1e-9));
    });

    test('fixed width keeps the card size and centres the grid', () {
      final sizing = resolveRoomGridSizing(
        width: 1000,
        autoColumns: 3,
        spacing: 10,
        basePadding: 12,
        fixedCardWidth: 300,
      );
      expect(sizing.columns, 3);
      expect(sizing.itemWidth, 300);
      // 3 * 300 + 2 * 10 = 920 used, 80 left: 40 on each side.
      expect(sizing.horizontalPadding, 40);
    });

    test('a wider window only adds columns', () {
      final narrow = resolveRoomGridSizing(
        width: 700,
        autoColumns: 2,
        spacing: 10,
        basePadding: 12,
        fixedCardWidth: 300,
      );
      final wide = resolveRoomGridSizing(
        width: 1400,
        autoColumns: 4,
        spacing: 10,
        basePadding: 12,
        fixedCardWidth: 300,
      );
      expect(narrow.itemWidth, 300);
      expect(wide.itemWidth, 300);
      expect(narrow.columns, 2);
      expect(wide.columns, 4);
    });

    test('shrinks a card only when a single column does not fit', () {
      final sizing = resolveRoomGridSizing(
        width: 200,
        autoColumns: 1,
        spacing: 10,
        basePadding: 12,
        fixedCardWidth: 300,
      );
      expect(sizing.columns, 1);
      expect(sizing.itemWidth, 176);
      expect(sizing.horizontalPadding, 12);
    });
  });
}
