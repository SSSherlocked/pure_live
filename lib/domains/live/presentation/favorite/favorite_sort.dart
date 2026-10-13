import 'package:pinyindart/pinyindart.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/config/room_card_settings_controller.dart';
import 'package:pure_live/domains/live/data/favorite_room_controller.dart';

/// Orders followed [rooms] by the 排序 setting; ties fall back to the
/// streamer name (by pinyin). By platform, the order is 平台设置 › 平台显示
/// (its visible platforms, as arranged there); any other source, such as an
/// imported IPTV list, follows in alphabetical order. Shared by the home 关注
/// page and the room's 关注 panel.
void sortFavoriteRooms(List<LiveRoom> rooms) {
  if (rooms.length < 2) return;
  // Pinyin keys once per room, not once per comparison.
  final names = Map<LiveRoom, String>.identity();
  for (final room in rooms) {
    names[room] = getPinyin((room.nick ?? '').trim(), withTone: false, separator: '').toLowerCase();
  }
  int byName(LiveRoom left, LiveRoom right) => names[left]!.compareTo(names[right]!);
  switch (SettingsService.to.roomCard.favoriteSortMode) {
    case FavoriteSortMode.name:
      rooms.sort(byName);
    case FavoriteSortMode.platform:
      final platformOrder = [for (final id in FavoriteRoomController.to.hotAreasList) id.trim().toLowerCase()];
      int rank(LiveRoom room) {
        final index = platformOrder.indexOf(room.normalizedPlatformId);
        return index < 0 ? platformOrder.length : index;
      }
      rooms.sort((left, right) {
        final platform = rank(left).compareTo(rank(right));
        if (platform != 0) return platform;
        // Sources outside the configured order: alphabetical.
        final source = left.normalizedPlatformId.compareTo(right.normalizedPlatformId);
        return source != 0 ? source : byName(left, right);
      });
    case FavoriteSortMode.audience:
      final app = SettingsService.to.app;
      rooms.sort((left, right) {
        final audience = LiveRoom.compareAudienceRanking(
          left,
          right,
          preferRealOnline: app.preferRealOnlineCounts.v,
          platformEnabled: app.isRealOnlineEnabledFor,
        );
        return audience != 0 ? audience : byName(left, right);
      });
  }
}

String _labelOf(FavoriteSortMode mode) => switch (mode) {
  FavoriteSortMode.name => i18n('favorite_sort_name'),
  FavoriteSortMode.platform => i18n('favorite_sort_platform'),
  FavoriteSortMode.audience => i18n('favorite_sort_audience'),
};

/// The three orders (the shared choice entry), the current one highlighted.
List<PopupMenuEntry<FavoriteSortMode>> _sortItems(BuildContext context) {
  final current = SettingsService.to.roomCard.favoriteSortMode;
  final labels = [for (final mode in FavoriteSortMode.values) _labelOf(mode)];
  return [
    for (final mode in FavoriteSortMode.values)
      choiceMenuItem<FavoriteSortMode>(
        context,
        value: mode,
        label: _labelOf(mode),
        labels: labels,
        selected: mode == current,
      ),
  ];
}

void _applySortMode(FavoriteSortMode? mode) {
  if (mode != null) SettingsService.to.roomCard.favoriteSortModeName.v = mode.name;
}

/// The home 关注 page's 排序 entry in the top-right menu: a submenu of the
/// three orders.
HomePageMenuAction favoriteSortMenuAction() => HomePageMenuAction(
  icon: Icons.filter_list_rounded,
  label: i18n('favorite_sort'),
  choices: [for (final mode in FavoriteSortMode.values) _labelOf(mode)],
  selected: () => SettingsService.to.roomCard.favoriteSortMode.index,
  onSelected: (index) => _applySortMode(FavoriteSortMode.values[index]),
);

/// The 排序 button of the room's 关注 panel: a small, quiet icon opening the
/// three orders.
class FavoriteSortButton extends StatelessWidget {
  const FavoriteSortButton({super.key, this.iconSize = 18});

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    // The items are built when the menu opens, so they show the current order.
    return PopupMenuButton<FavoriteSortMode>(
      tooltip: i18n('favorite_sort'),
      icon: Icon(Icons.filter_list_rounded, size: iconSize, color: Theme.of(context).colorScheme.onSurfaceVariant),
      onSelected: _applySortMode,
      constraints: choiceMenuConstraints(context, [for (final mode in FavoriteSortMode.values) _labelOf(mode)]),
      itemBuilder: _sortItems,
    );
  }
}
