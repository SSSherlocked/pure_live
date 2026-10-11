import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/widgets/common_avatar.dart';
import 'package:pure_live/domains/live/data/favorite_room_controller.dart';
import 'package:pure_live/domains/live/presentation/playback/controllers/live_play_controller.dart';

/// "关注" tab of the room panel: the followed rooms that are live right now,
/// one tap away from replacing the room being watched.
class FollowRoomsPage extends StatelessWidget {
  const FollowRoomsPage({super.key, required this.controller});

  final LivePlayController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final current = controller.state.value.room.detail;
      final app = SettingsService.to.app;
      final rooms =
          FavoriteRoomController.to.favoriteRooms.v.where((room) => room.isLiveNow && room.isRecord == false).toList()
            ..sort(
              (left, right) => LiveRoom.compareAudienceRanking(
                left,
                right,
                preferRealOnline: app.preferRealOnlineCounts.v,
                platformEnabled: app.isRealOnlineEnabledFor,
              ),
            );
      if (rooms.isEmpty) return AppStatusView(type: AppStatusType.empty);

      return ListView.builder(
        key: const ValueKey('live-follow-rooms-list'),
        physics: const PureLiveScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemCount: rooms.length,
        itemBuilder: (context, index) {
          final room = rooms[index];
          final selected = current != null && room.hasSameIdentity(current);
          return _FollowRoomTile(
            room: room,
            selected: selected,
            onTap: selected ? null : () => controller.switchRoom(room),
          );
        },
      );
    });
  }
}

class _FollowRoomTile extends StatelessWidget {
  const _FollowRoomTile({required this.room, required this.selected, required this.onTap});

  final LiveRoom room;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final nick = room.nick?.trim() ?? '';
    final title = room.title?.trim().isNotEmpty == true ? room.title!.trim() : i18n('untitled_room');
    return ListTile(
      dense: true,
      selected: selected,
      onTap: onTap,
      leading: CommonAvatar(avatarUrl: room.avatar, fallbackName: nick, dense: true),
      title: Text(nick.isEmpty ? i18n('unknown') : nick, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
      ),
      trailing: Text(i18n('site_${room.platform}'), style: theme.textTheme.labelSmall),
    );
  }
}
