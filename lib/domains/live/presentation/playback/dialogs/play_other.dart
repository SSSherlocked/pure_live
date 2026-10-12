import 'dart:async';

import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/utils/event_bus.dart';
import 'package:pure_live/core/widgets/common_avatar.dart';
import 'package:pure_live/core/player/presentation/player_side_panel.dart';
import 'package:pure_live/domains/live/data/favorite_room_controller.dart';
import 'package:pure_live/domains/live/presentation/playback/controllers/live_play_controller.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/content_first_panel_layout.dart';

/// Fullscreen "关注" panel: the same followed-room switcher as the room
/// panel's 关注 tab, in the fullscreen [PlayerSidePanel].
class PlayOther extends StatelessWidget {
  const PlayOther({required this.controller, super.key});

  final LivePlayController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerHeight = resolveRoomHistoryTextMetrics(
      textScaler: MediaQuery.textScalerOf(context),
      headerFontSize: theme.textTheme.titleSmall?.fontSize ?? 14,
      headerLineHeight: theme.textTheme.titleSmall?.height ?? 1.25,
      tabFontSize: theme.textTheme.labelLarge?.fontSize ?? 14,
      tabLineHeight: theme.textTheme.labelLarge?.height ?? 1.43,
      titleFontSize: theme.textTheme.titleMedium?.fontSize ?? 15,
      titleLineHeight: theme.textTheme.titleMedium?.height ?? 1.5,
      detailFontSize: theme.textTheme.bodySmall?.fontSize ?? 12,
      detailLineHeight: theme.textTheme.bodySmall?.height ?? 1.33,
    ).headerHeight;

    return PlayerSidePanel(
      key: const ValueKey('fullscreen-room-history-dialog'),
      icon: Icons.favorite_rounded,
      title: i18n('follow'),
      headerHeight: headerHeight,
      closeKey: const ValueKey('room-history-close'),
      child: FollowRoomSwitcher(controller: controller, onSwitch: () => Navigator.of(context).pop()),
    );
  }
}

/// Followed rooms split into 已开播 / 录播, one tap away from
/// replacing the room being watched. Used by the room panel's 关注 tab and
/// by the fullscreen [PlayOther] panel.
class FollowRoomSwitcher extends StatefulWidget {
  const FollowRoomSwitcher({required this.controller, this.onSwitch, super.key});

  final LivePlayController controller;

  /// Runs before switching, e.g. to close the hosting dialog.
  final VoidCallback? onSwitch;

  @override
  State<FollowRoomSwitcher> createState() => _FollowRoomSwitcherState();
}

class _FollowRoomSwitcherState extends State<FollowRoomSwitcher> with SingleTickerProviderStateMixin {
  late final TabController tabController;

  final onlineRooms = <LiveRoom>[].obs;
  final recordingRooms = <LiveRoom>[].obs;
  final loadingFinish = false.obs;
  final refreshing = false.obs;

  StreamSubscription<dynamic>? subscription;
  Worker? _favoritesWorker;

  @override
  void initState() {
    super.initState();

    tabController = TabController(length: 2, vsync: this, animationDuration: pureLiveTabTransitionDuration);

    _updateRooms();

    subscription = EventBus.instance.listen('refresh_favorite_finish', (_) => _updateRooms());
    // The 关注 tab stays mounted for the whole room session, so follow list
    // edits must show up without reopening it.
    _favoritesWorker = ever(FavoriteRoomController.to.favoriteRooms, (_) => _updateRooms());
  }

  void _updateRooms() {
    if (!mounted) return;
    final allRooms = FavoriteRoomController.to.favoriteRooms.v;

    final liveList = allRooms.where((room) => room.isLiveNow && room.isRecord == false).toList()
      ..sort(_compareAudience);
    final recordList = allRooms.where((room) => room.effectiveLiveStatus == LiveStatus.replay).toList()
      ..sort(_compareAudience);
    onlineRooms.assignAll(liveList);
    recordingRooms.assignAll(recordList);

    loadingFinish.value = true;
    refreshing.value = false;
  }

  int _compareAudience(LiveRoom left, LiveRoom right) {
    final app = SettingsService.to.app;
    return LiveRoom.compareAudienceRanking(
      left,
      right,
      preferRealOnline: app.preferRealOnlineCounts.v,
      platformEnabled: app.isRealOnlineEnabledFor,
    );
  }

  @override
  void dispose() {
    tabController.dispose();
    subscription?.cancel();
    _favoritesWorker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final textTheme = theme.textTheme;
    final textMetrics = resolveRoomHistoryTextMetrics(
      textScaler: MediaQuery.textScalerOf(context),
      headerFontSize: textTheme.titleSmall?.fontSize ?? 14,
      headerLineHeight: textTheme.titleSmall?.height ?? 1.25,
      tabFontSize: textTheme.labelLarge?.fontSize ?? 14,
      tabLineHeight: textTheme.labelLarge?.height ?? 1.43,
      titleFontSize: textTheme.titleMedium?.fontSize ?? 15,
      titleLineHeight: textTheme.titleMedium?.height ?? 1.5,
      detailFontSize: textTheme.bodySmall?.fontSize ?? 12,
      detailLineHeight: textTheme.bodySmall?.height ?? 1.33,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 6),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: textMetrics.tabBarHeight,
                  child: ScrollableTabBar(
                    controller: tabController,
                    isScrollable: textMetrics.scrollTabs,
                    tabAlignment: textMetrics.scrollTabs ? TabAlignment.start : TabAlignment.fill,
                    physics: const PureLiveBoundedScrollPhysics(),
                    labelColor: colors.primary,
                    unselectedLabelColor: colors.onSurfaceVariant,
                    indicatorSize: TabBarIndicatorSize.label,
                    dividerHeight: 0,
                    splashBorderRadius: BorderRadius.circular(8),
                    labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                    tabs: [
                      _CompactTab(
                        icon: Icons.sensors_rounded,
                        label: i18n('online_room_title'),
                        height: textMetrics.tabBarHeight,
                        shrinkToFit: !textMetrics.scrollTabs,
                      ),
                      _CompactTab(
                        icon: Icons.fiber_smart_record_rounded,
                        label: i18n('recording_room_title'),
                        height: textMetrics.tabBarHeight,
                        shrinkToFit: !textMetrics.scrollTabs,
                      ),
                    ],
                  ),
                ),
              ),
              Obx(
                () => IconButton(
                  key: const ValueKey('room-history-refresh'),
                  tooltip: i18n('refresh'),
                  visualDensity: VisualDensity.compact,
                  onPressed: refreshing.value
                      ? null
                      : () {
                          refreshing.value = true;
                          EventBus.instance.emit('refresh_favorite_rooms', true);
                        },
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              Obx(
                () => loadingFinish.value
                    ? TabBarView(
                        controller: tabController,
                        physics: const PureLiveBoundedScrollPhysics(),
                        children: [
                          _buildRoomGrid(onlineRooms, history: false, textMetrics: textMetrics),
                          _buildRoomGrid(recordingRooms, history: false, textMetrics: textMetrics),
                        ],
                      )
                    : AppStatusView(type: AppStatusType.loading, title: '', subtitle: ''),
              ),
              Obx(
                () => refreshing.value
                    ? const Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        child: LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.transparent),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRoomGrid(List<LiveRoom> rooms, {required bool history, required RoomHistoryTextMetrics textMetrics}) {
    if (rooms.isEmpty) {
      return AppStatusView(type: AppStatusType.empty);
    }

    // One column of avatar rows at every width: no covers, the same list in
    // the side panel and in the fullscreen panel.
    const padding = 10.0;
    const spacing = 8.0;
    final rowExtent = textMetrics.mobileRowHeight;
    return Builder(
      builder: (context) {
        return Obx(() {
          final current = widget.controller.state.value.room.detail;
          return GridView.builder(
            key: ValueKey(history ? 'watch-history-grid' : 'live-room-grid'),
            padding: const EdgeInsets.fromLTRB(padding, 2, padding, padding),
            physics: const PureLiveScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 1,
              mainAxisExtent: rowExtent,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
            ),
            itemCount: rooms.length,
            itemBuilder: (context, index) {
              final room = rooms[index];
              final playing = current != null && room.hasSameIdentity(current);

              return _RoomSwitchCard(
                room: room,
                history: history,
                playing: playing,
                onTap: playing
                    ? null
                    : () {
                        widget.onSwitch?.call();
                        widget.controller.switchRoom(room);
                      },
              );
            },
          );
        });
      },
    );
  }
}

class _CompactTab extends StatelessWidget {
  const _CompactTab({required this.icon, required this.label, required this.height, required this.shrinkToFit});

  final IconData icon;
  final String label;
  final double height;
  final bool shrinkToFit;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14),
        const SizedBox(width: 3),
        // Flexible causes a layout error here because TabBar may provide unbounded width constraints.
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelLarge),
      ],
    );
    return Tab(
      height: height,
      child: shrinkToFit ? FittedBox(fit: BoxFit.scaleDown, child: content) : content,
    );
  }
}

class _RoomSwitchCard extends StatelessWidget {
  const _RoomSwitchCard({
    required this.room,
    required this.history,
    required this.onTap,
    this.playing = false,
  });

  final LiveRoom room;
  final bool history;

  /// The room currently on screen: highlighted and not tappable.
  final bool playing;

  final VoidCallback? onTap;

  String _historyLabel() {
    final value = room.lastWatchedAt;

    if (value == null || value <= 0) {
      return i18n('history_earlier');
    }

    return i18n('watched_at', args: {'time': formatHistoryWatchedAt(value)});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final audience = room.audienceValue(
      preferRealOnline: SettingsService.to.app.preferRealOnlineCounts.v,
      platformEnabled: SettingsService.to.app.isRealOnlineEnabledFor(room.platform),
    );

    final title = room.title?.trim().isNotEmpty == true ? room.title! : i18n('untitled_room');

    final nick = room.nick?.trim() ?? '';

    final meta = playing
        ? i18n('now_watching')
        : history
        ? _historyLabel()
        : audience.isEmpty
        ? i18n('audience_unknown')
        : readableCount(audience);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: playing ? colors.primaryContainer.withValues(alpha: .45) : colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: playing ? colors.primary : colors.outlineVariant.withValues(alpha: .55),
              width: playing ? 1.5 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _buildAvatarLayout(context, meta: meta, title: title, nick: nick),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarLayout(BuildContext context, {required String meta, required String title, required String nick}) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final platform = room.platform?.trim().toLowerCase() ?? '';
    final displayNick = nick.isEmpty ? i18n('unknown') : nick;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          CommonAvatar(avatarUrl: room.avatar, fallbackName: nick, dense: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  displayNick,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // The same title/subtitle pair as the danmaku settings panel's rows.
                  style: AppText.from(theme).sectionTitle,
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.from(theme).secondary.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (platform.isNotEmpty) ...[_PlatformTag(platform: platform), const SizedBox(height: 3)],
              Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.from(theme).secondary.copyWith(
                  color: playing
                      ? colors.primary
                      : history
                      ? colors.onSurfaceVariant
                      : Colors.orange.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlatformTag extends StatelessWidget {
  const _PlatformTag({required this.platform});

  final String platform;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: .75),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.outline.withValues(alpha: .2), width: .5),
      ),
      child: Text(
        i18n('site_$platform'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppText.of(context).tag.copyWith(color: colors.onSurfaceVariant, fontWeight: FontWeight.w600),
      ),
    );
  }
}

String formatHistoryWatchedAt(int millisecondsSinceEpoch) {
  final watched = DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch);
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${watched.year.toString().padLeft(4, '0')}-'
      '${twoDigits(watched.month)}-${twoDigits(watched.day)} '
      '${twoDigits(watched.hour)}:${twoDigits(watched.minute)}';
}
