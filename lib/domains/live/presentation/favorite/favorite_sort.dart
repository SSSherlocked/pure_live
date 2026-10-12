import 'package:pinyindart/pinyindart.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/config/room_card_settings_controller.dart';

/// Orders followed [rooms] by the 排序 setting; ties fall back to the
/// streamer name (by pinyin). [platformOrder] ranks platforms for
/// [FavoriteSortMode.platform]; unknown platforms go last. Shared by the home
/// 关注 page and the room's 关注 panel.
void sortFavoriteRooms(List<LiveRoom> rooms, {required List<String> platformOrder}) {
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
      int rank(LiveRoom room) {
        final index = platformOrder.indexOf(room.normalizedPlatformId);
        return index < 0 ? platformOrder.length : index;
      }
      rooms.sort((left, right) {
        final platform = rank(left).compareTo(rank(right));
        return platform != 0 ? platform : byName(left, right);
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

/// The 排序 button: a small, quiet icon opening the three orders, the current
/// one bold in the primary colour.
class FavoriteSortButton extends StatelessWidget {
  const FavoriteSortButton({super.key, this.iconSize = 20});

  final double iconSize;

  static String labelOf(FavoriteSortMode mode) => switch (mode) {
    FavoriteSortMode.name => i18n('favorite_sort_name'),
    FavoriteSortMode.platform => i18n('favorite_sort_platform'),
    FavoriteSortMode.audience => i18n('favorite_sort_audience'),
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final settings = SettingsService.to.roomCard;
    return Obx(() {
      final current = settings.favoriteSortMode;
      return PopupMenuButton<FavoriteSortMode>(
        tooltip: i18n('favorite_sort'),
        icon: Icon(Icons.filter_list_rounded, size: iconSize, color: colors.onSurfaceVariant),
        onSelected: (mode) => settings.favoriteSortModeName.v = mode.name,
        itemBuilder: (context) => [
          for (final mode in FavoriteSortMode.values)
            PopupMenuItem<FavoriteSortMode>(
              value: mode,
              child: Text(
                labelOf(mode),
                style: AppText.of(context).body.copyWith(
                  color: mode == current ? colors.primary : null,
                  fontWeight: mode == current ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
        ],
      );
    });
  }
}
