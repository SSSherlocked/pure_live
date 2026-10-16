import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/platform/platform_utils.dart';
import 'package:pure_live/core/player/kernel/floating_handle_keeper.dart';
import 'package:pure_live/core/player/kernel/player_kernel_service.dart';
import 'package:pure_live/core/player/presentation/fullscreen_window.dart' show WindowService;
import 'package:pure_live/domains/live/presentation/playback/controllers/live_play_controller.dart';
import 'package:pure_live/domains/live/domain/global_player_service.dart';
import 'package:pure_live/core/logging/app_log.dart';

class LiveRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  /// A route's path without its query (`/live_play?site=douyin` is the room
  /// page too).
  static String? _pathOf(Route<dynamic>? route) => route?.settings.name?.split('?').first;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    switch (_pathOf(route)) {
      case RoutePath.kLivePlay:
        _onLivePlayEnter();
        break;
      case RoutePath.kMultiview:
        _onMultiviewEnter();
      case RoutePath.kLocalVideoPlayer:
        _onLocalVideoPlayerEnter();
      case RoutePath.kRecordPage:
        _setVideoLayerVisible(false);
        break;
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    switch (_pathOf(route)) {
      case RoutePath.kLivePlay:
        _onLivePlayExit('pop');
        break;
      case RoutePath.kRecordPage:
        _restoreVideoLayerAfterRouteExit(route);
        break;
    }
  }

  // A room page can also leave without a pop: removed from under another
  // route, or replaced. Its player stops then too.
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (_pathOf(route) == RoutePath.kLivePlay) _onLivePlayExit('remove');
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (_pathOf(oldRoute) == RoutePath.kLivePlay && _pathOf(newRoute) != RoutePath.kLivePlay) {
      _onLivePlayExit('replace');
    }
  }

  void _onLivePlayEnter() {
    final playerManager = GlobalPlayerService.instance.player;
    playerManager.setVideoPresentationVisible(true);
    // A recording handed to the small window is taken back: two videos cannot
    // share the surface (or the audio). Reclaiming also closes the window
    // itself, not just the player behind it.
    unawaited(FloatingHandleKeeper.reclaimCurrent(PlayerKernelService.instance.kernel));
  }

  /// Watching a recording on its own page.
  ///
  /// A recording that was floating is taken back by the page that owns it —
  /// the window included, so the new page is not covered by a window whose
  /// player was just disposed.
  void _onLocalVideoPlayerEnter() {
    unawaited(FloatingHandleKeeper.reclaimCurrent(PlayerKernelService.instance.kernel));
  }

  void _onMultiviewEnter() {
    unawaited(GlobalPlayerService.instance.player.close());
    final controller = _findLivePlayController();
    if (controller == null) return;
    final state = controller.state.value;
    state.player.videoController?.clearListener();
  }

  void _onLivePlayExit(String how) {
    // First, whatever else is found: leaving a room stops its player. It used
    // to wait for the room's controller to be found, and a room whose
    // controller was already gone kept playing behind the home page.
    Log.i('route: room page left ($how)');
    unawaited(GlobalPlayerService.instance.player.close());
    final controller = _findLivePlayController();
    if (controller == null) return;

    final state = controller.state.value;

    controller.updateRoom(success: false);

    state.player.videoController?.clearListener();

    if (PlatformUtils.isMobile) {
      WindowService().doExitFullScreen();
    }
  }

  void _setVideoLayerVisible(bool visible) {
    final controller = _findLivePlayController();
    if (controller == null) return;
    // Windows removes the Texture subtree while this opaque route is visible.
    // Stop presentation-only stall supervision before that intentional
    // teardown so a long stay in recorder centre does not reopen a healthy
    // Huya transport in the background.
    GlobalPlayerService.instance.player.setVideoPresentationVisible(visible);
  }

  /// A popped route remains in the overlay during its reverse transition.
  /// Reattaching media_kit's Windows texture in didPop used to overlap that
  /// transition and produced a reproducible flutter_windows.dll access
  /// violation when returning from the recorder centre.  Wait for the route
  /// to be fully removed, then cross one more frame boundary before restoring
  /// the live surface.
  void _restoreVideoLayerAfterRouteExit(Route<dynamic> route) {
    unawaited(
      _waitForRouteExit(route).then((_) async {
        await SchedulerBinding.instance.endOfFrame;
        final controller = _findLivePlayController();
        if (controller != null && !controller.isClosed) {
          // Let the rebuilt Texture publish its viewport before presentation
          // supervision resumes. The first mounted layout force-reasserts the
          // Windows native size even when it equals the previous viewport.
          await SchedulerBinding.instance.endOfFrame;
          GlobalPlayerService.instance.player.setVideoPresentationVisible(true);
        }
      }),
    );
  }

  Future<void> _waitForRouteExit(Route<dynamic> route) {
    if (route is TransitionRoute<dynamic>) {
      return route.completed;
    }
    return SchedulerBinding.instance.endOfFrame;
  }

  LivePlayController? _findLivePlayController() {
    try {
      if (!Get.isRegistered<LivePlayController>()) return null;
      return Get.find<LivePlayController>();
    } catch (e, stackTrace) {
      Log.dev('Failed to find LivePlayController', error: e, stackTrace: stackTrace);
      return null;
    }
  }
}

