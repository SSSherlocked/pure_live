import 'dart:math' as math;
import 'dart:async';

import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/utils/event_bus.dart';
import 'package:pure_live/core/config/room_card_settings_controller.dart';
import 'package:pure_live/core/config/theme_settings_controller.dart';
import 'package:pure_live/core/player/presentation/player_side_panel.dart';
import 'package:pure_live/domains/live/data/favorite_room_controller.dart';
import 'package:pure_live/domains/live/presentation/favorite/favorite_sort.dart';
import 'package:pure_live/domains/live/presentation/playback/controllers/live_play_controller.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/content_first_panel_layout.dart';
import 'package:pure_live/domains/live/presentation/widgets/room_card.dart';
import 'package:pure_live/domains/live/presentation/widgets/room_card_layout.dart';

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
    // A tighter title row: the tabs sit right under it.
    final tightHeaderHeight = math.max(40.0, headerHeight - 8);

    return PlayerSidePanel(
      key: const ValueKey('fullscreen-room-history-dialog'),
      icon: Icons.favorite_rounded,
      title: i18n('follow'),
      headerHeight: tightHeaderHeight,
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
  Worker? _sortWorker;
  Worker? _autoRefreshWorker;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();

    tabController = TabController(length: 2, vsync: this, animationDuration: pureLiveTabTransitionDuration);

    _updateRooms();

    subscription = EventBus.instance.listen('refresh_favorite_finish', (_) => _updateRooms());
    // The 关注 tab stays mounted for the whole room session, so follow list
    // edits must show up without reopening it.
    _favoritesWorker = ever(FavoriteRoomController.to.favoriteRooms, (_) => _updateRooms());
    _sortWorker = everAll([
      SettingsService.to.roomCard.favoriteSortModeName,
      FavoriteRoomController.to.hotAreasList,
    ], (_) => _updateRooms());
    _scheduleAutoRefresh();
    _autoRefreshWorker = ever(SettingsService.to.theme.livePanelFollowRefreshMinutes, (_) => _scheduleAutoRefresh());
  }

  /// Refreshes the followed rooms every 信息页 › 关注刷新间隔 minutes, if set.
  void _scheduleAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    final minutes = ThemeSettingsController.normalizeLivePanelFollowRefreshMinutes(
      SettingsService.to.theme.livePanelFollowRefreshMinutes.v,
    );
    if (minutes <= 0) return;
    _autoRefreshTimer = Timer.periodic(Duration(minutes: minutes), (_) => _refresh());
  }

  void _refresh() {
    if (!mounted || refreshing.value) return;
    refreshing.value = true;
    EventBus.instance.emit('refresh_favorite_rooms', true);
  }

  void _updateRooms() {
    if (!mounted) return;
    final allRooms = FavoriteRoomController.to.favoriteRooms.v;

    // The same order as the home 关注 page (its 排序 setting).
    final liveList = allRooms.where((room) => room.isLiveNow && room.isRecord == false).toList();
    final recordList = allRooms.where((room) => room.effectiveLiveStatus == LiveStatus.replay).toList();
    sortFavoriteRooms(liveList);
    sortFavoriteRooms(recordList);
    onlineRooms.assignAll(liveList);
    recordingRooms.assignAll(recordList);

    loadingFinish.value = true;
    refreshing.value = false;
  }

  @override
  void dispose() {
    tabController.dispose();
    subscription?.cancel();
    _favoritesWorker?.dispose();
    _sortWorker?.dispose();
    _autoRefreshWorker?.dispose();
    _autoRefreshTimer?.cancel();
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
          // No gap above the tabs: the panel's title row is right above them.
          // 排序 on the left and refresh on the right, equally wide, keep the
          // tabs centred.
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Row(
            children: [
              const FavoriteSortButton(key: ValueKey('follow-panel-sort')),
              Expanded(
                // The two tabs share the row equally, each label centred in
                // its half; the bar is narrowed so the labels sit closer than
                // the full row put them (see _followTabsWidth). A row that
                // scrolls its tabs keeps the full width.
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = textMetrics.scrollTabs
                        ? constraints.maxWidth
                        : _followTabsWidth(context, constraints.maxWidth);
                    return Center(
                      child: SizedBox(
                        width: width,
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
                    );
                  },
                ),
              ),
              Obx(
                () => IconButton(
                  key: const ValueKey('room-history-refresh'),
                  tooltip: i18n('refresh'),
                  visualDensity: VisualDensity.compact,
                  onPressed: refreshing.value ? null : _refresh,
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
    return Builder(
      builder: (context) {
        return Obx(() {
          final current = widget.controller.state.value.room.detail;
          // Rows are the compact room card's height, under the same settings.
          final dense = SettingsService.to.app.enableDenseFavorites.v;
          // The gap between rows is 房间卡片设置's row spacing for the compact
          // rows, as on the home 关注 page in that layout.
          final spacing = SettingsService.to.theme.cardMainSpacing(compact: true);
          final rowExtent = RoomCardLayoutMetrics.compactHeight(
            appearance: SettingsService.to.roomCard.resolve().copyWith(layout: RoomCardLayout.compact),
            dense: dense,
            textScaler: MediaQuery.textScalerOf(context),
          );
          // The panel's compact text would make these rows a step smaller
          // than the same cards on the home page; give them the app's sizes.
          return Theme(
            data: Theme.of(context).copyWith(textTheme: Get.theme.textTheme),
            child: GridView.builder(
              key: ValueKey(history ? 'watch-history-grid' : 'live-room-grid'),
              padding: const EdgeInsets.fromLTRB(padding, 2, padding, padding),
              physics: const PureLiveScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 1,
                mainAxisExtent: rowExtent,
                mainAxisSpacing: spacing,
              ),
              itemCount: rooms.length,
              itemBuilder: (context, index) {
                final room = rooms[index];
                final playing = current != null && room.hasSameIdentity(current);

                // The home page's compact row, following 房间卡片设置; here a
                // tap switches rooms and the room on screen is outlined.
                return RoomCard(
                  key: ValueKey('follow-room-${room.platform}:${room.roomId}'),
                  room: room,
                  dense: dense,
                  forceCompact: true,
                  longPressDetails: false,
                  highlighted: playing,
                  status: playing
                      ? i18n('now_watching')
                      : history
                      ? _historyLabel(room)
                      : null,
                  onSelect: () {
                    widget.onSwitch?.call();
                    widget.controller.switchRoom(room);
                  },
                );
              },
            ),
          );
        });
      },
    );
  }
}

/// The width of the 关注 panel's two tabs within [rowWidth]. The full row set
/// each label in the middle of its half, [rowWidth] / 2 minus a label apart;
/// this width keeps a share of that gap: half on touch layouts, three
/// quarters with a pointer, where half read crowded.
double _followTabsWidth(BuildContext context, double rowWidth) {
  final share = AppLayout.of(context).touch ? 0.5 : 0.75;
  final style = Theme.of(context).textTheme.labelLarge;
  final scaler = MediaQuery.textScalerOf(context);
  double labelWidth(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    // The tab's icon and the gap after it.
    return 14 + 3 + width;
  }

  final label = (labelWidth(i18n('online_room_title')) + labelWidth(i18n('recording_room_title'))) / 2;
  // Never so narrow that a tab (label plus 6 padding a side) has to shrink
  // its label.
  final gap = rowWidth / 2 - label;
  return (2 * label + 2 * share * gap).clamp(math.min(rowWidth, 2 * (label + 12)), rowWidth).toDouble();
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

/// When a 录播 room was last watched, for its row's status.
String _historyLabel(LiveRoom room) {
  final value = room.lastWatchedAt;
  if (value == null || value <= 0) return i18n('history_earlier');
  return i18n('watched_at', args: {'time': formatHistoryWatchedAt(value)});
}

String formatHistoryWatchedAt(int millisecondsSinceEpoch) {
  final watched = DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch);
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${watched.year.toString().padLeft(4, '0')}-'
      '${twoDigits(watched.month)}-${twoDigits(watched.day)} '
      '${twoDigits(watched.hour)}:${twoDigits(watched.minute)}';
}
