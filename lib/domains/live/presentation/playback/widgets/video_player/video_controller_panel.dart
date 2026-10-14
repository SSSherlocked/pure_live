import 'dart:async';
import 'dart:math' as math;

import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/player/presentation/player_menu_choice.dart';
import 'package:pure_live/core/config/live_panel_layout.dart';
import 'package:pure_live/domains/live/data/platforms/sites.dart';
import 'package:pure_live/core/player/core/portrait_stream_support.dart';
import 'package:pure_live/domains/live/domain/global_player_service.dart';
import 'package:pure_live/core/player/presentation/player_ui_controller.dart';
import 'package:pure_live/core/player/presentation/player_control_density.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/video_player/player_control_policy.dart';
import 'package:pure_live/domains/live/presentation/playback/states/ui_state.dart';
import 'package:pure_live/domains/live/presentation/playback/states/live_room_status.dart';
import 'package:pure_live/domains/live/presentation/playback/dialogs/play_other.dart';
import 'package:pure_live/domains/live/presentation/playback/states/player_state.dart';
import 'package:pure_live/core/player/presentation/danmaku/player_danmaku_actions.dart';
import 'package:pure_live/core/player/presentation/danmaku/player_danmaku_surface.dart';
import 'package:pure_live/core/player/presentation/danmaku/danmaku_surface_settings.dart';
import 'package:pure_live/domains/live/presentation/playback/pages/danmaku_settings_page.dart';
import 'package:pure_live/domains/live/presentation/playback/dialogs/known_room_link_dialog.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/video_player/volume_control.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/layout/control_hover_region.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/video_player/video_controller.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/video_player/player_super_chat_overlay.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/layout/bottom_control_surface.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/video_player/iptv_schedule_dialog.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/layout/portrait_fullscreen_interaction.dart';
import 'package:pure_live/core/player/presentation/player_side_panel.dart';
import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/player/presentation/left_submenu_button.dart';
import 'package:pure_live/domains/live/presentation/playback/dialogs/video_details_dialog.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/button/live_play_menu_button.dart';

/// The full-surface gesture layer sits below the visible controller bars, but
/// platform accessibility/input bridges can still deliver a tap to that layer
/// while a control is animating. Never reinterpret a tap inside either bar as
/// an on-video danmaku interaction. This also protects the audio/cast/PiP and
/// quality/fullscreen actions from opening a danmaku action sheet instead.
@visibleForTesting
bool shouldHandleVideoSurfaceTap({
  required Offset localPosition,
  required Size surfaceSize,
  required bool controlsVisible,
  double controlBarHeight = 56,
}) {
  if (!controlsVisible || surfaceSize.height <= 0) return true;
  final guardedHeight = controlBarHeight.clamp(0.0, surfaceSize.height / 2).toDouble();
  return localPosition.dy > guardedHeight && localPosition.dy < surfaceSize.height - guardedHeight;
}

/// Launcher home-gesture strip (swipe up to system desktop) at the bottom of
/// mobile screens. Android/iOS deliver the pointer to the app first and cancel
/// it once the launcher gesture is recognized, so a brightness/volume drag
/// started inside the strip always ends with a half-applied volume/brightness
/// change and no way to undo it. The strip never starts such a drag.
const double systemHomeGestureZoneHeight = 48;

/// Whether a surface-local drag start lies inside the launcher gesture strip.
@visibleForTesting
bool startsInSystemHomeGestureZone({required Offset localPosition, required Size surfaceSize}) {
  if (surfaceSize.height <= 0) return false;
  final zoneHeight = systemHomeGestureZoneHeight.clamp(0.0, surfaceSize.height / 3);
  return localPosition.dy >= surfaceSize.height - zoneHeight;
}

/// The minimum a fullscreen control bar keeps clear of the top edge.
///
/// A device whose panel physically reserves the notch can report a zero top
/// inset once the status bar hides (immersive fullscreen) — the notch does not
/// go away with the status bar. This is the floor the bar falls back to in that
/// case only: the height of a phone status bar, which is what the cutout occupies
/// and what the bar cleared a moment earlier.
const double fullscreenBlindTopInset = 28;

/// The top inset a player's control bar adds, with the immersive fallback.
@visibleForTesting
double playerBarTopInset({required double viewPaddingTop, required bool portraitFullscreen}) {
  if (viewPaddingTop > 0) return viewPaddingTop;
  return portraitFullscreen ? fullscreenBlindTopInset : 0;
}

/// The system safe area a control bar adds to its own position.
///
/// The picture is full-bleed — nobody wraps it in a `SafeArea`, because that
/// would shrink the video — so every bar has to place itself. `viewPadding` is
/// the raw system inset and is deliberately used instead of `padding`: a
/// `SafeArea` anywhere above a bar *consumes* the padding, and a bar that reads
/// zero slides back under the status bar or the gesture bar. That is exactly how
/// the portrait fullscreen bar ended up under the notch.
EdgeInsets playerBarInsets(BuildContext context, {bool portraitFullscreen = false}) {
  final view = MediaQuery.viewPaddingOf(context);
  return EdgeInsets.fromLTRB(
    view.left,
    playerBarTopInset(viewPaddingTop: view.top, portraitFullscreen: portraitFullscreen),
    view.right,
    view.bottom,
  );
}

@visibleForTesting
String fullscreenActionLabelKey(bool expanded) => expanded ? 'exit_fullscreen' : 'enter_fullscreen';

@visibleForTesting
String playerWindowActionLabelKey(bool expanded) => expanded ? 'collapse_player_window' : 'expand_player_window';

class VideoControllerPanel extends StatefulWidget {
  final VideoController controller;

  const VideoControllerPanel({super.key, required this.controller});

  @override
  State<StatefulWidget> createState() => _VideoControllerPanelState();
}

class _VideoControllerPanelState extends State<VideoControllerPanel> {
  static const barHeight = 56.0;
  final MenuController _moreMenu = MenuController();
  Offset? _lastTapGlobalPosition;
  Offset? _lastTapLocalPosition;

  VideoController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.enableController();
    });
  }

  /// 小窗播放 from the ⋯ menu (Android), the same as the Windows bar button.
  Future<void> _enterPip() async {
    final service = GlobalPlayerService.instance;
    if (!service.initialized || service.player.isPipPreparing.value) return;
    try {
      await controller.livePlayController.enterPipPresentation();
    } catch (_) {
      ToastUtil.show(i18n('pip_enter_failed'));
    }
  }

  void _castCurrentRoom(BuildContext context) {
    controller.enableController();
    KnownRoomLinkDialog.castPlayUrlByRoomId(
      context: context,
      liveroom: controller.room,
      isCurrentRoom: () => controller.status != PlayerStatus.disposed,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Focus(
        autofocus: true,
        child: Obx(() {
          final double currentVolume = controller.currentVolume.value;
          final int percentage = (currentVolume * 100).round();
          final screenMode = controller.livePlayController.state.value.ui.screenMode;
          // An upright phone tightens the floating controls, inline and in
          // fullscreen alike (a 56 px top bar left the inline title 18 px
          // below the picture's edge). Which controls show where: one table
          // (PlayerControlPolicy).
          final policy = PlayerControlPolicy.of(context);
          final compactControls = policy.compactControls;
          final topBarHeight = compactControls ? compactPlayerBarHeight : barHeight;
          // Like the top bar, the bottom one adds the system inset to its own
          // height, so a fullscreen bar clears the gesture bar.
          final bottomBarHeight = topBarHeight + playerBarInsets(context).bottom;
          final manager = GlobalPlayerService.instance.player;
          final portraitFullscreen = screenMode == VideoMode.portraitFullscreen;
          final verticalVideo = manager.isVerticalVideo.value;
          // The portrait source's own ⋯ entries, where its bar buttons were:
          // 画面方向 for a fullscreen vertical stream, 画面模式 only in the
          // portrait fullscreen, whose picture it arranges.
          final orientationEntry =
              policy.orientationControls &&
              (portraitFullscreen || (manager.isSystemFullscreen.value && verticalVideo));
          final displayModeEntry = policy.orientationControls && portraitFullscreen && verticalVideo;

          final IconData iconData = currentVolume <= 0
              ? Icons.volume_mute
              : currentVolume < 0.5
              ? Icons.volume_down
              : Icons.volume_up;

          return PlayerControlDensity.scope(
            compact: compactControls,
            child: MouseRegion(
              onHover: (_) => controller.onMouseHoverPlayer(),
              onExit: (_) => controller.onMouseExitPlayer(),
              cursor: !controller.showController.value ? SystemMouseCursors.none : SystemMouseCursors.basic,
              child: Stack(
                children: [
                  Container(
                    color: Colors.transparent,
                    alignment: Alignment.center,
                    child: AnimatedOpacity(
                      opacity: controller.showVolume.value ? 0.8 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: Card(
                        color: Colors.black,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(iconData, color: Colors.white),
                              Padding(
                                padding: const EdgeInsets.only(left: 8, right: 8),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SizedBox(
                                    width: 100,
                                    height: 20,
                                    child: LinearProgressIndicator(
                                      value: currentVolume,
                                      backgroundColor: Colors.white38,
                                      valueColor: const AlwaysStoppedAnimation(Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                              Text(
                                "$percentage%",
                                style: AppText.of(context).body.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Obx(() {
                    final manager = GlobalPlayerService.instance.player;
                    final hideForPortrait = PortraitDanmakuPolicy.hidesDanmaku(
                      isVerticalVideo: manager.isVerticalVideo.value,
                      mode: SettingsService.to.player.portraitDanmakuMode,
                    );
                    return Offstage(
                      offstage: controller.hideDanmaku.value || hideForPortrait,
                      child: PlayerDanmakuSurface(
                        key: controller.danmuKey,
                        controller: controller.danmakuController,
                        settings: controller,
                        isVerticalVideo: manager.isVerticalVideo.value,
                      ),
                    );
                  }),
                  // 在播放器中显示留言: bottom left, above the bottom bar and
                  // below the top bar. It takes no pointer. The small inline
                  // player of a phone leaves super chats to the 留言 tab below
                  // it, whatever the setting; fullscreen shows them.
                  Builder(
                    builder: (context) {
                      if (AppLayout.of(context).phone && !requiresSystemFullscreenExit(screenMode)) {
                        return const SizedBox.shrink();
                      }
                      final insets = playerBarInsets(
                        context,
                        portraitFullscreen: portraitFullscreen,
                      );
                      return Positioned.fill(
                        child: PlayerSuperChatOverlay(
                          controller: controller,
                          compact: compactControls,
                          padding: EdgeInsets.fromLTRB(
                            insets.left + (compactControls ? 8 : 12),
                            insets.top + topBarHeight,
                            insets.right,
                            bottomBarHeight + 4,
                          ),
                        ),
                      );
                    },
                  ),
                  GestureDetector(
                    // Opaque on purpose: this detector is what reveals and hides
                    // the bars, and its only child is the shared gesture layer,
                    // which paints nothing and declares itself translucent. With
                    // the default `deferToChild` the whole tap surface stopped
                    // hit-testing and tapping the video no longer showed the
                    // controls at all.
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) {
                      _lastTapGlobalPosition = details.globalPosition;
                      _lastTapLocalPosition = details.localPosition;
                    },
                    onTap: () {
                      final globalPosition = _lastTapGlobalPosition;
                      final localPosition = _lastTapLocalPosition;
                      if (localPosition != null &&
                          !shouldHandleVideoSurfaceTap(
                            localPosition: localPosition,
                            surfaceSize: context.size ?? Size.zero,
                            controlsVisible: controller.showController.value,
                            controlBarHeight: bottomBarHeight,
                          )) {
                        controller.enableController();
                        return;
                      }
                      if (globalPosition != null && controller.handleDanmakuPointer(globalPosition, longPress: false)) {
                        return;
                      }
                      // Touch: a second tap hides visible controls (upstream #886),
                      // as in other video apps. Desktop clicks keep revealing them.
                      if (policy.tapTogglesControls &&
                          controller.showController.value &&
                          GlobalPlayerService.instance.player.isPlayingNow) {
                        controller.toggleController();
                        return;
                      }
                      // A buffering/paused player must not swallow the only way
                      // to reveal its controls. Always expose the action bar; a
                      // tap on a paused surface keeps the historical resume
                      // behavior as well.
                      controller.enableController();
                      if (!GlobalPlayerService.instance.player.isPlayingNow) {
                        GlobalPlayerService.instance.player.togglePlayPause();
                      }
                    },
                    onLongPressStart: (details) {
                      if (!shouldHandleVideoSurfaceTap(
                        localPosition: details.localPosition,
                        surfaceSize: context.size ?? Size.zero,
                        controlsVisible: controller.showController.value,
                        controlBarHeight: bottomBarHeight,
                      )) {
                        controller.enableController();
                        return;
                      }
                      // Tap-and-hold pins the barrage under the finger; the
                      // message-actions menu opens as before, and releasing
                      // (with the menu closed) resumes the held message.
                      controller.pauseDanmakuAt(details.globalPosition);
                      final onDanmaku = controller.handleDanmakuPointer(details.globalPosition, longPress: true);
                      // A long press anywhere that is not on a barrage shows
                      // 关注, like Simple Live: outside fullscreen the room's
                      // info page turns to its 关注 tab. In fullscreen, or when
                      // that tab is turned off (or the room has no info page,
                      // IPTV), the 关注 panel opens instead: from the bottom on
                      // the narrow inline player, from the right elsewhere.
                      if (!onDanmaku && !controller.danmakuHeld && !controller.showLocked.value) {
                        final fullscreen = GlobalPlayerService.instance.player.fullscreenUI;
                        final inPage = !fullscreen && controller.livePlayController.showPanelTab(LivePanelTab.follow);
                        if (!inPage) {
                          unawaited(
                            showPlayerPanel<void>(
                              context,
                              asBottomSheet: AppLayout.of(context).phone && !fullscreen,
                              builder: (_) => CompactText(child: PlayOther(controller: controller.livePlayController)),
                            ),
                          );
                        }
                      }
                    },
                    onLongPressEnd: (_) => controller.resumeHeldDanmaku(),
                    onLongPressCancel: () => controller.resumeHeldDanmaku(),
                    onDoubleTap: () {
                      if (!controller.showLocked.value) {
                        GlobalPlayerService.instance.player.isWindowFullscreen.value
                            ? controller.toggleWindowFullScreen()
                            : controller.toggleFullScreenForSource();
                      }
                    },
                    child: PlayerGestureLayer(
                      controller: controller,
                      // The portrait-panel restore swipe owns the vertical drag
                      // while that transition is available; one drag must not
                      // mean both "restore the panel" and "change brightness".
                      enabled: screenMode != VideoMode.portraitFullscreen,
                    ),
                  ),
                  LockButton(controller: controller),
                  const PortraitStreamDiagnosticsBadge(),
                  TopActionBar(
                    controller: controller,
                    barHeight: topBarHeight,
                    moreMenu: _moreMenu,
                    // A portrait fullscreen owns the whole screen, so its top bar is
                    // the one that has to clear the notch on its own.
                    portraitFullscreen: portraitFullscreen,
                  ),
                  // Fixed anchor for the ⋯ menu at the top-right of the player.
                  // It does not move with the auto-hiding top bar, so an open
                  // menu stays put when the bar slides away.
                  Builder(
                    builder: (context) {
                      final insets = playerBarInsets(
                        context,
                        portraitFullscreen: portraitFullscreen,
                      );
                      return Positioned(
                        top: insets.top,
                        right: (compactControls ? 4 : 8) + insets.right,
                        child: PlayerMoreMenuAnchor(
                          menu: _moreMenu,
                          size: Size(
                            compactControls ? compactPlayerActionExtent : kMinInteractiveDimension,
                            topBarHeight,
                          ),
                          isAudioOnly: () => controller.isAudioOnly,
                          onToggleAudioOnly: () {
                            controller.enableController();
                            controller.toggleAudioOnly();
                          },
                          // 投屏 is a menu entry on Android, inline and fullscreen alike.
                          onCast: policy.castInMoreMenu ? () => _castCurrentRoom(context) : null,
                          onPip: policy.pipInMoreMenu ? () => unawaited(_enterPip()) : null,
                          // A portrait source's 画面模式 and 画面方向 lead the ⋯
                          // menu. Fullscreen hides the room page and its menu,
                          // so 录制 follows them and 视频详情 ends the menu.
                          leadingEntries: [
                            if (displayModeEntry) const PortraitDisplayModeMenuEntry(),
                            if (orientationEntry) PortraitOrientationMenuEntry(controller: controller),
                            if (policy.roomActionsInMoreMenu)
                              LiveRoomRecordMenuEntry(controller: controller.livePlayController),
                          ],
                          hostEntryLabels: [
                            if (displayModeEntry) i18n('portrait_display_mode_menu'),
                            if (orientationEntry) i18n('portrait_orientation_menu'),
                            if (policy.roomActionsInMoreMenu) ...[
                              i18n('record'),
                              i18n('recording'),
                              i18n('monitored'),
                              i18n('video_details'),
                            ],
                          ],
                          trailingEntries: [
                            if (policy.roomActionsInMoreMenu)
                              MenuItemButton(
                                key: const ValueKey('player-more-video-details'),
                                leadingIcon: const Icon(Remix.information_line, size: 18),
                                onPressed: () => unawaited(
                                  VideoDetailsDialog.showPanel(context, controller.livePlayController),
                                ),
                                child: Text(i18n('video_details'), maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: playerMenuLabelStyle),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                  BottomActionBar(
                    controller: controller,
                    barHeight: bottomBarHeight,
                    portraitFullscreen: portraitFullscreen,
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class ErrorWidget extends StatelessWidget {
  const ErrorWidget({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(i18n("play_video_failed"), style: AppText.of(context).listPrimary.copyWith(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () => controller.refresh(),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.2)),
            child: Text(i18n("retry"), style: AppText.of(context).sectionTitle.copyWith(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// Top action bar widgets
class TopActionBar extends StatelessWidget {
  const TopActionBar({
    super.key,
    required this.controller,
    required this.barHeight,
    required this.moreMenu,
    this.portraitFullscreen = false,
  });

  final VideoController controller;
  final double barHeight;

  /// Opens the ⋯ menu, which hangs off a fixed anchor outside this bar.
  final MenuController moreMenu;

  /// Whether this bar is the whole screen's top chrome, which is what makes the
  /// immersive-notch fallback apply.
  final bool portraitFullscreen;

  @override
  Widget build(BuildContext context) {
    // The picture fills the panel; only this bar has to stay out of the notch.
    // The inset is the raw system one, so this works whether the bar is over a
    // windowed video or a portrait fullscreen that owns the whole screen.
    final padding = playerBarInsets(context, portraitFullscreen: portraitFullscreen);
    // The compact bar adds no edge of its own: the buttons' padding is enough.
    final edge = PlayerControlDensity.compactOf(context) ? 0.0 : 8.0;
    return Obx(
      () => AnimatedPositioned(
        top: controller.showController.value && !controller.showLocked.value ? 0 : -(barHeight + padding.top),
        left: 0,
        right: 0,
        height: barHeight + padding.top,
        duration: const Duration(milliseconds: 300),
        child: ControlHoverRegion(
          enabled: controller.showController.value && !controller.showLocked.value,
          onEnter: controller.onMouseEnterController,
          onExit: controller.onMouseExitController,
          child: Container(
            height: barHeight + padding.top,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.transparent, Colors.black45],
              ),
            ),
            child: Padding(
              padding: EdgeInsets.only(top: padding.top, left: edge + padding.left, right: edge + padding.right),
              child: SizedBox(
                height: barHeight,
                child: Row(
                  children: [
                    for (final slot in PlayerControlPolicy.of(context).leadingSlots)
                      switch (slot) {
                        TopActionLeadingSlot.back => BackButton(controller: controller),
                      },

                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: PlayerControlDensity.compactOf(context) ? 6 : 12,
                          vertical: 4,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _liveRoomTitle(controller.room),
                              overflow: TextOverflow.ellipsis,
                              style: AppText.of(context).sectionTitle.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.none,
                              ),
                            ),
                            if (_liveProgramme(controller.room) case final programme?) ...[
                              const SizedBox(height: 2),
                              Text(
                                "${i18n('now_playing')}: $programme",
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    if (controller.room.platform == Sites.iptvSite)
                      IconButton(
                        icon: const Icon(Icons.assignment_outlined),
                        tooltip: i18n('view_schedule'),
                        visualDensity: VisualDensity.standard,
                        constraints: PlayerControlDensity.actionConstraints(context),
                        color: Colors.white,
                        onPressed: () => _showSchedule(context),
                      ),

                    for (final slot in PlayerControlPolicy.of(context).trailingSlots)
                      switch (slot) {
                        TopActionTrailingSlot.datetime => const DatetimeInfo(),
                        TopActionTrailingSlot.battery => BatteryInfo(controller: controller),
                      },
                    // ⋯ (画面比例 / 纯音频 / 投屏 / 小窗) closes the top-right
                    // group, inline and in fullscreen alike.
                    // Red while the room records, beside the ⋯ in fullscreen.
                    if (PlayerControlPolicy.of(context).roomActionsInMoreMenu)
                      LiveRoomRecordingIndicator(controller: controller.livePlayController),
                    PlayerMoreMenuButton(key: const ValueKey('player-top-more-menu'), menu: moreMenu),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showSchedule(BuildContext context) async {
    if (controller.isMenuOpen.value) return;
    controller.isMenuOpen.value = true;
    controller.stopHideController();
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          contentPadding: EdgeInsets.zero,
          content: IptvScheduleDialogContent(controller: controller),
        ),
      );
    } finally {
      if (controller.status != PlayerStatus.disposed) {
        controller.isMenuOpen.value = false;
        controller.enableController();
      }
    }
  }
}

class DatetimeInfo extends StatefulWidget {
  const DatetimeInfo({super.key});

  @override
  State<DatetimeInfo> createState() => _DatetimeInfoState();
}

class _DatetimeInfoState extends State<DatetimeInfo> {
  DateTime dateTime = DateTime.now();
  Timer? refreshDateTimer;

  @override
  void initState() {
    super.initState();
    refreshDateTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      setState(() => dateTime = DateTime.now());
    });
  }

  @override
  void dispose() {
    refreshDateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // get system time and format
    var hour = dateTime.hour.toString();
    if (hour.length < 2) hour = '0$hour';
    var minute = dateTime.minute.toString();
    if (minute.length < 2) minute = '0$minute';

    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      child: Text(
        '$hour:$minute',
        style: const TextStyle(color: Colors.white, decoration: TextDecoration.none),
      ),
    );
  }
}

class BatteryInfo extends StatefulWidget {
  const BatteryInfo({super.key, required this.controller});

  final VideoController controller;

  @override
  State<BatteryInfo> createState() => _BatteryInfoState();
}

class _BatteryInfoState extends State<BatteryInfo> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() => widget.controller.hasBattery.value ? _buildBattery() : const SizedBox.shrink());
  }

  Widget _buildBattery() {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: Container(
        width: 35,
        height: 15,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.4),
          border: Border.all(color: Colors.white),
          borderRadius: BorderRadius.circular(4),
        ),
        // A 15 px box: on a phone the tag role with the text scale is taller
        // than the box, and the overflowing text box sat the digits low.
        // Scaled down to fit, the line box is centred whatever the font.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Obx(
            () => Text(
              '${widget.controller.batteryLevel.value}',
              // One line, even leading: no extra space above or below.
              textHeightBehavior: const TextHeightBehavior(
                applyHeightToFirstAscent: false,
                applyHeightToLastDescent: false,
              ),
              style: AppText.of(context).tag.copyWith(
                color: Colors.white,
                decoration: TextDecoration.none,
                height: 1,
                leadingDistribution: TextLeadingDistribution.even,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BackButton extends StatelessWidget {
  const BackButton({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () async {
        final player = GlobalPlayerService.instance.player;
        final navigator = Navigator.of(context);
        // The on-screen back always leaves the room. Fullscreen is the same
        // page, so stopping at the inline player cost a second press; Esc and
        // the window controls still just leave fullscreen.
        if (player.isWindowFullscreen.value || player.isSystemFullscreen.value) {
          await controller.livePlayController.exitPresentationForSystemBack();
          // Let the back scope rebuild with canPop restored before popping.
          await WidgetsBinding.instance.endOfFrame;
        }
        if (navigator.mounted) await navigator.maybePop();
      },
      constraints: PlayerControlDensity.actionConstraints(context),
      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
    );
  }
}

/// 画面方向 in the ⋯ menu of a fullscreen vertical stream: whether this room's
/// source counts as portrait (自动识别 / 强制竖屏 / 强制横屏), plus the global
/// 记住单个直播间方向 switch, which decides whether a choice outlives the
/// session.
class PortraitOrientationMenuEntry extends StatelessWidget {
  const PortraitOrientationMenuEntry({super.key, required this.controller});

  final VideoController controller;

  void _select(PortraitOrientationOverride value) {
    final settings = SettingsService.to.player;
    settings.setPortraitOverrideForRoom(controller.room, value, remember: settings.rememberPortraitRoomOverride.v);
    GlobalPlayerService.instance.player.refreshPortraitPresentationPolicy();
  }

  /// Flips the switch and keeps the room's current choice in step with it,
  /// as picking that choice again would.
  void _toggleRemember() {
    final settings = SettingsService.to.player;
    final remember = !settings.rememberPortraitRoomOverride.v;
    settings.rememberPortraitRoomOverride.v = remember;
    final current = settings.portraitOverrideForRoom(controller.room);
    if (current != PortraitOrientationOverride.automatic) {
      settings.setPortraitOverrideForRoom(controller.room, current, remember: remember);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final settings = SettingsService.to.player;
      final selected = settings.portraitOverrideForRoom(controller.room);
      final remember = settings.rememberPortraitRoomOverride.v;
      final rememberLabel = i18n('portrait_remember_room_override');
      final labels = [for (final value in PortraitOrientationOverride.values) _overrideLabel(value), rememberLabel];
      // The switch's check box and its gap.
      const leadingWidth = 18.0 + 12;
      return LeftSubmenuButton(
        key: const ValueKey('player-more-portrait-orientation'),
        leadingIcon: Icon(switch (selected) {
          PortraitOrientationOverride.automatic => Icons.screen_rotation_alt_rounded,
          PortraitOrientationOverride.portrait => Icons.stay_current_portrait_rounded,
          PortraitOrientationOverride.landscape => Icons.stay_current_landscape_rounded,
        }, size: 18),
        labels: labels,
        entryLeadingWidth: leadingWidth,
        menuChildren: [
          for (final value in PortraitOrientationOverride.values)
            PlayerMenuChoice(
              key: ValueKey('player-portrait-orientation-${value.name}'),
              label: _overrideLabel(value),
              labels: labels,
              extraWidth: leadingWidth,
              selected: selected == value,
              onPressed: () => _select(value),
            ),
          const Divider(height: 1),
          MenuItemButton(
            key: const ValueKey('player-portrait-orientation-remember'),
            // A switch: the menu stays open to show its new state.
            closeOnActivate: false,
            leadingIcon: Icon(
              remember ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              size: 18,
              color: remember ? Theme.of(context).colorScheme.primary : null,
            ),
            onPressed: _toggleRemember,
            child: Text(
              rememberLabel,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: playerMenuLabelStyle,
            ),
          ),
        ],
        child: Text(
          i18n('portrait_orientation_menu'),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: playerMenuLabelStyle,
        ),
      );
    });
  }
}

/// 画面模式 in the ⋯ menu of a portrait fullscreen: how a portrait source uses
/// the upright screen (the setting 竖屏全屏画面模式). The orientation entry
/// decides what the source is; this one how a confirmed portrait source fills
/// the phone.
class PortraitDisplayModeMenuEntry extends StatelessWidget {
  const PortraitDisplayModeMenuEntry({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final settings = SettingsService.to.player;
      final selected = settings.portraitFullscreenDisplayMode;
      final labels = [for (final mode in PortraitFullscreenDisplayMode.values) _displayModeLabel(mode)];
      return LeftSubmenuButton(
        key: const ValueKey('player-more-portrait-display-mode'),
        leadingIcon: Icon(switch (selected) {
          PortraitFullscreenDisplayMode.complete => Icons.crop_free_rounded,
          PortraitFullscreenDisplayMode.ambient => Icons.blur_on_rounded,
          PortraitFullscreenDisplayMode.balanced => Icons.fit_screen_rounded,
          PortraitFullscreenDisplayMode.cover => Icons.fullscreen_rounded,
        }, size: 18),
        labels: labels,
        menuChildren: [
          for (final mode in PortraitFullscreenDisplayMode.values)
            PlayerMenuChoice(
              key: ValueKey('player-portrait-display-mode-${mode.name}'),
              label: _displayModeLabel(mode),
              labels: labels,
              selected: selected == mode,
              onPressed: () => settings.portraitFullscreenDisplayModeName.v = mode.name,
            ),
        ],
        child: Text(
          i18n('portrait_display_mode_menu'),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: playerMenuLabelStyle,
        ),
      );
    });
  }
}

String _displayModeLabel(PortraitFullscreenDisplayMode value) => switch (value) {
  PortraitFullscreenDisplayMode.complete => i18n('portrait_fullscreen_display_complete'),
  PortraitFullscreenDisplayMode.ambient => i18n('portrait_fullscreen_display_ambient'),
  PortraitFullscreenDisplayMode.balanced => i18n('portrait_fullscreen_display_balanced'),
  PortraitFullscreenDisplayMode.cover => i18n('portrait_fullscreen_display_cover'),
};

class PortraitStreamDiagnosticsBadge extends StatelessWidget {
  const PortraitStreamDiagnosticsBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final settings = SettingsService.to.player;
      if (!settings.showPortraitDiagnostics.v) return const SizedBox.shrink();
      final manager = GlobalPlayerService.instance.player;
      final geometry = manager.videoGeometry;
      final roomOverride = settings.portraitOverrideForRoom(manager.currentFloatRoom);
      final orientation = manager.effectiveVideoOrientation;
      final pending = geometry.candidateOrientation != geometry.orientation;
      final ratio = geometry.hasValidDimensions ? geometry.aspectRatio.toStringAsFixed(3) : '--';
      final effectiveRatio = geometry.hasValidDimensions ? geometry.effectiveAspectRatio.toStringAsFixed(3) : '--';
      final evidence = geometry.evidence.name;
      final state = pending ? '${_orientationLabel(geometry.candidateOrientation)}…' : _orientationLabel(orientation);
      final observedAt = geometry.observedAt;
      final observedTime = observedAt == null
          ? '--:--:--'
          : '${observedAt.hour.toString().padLeft(2, '0')}:'
                '${observedAt.minute.toString().padLeft(2, '0')}:'
                '${observedAt.second.toString().padLeft(2, '0')}';
      return Positioned(
        key: const ValueKey('portrait-stream-diagnostics'),
        top: 62,
        left: 12,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              child: Text(
                '${geometry.width > 0 ? geometry.width : '--'}×${geometry.height > 0 ? geometry.height : '--'}  '
                '$ratio→$effectiveRatio  $state  ${_overrideLabel(roomOverride)}\n'
                '$evidence  C${(geometry.confidence * 100).round()}%  S${geometry.stableSampleCount}  $observedTime',
                style: AppText.of(context).tag.copyWith(color: Colors.white, decoration: TextDecoration.none),
              ),
            ),
          ),
        ),
      );
    });
  }
}

String _orientationLabel(VideoSourceOrientation value) => switch (value) {
  VideoSourceOrientation.portrait => i18n('portrait_orientation_portrait'),
  VideoSourceOrientation.landscape => i18n('portrait_orientation_landscape'),
  VideoSourceOrientation.square => i18n('portrait_orientation_square'),
  VideoSourceOrientation.unknown => i18n('portrait_orientation_unknown'),
};

String _overrideLabel(PortraitOrientationOverride value) => switch (value) {
  PortraitOrientationOverride.automatic => i18n('portrait_override_auto'),
  PortraitOrientationOverride.portrait => i18n('portrait_override_portrait'),
  PortraitOrientationOverride.landscape => i18n('portrait_override_landscape'),
};

/// The fullscreen controls lock, at the middle of the picture's right edge:
/// the size of the other player controls, on a translucent disc.
class LockButton extends StatelessWidget {
  const LockButton({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => AnimatedOpacity(
        opacity: (GlobalPlayerService.instance.player.fullscreenUI && controller.showController.value) ? 0.9 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: Align(
          alignment: Alignment.centerRight,
          child: AbsorbPointer(
            absorbing: !controller.showController.value,
            child: Padding(
              padding: const EdgeInsets.only(right: 20.0),
              child: IconButton(
                tooltip: i18n(controller.showLocked.value ? 'unlock_player_controls' : 'lock_player_controls'),
                onPressed: controller.showLocked.toggle,
                constraints: PlayerControlDensity.actionConstraints(context),
                icon: Icon(
                  controller.showLocked.value ? Icons.lock_rounded : Icons.lock_open_rounded,
                  size: PlayerControlDensity.iconSize(context, 24),
                ),
                color: Colors.white,
                style: IconButton.styleFrom(backgroundColor: Colors.black38, shape: const CircleBorder()),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact fullscreen entry for quality and CDN-line selection. Both controls
/// live in one landscape panel, avoiding two narrow menus competing for the
/// bottom-right safe area.
class FullscreenStreamSelectorButton extends StatelessWidget {
  const FullscreenStreamSelectorButton({super.key, required this.controller, this.compact = false});

  final VideoController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final live = controller.livePlayController;
      final state = live.state.value.player;
      final status = LiveRoomStatus.of(live);
      if (!live.state.value.room.success || !status.hasStream) {
        return const SizedBox.shrink();
      }
      final switching = live.playerController.isStreamSwitching.value;

      // Quality and line are two chips, each opening its own list: one level,
      // so a list cannot drift away from its entry the way a submenu pushed up
      // from the bottom edge did. The line chip shows only with a second line.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _menu(
            context,
            key: const ValueKey('fullscreen-stream-selector'),
            icon: Icons.high_quality_rounded,
            label: status.qualityLabel,
            switching: switching,
            choices: [for (final quality in state.qualites) quality.quality],
            entries: [
              for (var index = 0; index < state.qualites.length; index++)
                PlayerMenuChoice(
                  key: ValueKey('stream-menu-quality-$index'),
                  label: state.qualites[index].quality,
                  labels: [for (final quality in state.qualites) quality.quality],
                  selected: state.currentQuality == index,
                  onPressed: switching
                      ? null
                      : () => unawaited(
                          live.setResolution(ReloadDataType.changeQuality, index, state.currentLineIndex),
                        ),
                ),
            ],
          ),
          if (state.lineCount > 1)
            _menu(
              context,
              key: const ValueKey('fullscreen-line-selector'),
              icon: Icons.alt_route_rounded,
              label: status.lineLabel,
              switching: switching,
              choices: [
                for (var line = 0; line < state.lineCount; line++)
                  i18n('toolbox_line', args: {'index': (line + 1).toString()}),
              ],
              entries: [
                for (var index = 0; index < state.lineCount; index++)
                  PlayerMenuChoice(
                    key: ValueKey('stream-menu-line-$index'),
                    label: i18n('toolbox_line', args: {'index': (index + 1).toString()}),
                    labels: [
                      for (var line = 0; line < state.lineCount; line++)
                        i18n('toolbox_line', args: {'index': (line + 1).toString()}),
                    ],
                    selected: state.currentLineIndex == index,
                    onPressed: switching
                        ? null
                        : () => unawaited(live.setResolution(ReloadDataType.changeLine, state.currentQuality, index)),
                  ),
              ],
            ),
        ],
      );
    });
  }

  /// A chip on the bar that opens one list; the list uses the compact roles.
  Widget _menu(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String label,
    required bool switching,
    required List<String> choices,
    required List<Widget> entries,
  }) {
    // The list is as wide as its longest choice (PlayerMenuChoice, in the
    // compact roles), so it can open centred on the chip; MenuAnchor still
    // flips it above or slides it back on screen where it does not fit.
    final compactLabel = compactTextTheme(Theme.of(context).textTheme).labelLarge ?? const TextStyle();
    final width = math.max(
      64.0,
      menuLabelWidth(context, choices, compactLabel.copyWith(fontWeight: FontWeight.w800)) + playerMenuItemPadding,
    );
    return MenuAnchor(
      style: const MenuStyle(alignment: Alignment.bottomCenter),
      alignmentOffset: Offset(-width / 2, 0),
      onOpen: () {
        controller.isMenuOpen.value = true;
        controller.stopHideController();
      },
      onClose: () {
        if (controller.status == PlayerStatus.disposed) return;
        controller.isMenuOpen.value = false;
        controller.enableController();
      },
      menuChildren: [for (final entry in entries) SizedBox(width: width, child: CompactText(child: entry))],
      builder: (context, menu, _) {
        // The compact bar (an upright phone) takes the compact buttons'
        // height, icons, spacing and one text role smaller.
        final dense = PlayerControlDensity.compactOf(context);
        final spinner = PlayerControlDensity.iconSize(context, 15);
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: dense ? 0 : 2),
          child: Material(
            key: key,
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: switching ? null : () => menu.isOpen ? menu.close() : menu.open(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: PlayerControlDensity.actionConstraints(context).minHeight),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: dense ? 5 : (compact ? 6 : 9)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      switching
                          ? SizedBox.square(
                              dimension: spinner,
                              child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          // The HQ glyph has more inner padding than the line glyph,
                          // so it is drawn a size larger to read the same.
                          : Icon(
                              icon,
                              size: PlayerControlDensity.iconSize(context, icon == Icons.high_quality_rounded ? 20 : 17),
                              color: Colors.white,
                            ),
                      SizedBox(width: dense ? 3 : 5),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: compact ? 72 : 120),
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: (dense ? AppText.of(context).secondary : AppText.of(context).body).copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// Bottom action bar widgets
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({
    super.key,
    required this.controller,
    required this.barHeight,
    required this.portraitFullscreen,
  });

  final VideoController controller;
  final double barHeight;
  // Keep the layout and its height from the same parent mode snapshot.
  final bool portraitFullscreen;

  @override
  Widget build(BuildContext context) {
    // Same rule as the top bar, at the other edge: the picture stays full-bleed
    // and this bar adds the raw system inset itself so it clears the gesture bar
    // (and a sideways cutout) instead of sitting under them.
    final padding = playerBarInsets(context);
    final compactControls = PlayerControlDensity.compactOf(context);
    final edge = compactControls ? 0.0 : 8.0;
    return Obx(() {
      bool shouldShow =
          (controller.showController.value || controller.isMenuOpen.value) && !controller.showLocked.value;
      return BottomControlSurface(
        visible: shouldShow,
        height: barHeight,
        child: ControlHoverRegion(
          enabled: shouldShow,
          onEnter: controller.onMouseEnterController,
          onExit: controller.onMouseExitController,
          child: PortraitFullscreenRestoreGestureRegion(
            enabled: portraitFullscreen,
            onRestore: () => unawaited(controller.exitPortraitFullScreen()),
            child: Container(
              height: barHeight,
              alignment: Alignment.bottomLeft,
              padding: EdgeInsets.fromLTRB(edge + padding.left, 0, edge + padding.right, padding.bottom),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black45],
                ),
              ),
              // The actions read settings (hide danmaku) and player state at
              // layout time, after the outer Obx has stopped listening, so
              // they get an Obx of their own.
              child: LayoutBuilder(
                builder: (context, constraints) => Obx(() {
                  final policy = PlayerControlPolicy.of(context);
                  final fullscreen = policy.fullscreen;
                  if (portraitFullscreen) {
                    return _buildPortraitFullscreenLayout(policy);
                  }
                  final compact = constraints.maxWidth < 760;
                  final left = _buildLeftActions(policy);
                  final right = _buildRightActions(policy, compact: compact);

                  if (fullscreen) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(children: [left, const Spacer(), right]),
                    );
                  }

                  // The inline bar scrolls when a phone is too narrow for
                  // every action. Fullscreen stays pinned outside the scroll
                  // view: as the last item it used to be clipped off-screen.
                  final pinExpand = !GlobalPlayerService.instance.player.isWindowFullscreen.value;
                  final inlineRight = _buildRightActions(policy, compact: false, includeExpand: !pinExpand);
                  return Row(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, scrollConstraints) => SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const PureLiveBoundedScrollPhysics(),
                            clipBehavior: Clip.hardEdge,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: scrollConstraints.maxWidth),
                              child: Padding(
                                padding: EdgeInsets.only(left: compactControls ? 0 : 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [left, inlineRight],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (pinExpand)
                        Padding(
                          padding: EdgeInsets.only(right: compactControls ? 0 : 8),
                          child: ExpandButton(controller: controller),
                        ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ),
      );
    });
  }

  /// The inline bar's single row, with the quality and line chips before
  /// the fullscreen button: the room's own quality row is hidden here.
  Widget _buildPortraitFullscreenLayout(PlayerControlPolicy policy) {
    return Row(
      children: [
        _buildLeftActions(policy),
        const Spacer(),
        FullscreenStreamSelectorButton(controller: controller, compact: true),
        if (!GlobalPlayerService.instance.player.isWindowFullscreen.value) ExpandButton(controller: controller),
      ],
    );
  }

  /// The same group in every mode — inline, fullscreen and portrait
  /// fullscreen — so a control never appears in one and not another.
  Widget _buildLeftActions(PlayerControlPolicy policy) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlayPauseButton(controller: controller),
        RefreshButton(controller: controller),
        if (!SettingsService.to.danmaku.hideDanmaku.value) ...[
          PlayerDanmakuButton(controller: controller),
          PlayerDanmakuSettingsButton(
            controller: controller,
            dockedInLandscape: policy.dockedDanmakuPanel,
            openInPlace: policy.danmakuSettingsInPanel
                ? () => controller.livePlayController.showPanelTab(LivePanelTab.danmakuSettings)
                : null,
            // The room keeps its bar up while the panel is open, exactly as the
            // private button did; the pinning is the caller's policy, not the
            // shared button's.
            onOpenChanged: (open) {
              controller.isMenuOpen.value = open;
              if (!open) controller.enableController();
            },
          ),
        ],
      ],
    );
  }

  Widget _buildRightActions(PlayerControlPolicy policy, {required bool compact, bool includeExpand = true}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // One-tap mute, then quality and line: both stay on the bar in every
        // mode, so entering or leaving fullscreen never shifts the controls.
        MuteToggleButton(controller: controller),
        if (policy.streamSelector) FullscreenStreamSelectorButton(controller: controller, compact: compact),
        if (policy.muteButton) RoomMuteButton(controller: controller),
        if (policy.windowFullscreenButton &&
            controller.supportWindowFull &&
            !GlobalPlayerService.instance.player.isSystemFullscreen.value)
          ExpandWindowButton(controller: controller),
        if (includeExpand && !GlobalPlayerService.instance.player.isWindowFullscreen.value)
          ExpandButton(controller: controller),
      ],
    );
  }
}

class PlayPauseButton extends StatelessWidget {
  const PlayPauseButton({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    final playerManager = GlobalPlayerService.instance.player;

    return StreamBuilder<bool>(
      stream: playerManager.onPlaying.distinct(),
      initialData: playerManager.isPlayingNow,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data ?? playerManager.isPlayingNow;
        return IconButton(
          key: const ValueKey('player-play-pause-action'),
          tooltip: i18n(isPlaying ? 'multiview_pause' : 'multiview_play'),
          visualDensity: VisualDensity.standard,
          constraints: PlayerControlDensity.actionConstraints(context),
          onPressed: () => playerManager.togglePlayPause(),
          icon: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
            size: PlayerControlDensity.iconSize(context, 24),
          ),
        );
      },
    );
  }
}

class RefreshButton extends StatelessWidget {
  const RefreshButton({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const ValueKey('player-refresh-action'),
      tooltip: i18n('refresh'),
      visualDensity: VisualDensity.standard,
      constraints: PlayerControlDensity.actionConstraints(context),
      onPressed: () => controller.refresh(),
      icon: const Icon(Icons.refresh_rounded, color: Colors.white),
    );
  }
}

String _liveRoomTitle(LiveRoom liveroom) {
  for (final candidate in [liveroom.title, liveroom.nick, liveroom.roomId]) {
    final value = candidate?.trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return i18n('untitled_room');
}

String? _liveProgramme(LiveRoom liveroom) {
  final programme = liveroom.currentProgramme?.trim() ?? '';
  return programme.isEmpty ? null : programme;
}

class ExpandWindowButton extends StatelessWidget {
  const ExpandWindowButton({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final expanded = GlobalPlayerService.instance.player.isWindowFullscreen.value;
      return IconButton(
        key: const ValueKey('player-window-expand-action'),
        tooltip: i18n(playerWindowActionLabelKey(expanded)),
        visualDensity: VisualDensity.standard,
        constraints: PlayerControlDensity.actionConstraints(context),
        onPressed: () => controller.toggleWindowFullScreen(),
        icon: RotatedBox(
          quarterTurns: 1,
          child: Icon(
            expanded ? Icons.unfold_less_rounded : Icons.unfold_more_rounded,
            color: Colors.white,
            size: PlayerControlDensity.iconSize(context, 24),
          ),
        ),
      );
    });
  }
}

class ExpandButton extends StatelessWidget {
  const ExpandButton({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final expanded = GlobalPlayerService.instance.player.isSystemFullscreen.value;
      return IconButton(
        key: const ValueKey('player-fullscreen-action'),
        tooltip: i18n(fullscreenActionLabelKey(expanded)),
        visualDensity: VisualDensity.standard,
        constraints: PlayerControlDensity.actionConstraints(context),
        // A vertical stream enters its portrait fullscreen, as a double tap does.
        onPressed: () => controller.toggleFullScreenForSource(),
        icon: Icon(
          expanded ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
          color: Colors.white,
          size: PlayerControlDensity.iconSize(context, 24),
        ),
      );
    });
  }
}

/// Speaker icon that mutes or restores the room in one tap. It shows the
/// current state: a speaker while sound plays, a crossed-out speaker at 0.
class MuteToggleButton extends StatelessWidget {
  const MuteToggleButton({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final muted = controller.currentVolume.value <= 0;
      return IconButton(
        key: const ValueKey('player-mute-toggle'),
        visualDensity: VisualDensity.standard,
        constraints: PlayerControlDensity.actionConstraints(context),
        iconSize: PlayerControlDensity.iconSize(context, 24),
        color: Colors.white,
        onPressed: () {
          controller.enableController();
          unawaited(controller.toggleMute());
        },
        icon: Icon(muted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
      );
    });
  }
}

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key, required this.controller});

  final DanmakuSettingsSource controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;
    final compactLandscape = isLandscape && size.height < 620;
    final targetWidth = isLandscape
        ? (size.width * (compactLandscape ? 0.44 : 0.38)).clamp(340.0, compactLandscape ? 460.0 : 540.0).toDouble()
        : (size.width * 0.92).clamp(300.0, 560.0).toDouble();
    final targetHeight = isLandscape ? size.height - (compactLandscape ? 12 : 24) : size.height * 0.84;
    final panelColor = colorScheme.surface;

    return Dialog(
      alignment: isLandscape ? Alignment.centerRight : Alignment.center,
      backgroundColor: Colors.transparent,
      shadowColor: theme.shadowColor.withValues(alpha: 0.45),
      elevation: 24,
      insetPadding: EdgeInsets.symmetric(horizontal: isLandscape ? 6 : 12, vertical: isLandscape ? 6 : 12),
      child: Container(
        key: const ValueKey('fullscreen-danmaku-settings-panel'),
        width: targetWidth,
        height: targetHeight,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: panelColor,
          borderRadius: isLandscape
              ? const BorderRadius.horizontal(left: Radius.circular(18), right: Radius.circular(8))
              : BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.7), width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, compactLandscape ? 6 : 10, 6, compactLandscape ? 6 : 10),
              child: Row(
                children: [
                  Container(
                    width: 3.5,
                    height: 18,
                    decoration: BoxDecoration(color: colorScheme.primary, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          i18n('settings_danmaku_title'),
                          style: AppText.of(context).sectionTitle.copyWith(fontWeight: FontWeight.w700).copyWith(color: colorScheme.onSurface),
                        ),
                        Text(
                          i18n('danmaku_realtime_hint'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.of(context).secondary.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('fullscreen-danmaku-settings-close'),
                    tooltip: i18n('close'),
                    visualDensity: VisualDensity.standard,
                    constraints: const BoxConstraints(
                      minWidth: kMinInteractiveDimension,
                      minHeight: kMinInteractiveDimension,
                    ),
                    color: colorScheme.onSurfaceVariant,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.7), height: 1, thickness: 0.8),
            Expanded(
              // PiP has a dedicated settings/preview page. Keeping those
              // controls out of the short landscape sheet leaves the live
              // picture visible and avoids a confusing nested long form.
              child: CompactText(
                child: DanmakuSettingsContent(controller: controller, embedded: true, includePipSettings: false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
