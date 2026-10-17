import 'dart:math' as math;
import 'package:pure_live/core/widgets/refresh_indicators.dart';
import 'dart:async';

import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/utils/event_bus.dart';
import 'package:pure_live/core/config/room_card_settings_controller.dart';
import 'package:pure_live/core/config/theme_settings_controller.dart';
import 'package:pure_live/core/config/live_panel_layout.dart';
import 'package:pure_live/core/player/presentation/player_side_panel.dart';
import 'package:pure_live/domains/live/domain/global_player_service.dart';
import 'package:pure_live/domains/live/data/favorite_room_controller.dart';
import 'package:pure_live/domains/live/presentation/favorite/favorite_sort.dart';
import 'package:pure_live/domains/live/presentation/playback/controllers/live_play_controller.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/content_first_panel_layout.dart';
import 'package:pure_live/domains/live/presentation/widgets/room_card.dart';
import 'package:pure_live/domains/live/presentation/widgets/room_card_layout.dart';

/// Shows 关注 for a long press on the video area, like Simple Live: outside
/// fullscreen the room's info page turns to its 关注 tab. In fullscreen, or
/// when that tab is turned off (or the room has no info page, IPTV), the 关注
/// panel opens instead: from the bottom on the narrow inline player, from the
/// right elsewhere.
void showFollowPanel(BuildContext context, LivePlayController controller) {
  final fullscreen = GlobalPlayerService.instance.player.fullscreenUI;
  if (!fullscreen && controller.showPanelTab(LivePanelTab.follow)) return;
  unawaited(
    showPlayerPanel<void>(
      context,
      asBottomSheet: AppLayout.of(context).phone && !fullscreen,
      builder: (_) => CompactText(child: PlayOther(controller: controller)),
    ),
  );
}

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

/// The followed rooms that are live, one tap away from replacing the room
/// being watched. Used by the room panel's 关注 tab and by the fullscreen
/// [PlayOther] panel.
///
/// Pulled down it refreshes, with the home lists' refresh ball; in the
/// desktop layout ([AppLayout.refreshByButton]) a button at its bottom right
/// does too. The order is the home 关注 page's 排序 setting.
class FollowRoomSwitcher extends StatefulWidget {
  const FollowRoomSwitcher({required this.controller, this.onSwitch, super.key});

  final LivePlayController controller;

  /// Runs before switching, e.g. to close the hosting dialog.
  final VoidCallback? onSwitch;

  @override
  State<FollowRoomSwitcher> createState() => _FollowRoomSwitcherState();
}

class _FollowRoomSwitcherState extends State<FollowRoomSwitcher> {
  final onlineRooms = <LiveRoom>[].obs;
  final loadingFinish = false.obs;

  /// The refresh in progress; a pull or a press meanwhile joins it.
  Completer<void>? _refreshing;

  /// Lets the desktop refresh button run the pull's refresh, so the same
  /// refresh ball shows it (as on the home lists).
  final EasyRefreshController _refreshController = EasyRefreshController();

  /// A refresh that never reports back still lets the ball go.
  static const Duration _refreshTimeout = Duration(seconds: 30);

  StreamSubscription<dynamic>? subscription;
  Worker? _favoritesWorker;
  Worker? _sortWorker;
  Worker? _autoRefreshWorker;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();

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
    _autoRefreshTimer = Timer.periodic(Duration(minutes: minutes), (_) => unawaited(_refresh()));
  }

  /// Asks the 关注 controller to refresh and completes when it reports back.
  Future<void> _refresh() {
    final running = _refreshing;
    if (running != null) return running.future;
    final completer = Completer<void>();
    _refreshing = completer;
    _refreshesStarted++;
    EventBus.instance.emit('refresh_favorite_rooms', true);
    return completer.future.timeout(_refreshTimeout, onTimeout: _finishRefresh);
  }

  int _refreshesStarted = 0;

  /// The desktop button: the refresh ball drops in and runs the refresh;
  /// if it cannot (the header is busy or out of reach), the refresh runs
  /// without it.
  Future<void> _refreshByButton() async {
    final started = _refreshesStarted;
    await _refreshController.callRefresh();
    if (mounted && _refreshesStarted == started) await _refresh();
  }

  void _finishRefresh() {
    final running = _refreshing;
    _refreshing = null;
    if (running != null && !running.isCompleted) running.complete();
  }

  void _updateRooms() {
    if (!mounted) return;
    final allRooms = FavoriteRoomController.to.favoriteRooms.v;

    // The same order as the home 关注 page (its 排序 setting).
    final liveList = allRooms.where((room) => room.isLiveNow && room.isRecord == false).toList();
    sortFavoriteRooms(liveList);
    onlineRooms.assignAll(liveList);

    loadingFinish.value = true;
    _finishRefresh();
  }

  @override
  void dispose() {
    subscription?.cancel();
    _favoritesWorker?.dispose();
    _sortWorker?.dispose();
    _autoRefreshWorker?.dispose();
    _autoRefreshTimer?.cancel();
    _finishRefresh();
    _refreshController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final refreshByButton = AppLayout.of(context).refreshByButton;
    return Stack(
      children: [
        Positioned.fill(
          child: Obx(
            () => loadingFinish.value
                ? EasyRefresh.builder(
                    // A floating ball over the list, as on the home lists.
                    header: floatingRefreshHeader(),
                    controller: _refreshController,
                    triggerAxis: Axis.vertical,
                    onRefresh: _refresh,
                    childBuilder: (context, physics) => _buildRoomList(onlineRooms, physics),
                  )
                : AppStatusView(type: AppStatusType.loading, title: '', subtitle: ''),
          ),
        ),
        if (refreshByButton)
          Positioned(
            right: 12,
            bottom: 12,
            child: FloatingActionButton.small(
              key: const ValueKey('follow-panel-refresh'),
              heroTag: null,
              tooltip: i18n('refresh'),
              onPressed: () => unawaited(_refreshByButton()),
              child: const Icon(Icons.refresh_rounded),
            ),
          ),
      ],
    );
  }

  Widget _buildRoomList(List<LiveRoom> rooms, ScrollPhysics physics) {
    if (rooms.isEmpty) {
      // Still a scroll view, so an empty list can be pulled to refresh.
      return CustomScrollView(
        physics: physics,
        slivers: [SliverFillRemaining(hasScrollBody: false, child: AppStatusView(type: AppStatusType.empty))],
      );
    }

    // One column of avatar rows at every width: no covers, the same list in
    // the side panel and in the fullscreen panel.
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
            appearance: SettingsService.to.roomCard.appearanceFor(RoomCardLayout.compact),
            dense: dense,
            textScaler: MediaQuery.textScalerOf(context),
          );
          // The panel's compact text would make these rows a step smaller
          // than the same cards on the home page; give them the app's sizes.
          return Theme(
            data: Theme.of(context).copyWith(textTheme: Get.theme.textTheme),
            child: GridView.builder(
              key: const ValueKey('live-room-grid'),
              // The same margin on every side, the top included.
              padding: const EdgeInsets.all(LivePanelTab.listPadding),
              physics: physics,
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
                  status: playing ? i18n('now_watching') : null,
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
