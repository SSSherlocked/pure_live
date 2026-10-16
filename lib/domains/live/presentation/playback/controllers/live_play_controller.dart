import 'dart:io';
import 'dart:async';

import 'package:pure_live/domains/live/domain/playback_startup_timing.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/domains/live/domain/live_audio_focus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:pure_live/core/config/live_panel_layout.dart';
import 'package:pure_live/core/config/theme_settings_controller.dart';
import 'package:pure_live/core/utils/event_bus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:pure_live/shared/platforms/emoji_manager.dart';
import 'package:pure_live/shared/platforms/live_site.dart' show LiveStreamFacts;
import 'package:pure_live/core/models/live_play_quality.dart';
import 'package:pure_live/core/player/core/playback_source.dart';
import 'package:pure_live/core/player/core/live_audio_service.dart';
import 'package:pure_live/core/player/core/background_playback_keeper.dart';
import 'package:pure_live/core/player/core/background_playback_service.dart';
import 'package:media_core/media_core.dart' show PlayerPlaybackState;
import 'package:pure_live/domains/live/presentation/playback/states/ui_state.dart';
import 'package:pure_live/domains/live/presentation/playback/states/player_state.dart';
import 'package:pure_live/core/stream/hls_source_query_policy.dart';
import 'package:pure_live/domains/live/presentation/playback/states/room_state.dart';
import 'package:pure_live/domains/live/presentation/playback/states/live_play_state.dart';
import 'package:pure_live/domains/recorder/presentation/pages/recorder/recorder_controller.dart';
import 'package:pure_live/domains/live/presentation/playback/controllers/timer_controller.dart';
import 'package:pure_live/domains/live/presentation/playback/services/room_external_opener.dart';
import 'package:pure_live/domains/live/presentation/playback/controllers/player_controller.dart';
import 'package:pure_live/core/config/app_settings_controller.dart';
import 'package:pure_live/domains/live/presentation/playback/controllers/danmaku_controller.dart';
import 'package:pure_live/domains/live/presentation/playback/controllers/danmaku_session_host.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/danmaku/danmaku_list_view.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/video_player/video_controller.dart';
import 'package:pure_live/domains/live/presentation/playback/controllers/danmaku_presentation_recovery.dart';
import 'package:pure_live/domains/live/data/platforms/sites.dart';
import 'package:pure_live/domains/live/domain/global_player_service.dart';
import 'package:pure_live/domains/live/data/favorite_room_controller.dart';
import 'package:pure_live/domains/live/data/history_controller.dart';
import 'package:pure_live/core/logging/app_log.dart';

// live_play_controller.dart

typedef IptvPlayerStarter = Future<bool> Function(LiveRoom liveroom);

enum IptvPlaybackSwitchResult { started, superseded, failed }

@visibleForTesting
String roomStateMessage(LiveRoom room) {
  return switch (room.effectiveRestriction) {
    LiveRestriction.needsLogin => i18n('restriction_needs_login'),
    LiveRestriction.paid => i18n('restriction_paid'),
    LiveRestriction.subscribersOnly => i18n('restriction_subscribers_only'),
    LiveRestriction.private => i18n('restriction_private'),
    LiveRestriction.appOnly => i18n('restriction_app_only'),
    LiveRestriction.regionBlocked => i18n('restriction_region_blocked'),
    LiveRestriction.password => i18n('restriction_password'),
    LiveRestriction.adult => i18n('restriction_adult'),
    LiveRestriction.unplayable => i18n('restriction_unplayable'),
    LiveRestriction.none =>
      room.effectiveLiveStatus == LiveStatus.banned ? i18n('server_error_retry_later') : i18n('stream_not_live'),
  };
}

@visibleForTesting
String unknownRoomStatusMessage(LiveRoom? room) =>
    room != null && room.isRestricted ? roomStateMessage(room) : i18n('get_room_info_failed_retry');

class LivePlayController extends GetxController
    with GetSingleTickerProviderStateMixin, WidgetsBindingObserver
    implements DanmakuSessionHost, PlayerSessionHost {
  LivePlayController({required this.room, required this.site}) : _iptvPlayerStarter = null;

  @visibleForTesting
  LivePlayController.withIptvPlayerStarter(this._iptvPlayerStarter, {required this.room, required this.site});

  final String site;
  final LiveRoom room;
  final IptvPlayerStarter? _iptvPlayerStarter;

  late final TimerController timerController;
  late final DanmakuController danmakuController;
  late final PlayerController playerController;

  final RecorderController recorderController = Get.find<RecorderController>();

  @override
  final Rx<LivePlayState> state = const LivePlayState().obs;
  final RxList<LiveMessage> danmakuMessages = <LiveMessage>[].obs;
  final _danmakuRemovals = StreamController<bool Function(LiveMessage)>.broadcast(sync: true);
  Stream<bool Function(LiveMessage)> get danmakuRemovals => _danmakuRemovals.stream;
  final RxInt danmakuPresentationRevision = 0.obs;
  final RxList<LiveSuperChatMessage> superChats = <LiveSuperChatMessage>[].obs;
  late Site currentSite;
  late TabController tabController;

  // Automatic reconnect after a dropped stream (a network-class failure, or
  // every line failing once the room has played): retried at 2/10/20/30/60 s
  // (the last repeats) for up to 30 minutes, and at once when the device
  // reports a network again (wzgrx/pure_live G02.3 / O01.3). Away from the
  // app it only runs while the room keeps its foreground service
  // ([BackgroundPlaybackKeeper.mayStartPlayback]).
  static const ReconnectSchedule _reconnectSchedule = ReconnectSchedule();
  Timer? _reconnectTimer;
  StreamSubscription<List<ConnectivityResult>>? _reconnectConnectivity;
  DateTime? _reconnectStartedAt;
  int _reconnectAttempt = 0;
  bool _reconnecting = false;

  /// An attempt came due away from the app while the room may not start by
  /// itself; it runs when the user is back.
  bool _reconnectDeferred = false;

  /// The current room played at least once since it was opened.
  bool _roomHasPlayed = false;

  /// Whether a failure that exhausted every line is a dropped stream to
  /// reconnect (the room played, or is already reconnecting) rather than a
  /// room that never opened.
  bool get reconnectsDroppedStream => _roomHasPlayed || _reconnectStartedAt != null;

  /// A dropped stream: keep trying until the room plays again.
  void onPlaybackNetworkError() {
    if (isClosed || _ownerClosed) return;
    final firstFailure = _reconnectStartedAt == null;
    _reconnectStartedAt ??= DateTime.now();
    if (firstFailure) ToastUtil.show(i18n('playback_auto_reconnect'));
    _reconnectConnectivity ??= Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        _scheduleReconnect(const Duration(seconds: 1));
      }
    });
    _scheduleReconnect(_reconnectSchedule.delayBefore(_reconnectAttempt));
    _syncBackgroundHold();
  }

  /// The room plays again: stop the reconnect ladder.
  void notifyPlaybackRecovered() {
    _roomHasPlayed = true;
    _stopReconnect();
  }

  void _scheduleReconnect(Duration delay) {
    if (isClosed || _ownerClosed || _reconnectStartedAt == null) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () => unawaited(_attemptReconnect()));
  }

  Future<void> _attemptReconnect() async {
    final startedAt = _reconnectStartedAt;
    if (isClosed || _ownerClosed || startedAt == null || _reconnecting) return;
    if (GlobalPlayerService.instance.player.isPlayingNow) {
      _stopReconnect();
      return;
    }
    if (!_backgroundKeeper.mayStartPlayback) {
      // Away from the app and nothing is kept: the room was not playing when
      // the app left, the user paused it, or the wait ran out. It must not
      // start there by itself (and Android would refuse its foreground
      // service); the user's return tries again (C01.5).
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _reconnectDeferred = true;
      return;
    }
    if (_reconnectSchedule.isExhausted(DateTime.now().difference(startedAt))) {
      _stopReconnect();
      return;
    }
    _reconnectAttempt++;
    _reconnecting = true;
    try {
      // A drop can be the end of the broadcast. Ask the platform first: an
      // offline room shows 未开播 and the ladder keeps checking, so a room
      // that comes back plays again on its own (the background keeper holds
      // the service for that wait).
      if (await _broadcastEnded()) return;
      final videoController = state.value.player.videoController;
      if (videoController != null) {
        await videoController.refresh();
      } else {
        await onInitPlayerState(reloadDataType: ReloadDataType.refresh);
      }
    } catch (_) {
      // A failed attempt is answered by the next step of the ladder.
    } finally {
      _reconnecting = false;
      if (!isClosed && !_ownerClosed && _reconnectStartedAt != null) {
        // Keep the ladder going even when a failed attempt raised no player
        // error (the room page itself did not load), and while the room is
        // offline.
        if (!GlobalPlayerService.instance.player.isPlayingNow) {
          _scheduleReconnect(_reconnectSchedule.delayBefore(_reconnectAttempt));
        }
      }
    }
  }

  /// Whether the broadcast is over, asked of the platform during a reconnect.
  /// An offline answer marks the room offline (the picture says 未开播) and
  /// skips this attempt's reload; a live one clears an earlier offline mark
  /// so the reload plays it. Unknown or failed answers change nothing.
  /// Whether [now] plays, for a room that was [before]. A broadcast that
  /// ended is 已下播 even when the platform has a replay or a carousel
  /// running in its place: that is not switched to. A room opened as a
  /// replay (录播) still plays it.
  static bool _playableAfter(LiveRoom before, LiveRoom now) =>
      now.isLiveNow || (now.isPlayableNow && !before.isLiveNow);

  Future<bool> _broadcastEnded() async {
    final current = state.value.room.detail;
    if (current == null || currentSite.id == Sites.iptvSite) return false;
    try {
      final fetched = await currentSite.liveSite.getRoomDetail(current);
      if (isClosed || _ownerClosed || fetched.isLiveStatusPending) return false;
      final refreshed = fetched.withAudienceFallbackFrom(current);
      final live = _playableAfter(current, refreshed);
      if (live == state.value.room.isLiving) return !live;
      updateRoom(liveroom: refreshed, isLiving: live);
      unawaited(live ? _syncDanmakuConnection(refreshed) : danmakuController.stopDanmaku());
      _syncBackgroundHold();
      return !live;
    } catch (_) {
      return false;
    }
  }

  /// The user is back: a ladder that waited for them starts afresh, now.
  void _resumeDeferredReconnect() {
    if (!_reconnectDeferred || isClosed || _ownerClosed) return;
    _reconnectDeferred = false;
    if (_reconnectStartedAt == null) return;
    _reconnectStartedAt = DateTime.now();
    _reconnectAttempt = 0;
    _scheduleReconnect(Duration.zero);
  }

  // A stream that stops moving without an error is refreshed (as Simple Live
  // does): at most 3 times in a row and 5 s apart. A long stall reported well
  // after the last refresh (the 10 s stall plus 30 s of play) starts a fresh
  // count. The reconnect ladder, when running, owns recovery instead.
  static const int _maxStallRefreshes = 3;
  static const Duration _stallRefreshCooldown = Duration(seconds: 5);
  static const Duration _stallRefreshResetAfter = Duration(seconds: 40);
  StreamSubscription<Duration>? _longStallSub;
  int _stallRefreshes = 0;
  DateTime? _lastStallRefreshAt;

  void _onLongStall(Duration still) {
    if (isClosed || _ownerClosed || _reconnectStartedAt != null || _reconnecting) return;
    final videoController = state.value.player.videoController;
    final player = GlobalPlayerService.instance.player;
    if (videoController == null || !player.ownsVideoController(videoController)) return;
    final now = DateTime.now();
    final last = _lastStallRefreshAt;
    if (last != null && now.difference(last) > _stallRefreshResetAfter) _stallRefreshes = 0;
    if (_stallRefreshes >= _maxStallRefreshes) return;
    if (last != null && now.difference(last) < _stallRefreshCooldown) return;
    _stallRefreshes++;
    _lastStallRefreshAt = now;
    Log.w('Playback stalled for ${still.inSeconds} s; refreshing ($_stallRefreshes/$_maxStallRefreshes)');
    unawaited(videoController.refresh());
  }

  void _stopReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    unawaited(_reconnectConnectivity?.cancel());
    _reconnectConnectivity = null;
    _reconnectStartedAt = null;
    _reconnectAttempt = 0;
    _reconnectDeferred = false;
    _syncBackgroundHold();
  }

  // Background play (wzgrx/pure_live O01.3 / C01.5, Android): away from the
  // app the keeper decides whether the room keeps the media notification's
  // foreground service and the CPU/Wi-Fi locks, and whether it may start
  // playing by itself (see BackgroundPlaybackKeeper).
  late final BackgroundPlaybackKeeper _backgroundKeeper = BackgroundPlaybackKeeper(onChanged: _applyBackgroundHold);
  late final void Function() _remotePauseListener = _onRemotePause;
  StreamSubscription<Object?>? _playerPhaseSub;
  BackgroundPlayerPhase _playerPhase = BackgroundPlayerPhase.idle;
  BackgroundKeeperInput? _lastKeeperInput;
  Worker? _roomStateHoldWorker;

  static BackgroundPlayerPhase _phaseOf(PlayerPlaybackState playback) => switch (playback) {
    PlayerPlaybackState.playing => BackgroundPlayerPhase.playing,
    PlayerPlaybackState.opening ||
    PlayerPlaybackState.buffering ||
    PlayerPlaybackState.seeking => BackgroundPlayerPhase.starting,
    PlayerPlaybackState.paused => BackgroundPlayerPhase.paused,
    PlayerPlaybackState.error => BackgroundPlayerPhase.failed,
    PlayerPlaybackState.idle ||
    PlayerPlaybackState.stopping ||
    PlayerPlaybackState.stopped ||
    PlayerPlaybackState.completed => BackgroundPlayerPhase.idle,
  };

  /// Out of sight (not picture-in-picture) with background play or a sleep
  /// session on. Android only: that is where the foreground service lives.
  bool get _isAwayForBackgroundPlay =>
      Platform.isAndroid &&
      _wasBackgrounded &&
      !GlobalPlayerService.instance.player.isInPip.value &&
      LiveAudioService.shouldContinueInBackground;

  void _syncBackgroundHold() {
    if (isClosed || _ownerClosed) return;
    final input = BackgroundKeeperInput(
      away: _isAwayForBackgroundPlay,
      phase: _playerPhase,
      reconnecting: _reconnectStartedAt != null,
      roomOffline: !state.value.room.isLiving,
      interrupted: LiveAudioFocus.instance.pausedByInterruption.value,
    );
    if (input == _lastKeeperInput) return;
    _lastKeeperInput = input;
    _backgroundKeeper.update(input);
    _applyBackgroundHold();
  }

  void _applyBackgroundHold() {
    if (isClosed || _ownerClosed) return;
    unawaited(BackgroundPlaybackService.setForegroundHold(_backgroundKeeper.hold != BackgroundHold.none));
  }

  /// The notification, the lock screen or a headset button paused or
  /// stopped the room: a call's planned resume is dropped too.
  void _onRemotePause() {
    if (isClosed || _ownerClosed) return;
    LiveAudioFocus.instance.forgetResume();
    _pausedByPipClose = false;
    _markUserPause();
  }

  /// The user's pause (also headphones unplugged, the room or sleep timer): nothing is
  /// kept or started away from the app until the room plays again.
  void _markUserPause() {
    if (isClosed || _ownerClosed) return;
    _backgroundKeeper.markUserPause();
    _applyBackgroundHold();
  }

  /// Keeps the room's fullscreen state in step with the desktop window.
  late final _NativeFullscreenSync _nativeFullscreenSync = _NativeFullscreenSync(this);

  /// Side panel sections the user keeps, in their order, fixed for this room
  /// session.
  late final List<LivePanelTab> panelTabs = Get.isRegistered<ThemeSettingsController>()
      ? SettingsService.to.theme.visibleLivePanelTabs
      : LivePanelTab.defaultOrder;

  /// The side panel's tab labels. 留言 carries the room's super chat count,
  /// 留言(3); with none it is plain 留言. Reads [superChats], so an [Obx]
  /// building the tab bar follows the count.
  List<String> get tabs {
    final superChatCount = superChats.length;
    return [
      for (final tab in panelTabs)
        tab == LivePanelTab.superChat && superChatCount > 0
            ? '${i18n(tab.shortLabelKey)}($superChatCount)'
            : i18n(tab.shortLabelKey),
    ];
  }

  /// Brings [tab] of the side panel to the front. False when the room has no
  /// side panel (IPTV) or no such section, so the caller can fall back.
  bool showPanelTab(LivePanelTab tab) {
    if (site == Sites.iptvSite) return false;
    final index = panelTabs.indexOf(tab);
    if (index < 0) return false;
    tabController.animateTo(index);
    return true;
  }

  bool _ownerClosed = false;
  bool _externalOpenInFlight = false;
  bool _childControllersReleased = false;
  bool _reactiveStateClosed = false;
  int _roomLoadEpoch = 0;
  int _iptvPlaybackEpoch = 0;
  bool _asmrSessionActive = false;
  Timer? _danmakuFlushTimer;
  Worker? _pipStateWorker;
  Worker? _screenKeepOnWorker;
  Worker? _superChatPinnedWorker;
  late final DanmakuPresentationRecovery _danmakuPresentationRecovery;
  bool _wasInSystemPip = false;
  bool _wasBackgrounded = false;
  bool _handlingSystemBackPresentation = false;
  final List<LiveMessage> _pendingDanmakuMessages = <LiveMessage>[];
  late final String _controllerTag;

  static const int _maxDanmakuHistory = 500;
  static const int _maxPendingDanmakuBatch = 200;
  // The on-video barrage receives messages directly from DanmakuController.
  // This buffer only feeds the virtualized history list, whose own visual
  // cadence is 80 ms. A 64 ms batch halves full 500-item RxList copies in busy
  // rooms without slowing the moving barrage or local messages (which flush
  // immediately).
  static const Duration _danmakuBatchWindow = Duration(milliseconds: 64);

  Timer? _superChatExpiryTimer;
  @override
  void onInit() {
    super.onInit();
    _nativeFullscreenSync.attach();
    unawaited(LiveAudioFocus.instance.attach());
    _controllerTag = '${identityHashCode(this)}';
    currentSite = Sites.of(site);

    final manager = GlobalPlayerService.instance.player;
    _longStallSub = manager.onLongStall.listen(_onLongStall);
    _playerPhase = manager.isPlayingNow ? BackgroundPlayerPhase.playing : BackgroundPlayerPhase.idle;
    _playerPhaseSub = manager.onStateChanged.listen((coreState) {
      final phase = _phaseOf(coreState.playback);
      if (phase == _playerPhase) return;
      _playerPhase = phase;
      if (phase == BackgroundPlayerPhase.playing) {
        // Playing again (the user, the notification, a reconnect): a pause
        // planned to be undone later - for a closed picture-in-picture window
        // or a call - is over, and must not resume a later pause of the user.
        _pausedByPipClose = false;
        LiveAudioFocus.instance.forgetResume();
      }
      _syncBackgroundHold();
    });
    LiveAudioFocus.instance.pausedByInterruption.addListener(_syncBackgroundHold);
    LiveAudioFocus.instance.onNoisyPause = _markUserPause;
    LiveAudioService.onSleepTimerPause = _markUserPause;
    BackgroundPlaybackService.setRemotePauseListener(_remotePauseListener);
    final autoStartAsmr = Platform.isAndroid && SettingsService.to.app.enableAsmrSleepMode.v;
    _asmrSessionActive = autoStartAsmr;
    state.value = LivePlayState(
      room: RoomState(detail: room, isLiving: true, success: false),
      // ASMR is the only automatic audio-only entry point. Manual headphone
      // switching is scoped to the current room and is never persisted.
      player: PlayerState(
        qualites: const <LivePlayQuality>[],
        currentQuality: 0,
        playUrls: const <String>[],
        sourceQueryPolicies: const {},
        streamFacts: const {},
        currentLineIndex: 0,
        isCurrentRoomAudioOnly: autoStartAsmr,
        hasUseDefaultResolution: false,
      ),
      ui: UIState(closeTimes: 60, closeTimeFlag: false),
    );
    unawaited(
      LiveAudioService.configureSleepTimer(enabled: autoStartAsmr, minutes: SettingsService.to.app.asmrSleepMinutes.v),
    );

    _initControllers();
    _danmakuPresentationRecovery = DanmakuPresentationRecovery(
      isBlocked: () => GlobalPlayerService.instance.player.isCompactModeActive,
      canRecover: () {
        if (isClosed || _ownerClosed) return false;
        return state.value.room.success && state.value.room.detail != null;
      },
      recover: _recoverDanmakuAfterPresentation,
    );
    WidgetsBinding.instance.addObserver(this);
    _wasInSystemPip = manager.isInPip.value;
    _pipStateWorker = ever<bool>(manager.isInPip, (isInPip) {
      final returnedFromPip = _wasInSystemPip && !isInPip;
      _wasInSystemPip = isInPip;
      if (returnedFromPip) _restoreDanmakuPresentation();
      _syncBackgroundHold();
      if (isInPip) {
        _pipJustClosed = false;
      } else if (returnedFromPip) {
        _onPipWindowGone();
      }
    });
    // Whether the room is on air is part of what the background keeper reads.
    _roomStateHoldWorker = ever<LivePlayState>(state, (_) => _syncBackgroundHold());
    _initTab();
    Future.microtask(_initCore);

    // This observable is owned by the application-wide SettingsService. Keep
    // and dispose its Worker explicitly; otherwise every closed room remains
    // reachable through the global Rx callback together with its 500-message
    // history, player controller and render caches.
    _screenKeepOnWorker = ever(SettingsService.to.app.enableScreenKeepOn, (_) => _updateWakelock());
    // 留言板常驻 off again: the super chats whose countdown has ended go now.
    _superChatPinnedWorker = ever(SettingsService.to.danmaku.superChatPinned, (_) => _removeExpiredSuperChats());

    _updateWakelock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden || state == AppLifecycleState.detached) {
      final leaving = !_wasBackgrounded;
      _wasBackgrounded = true;
      _syncBackgroundHold();
      if (leaving) _onLeftApp();
      return;
    }
    // The picture-in-picture window was expanded back into the app.
    if (state == AppLifecycleState.resumed) _pipJustClosed = false;
    if (state != AppLifecycleState.resumed || !_wasBackgrounded) return;
    _wasBackgrounded = false;
    _syncBackgroundHold();
    _restoreAwaySwitches();
    _resumeDeferredReconnect();
    if (!GlobalPlayerService.instance.player.isInPip.value) {
      _restoreDanmakuPresentation();
    }
  }

  // Away from the app (Android, wzgrx/pure_live O01.3): "后台只播声音" stops
  // decoding the picture and "后台断开弹幕" closes the danmaku connection
  // once the app stayed away [_awaySwitchDelay] without a picture-in-picture
  // window; coming back undoes both. "关闭画中画时暂停" pauses a room whose
  // picture-in-picture window was closed, and resumes it on return.
  static const Duration _awaySwitchDelay = Duration(milliseconds: 1500);
  Timer? _awaySwitchTimer;
  bool _videoOffByUs = false;
  bool _danmakuOffByUs = false;
  bool _pausedByPipClose = false;

  /// The picture-in-picture window went while the app was not yet stopped:
  /// it was closed if the app stops next, expanded if it resumes.
  bool _pipJustClosed = false;

  void _onLeftApp() {
    if (_pipJustClosed) {
      _pipJustClosed = false;
      _onPipClosed();
    }
    _scheduleAwaySwitches();
  }

  void _onPipWindowGone() {
    if (!_wasBackgrounded) {
      // Already back in front: the window was expanded into the app (its
      // resume arrived first), not closed.
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) return;
      _pipJustClosed = true;
      return;
    }
    // The app stopped first, then the window went: it was closed.
    _onPipClosed();
    _scheduleAwaySwitches();
  }

  void _onPipClosed() {
    if (!Platform.isAndroid || isClosed || _ownerClosed || !SettingsService.to.app.pauseOnPipClose.v) return;
    final player = GlobalPlayerService.instance.player;
    if (!player.isPlayingNow) return;
    _pausedByPipClose = true;
    _markUserPause();
    unawaited(player.pause());
  }

  void _scheduleAwaySwitches() {
    if (!Platform.isAndroid) return;
    _awaySwitchTimer?.cancel();
    _awaySwitchTimer = Timer(_awaySwitchDelay, _applyAwaySwitches);
  }

  void _applyAwaySwitches() {
    _awaySwitchTimer = null;
    if (isClosed || _ownerClosed || !_wasBackgrounded) return;
    final player = GlobalPlayerService.instance.player;
    if (player.isInPip.value) return;
    final app = SettingsService.to.app;
    if (!_danmakuOffByUs && app.backgroundPauseDanmaku.v) {
      _danmakuOffByUs = true;
      unawaited(danmakuController.suspendConnections());
    }
    // The user's own audio-only choice is theirs to undo: only a room that
    // shows its picture is switched, and only that one is switched back.
    if (!_videoOffByUs && app.backgroundAudioOnly.v && !player.desiredAudioOnlyMode) {
      _videoOffByUs = true;
      unawaited(player.setAudioOnly(true));
    }
  }

  void _restoreAwaySwitches() {
    _awaySwitchTimer?.cancel();
    _awaySwitchTimer = null;
    if (isClosed || _ownerClosed) return;
    final player = GlobalPlayerService.instance.player;
    if (_videoOffByUs) {
      _videoOffByUs = false;
      if (!player.desiredAudioOnlyMode) unawaited(player.setAudioOnly(false));
    }
    if (_danmakuOffByUs) {
      _danmakuOffByUs = false;
      danmakuController.resumeConnections();
      unawaited(_recoverDanmakuAfterPresentation());
    }
    if (_pausedByPipClose) {
      _pausedByPipClose = false;
      if (!player.isPlayingNow) unawaited(player.resume());
    }
  }

  void _restoreDanmakuPresentation() {
    if (isClosed || _ownerClosed) return;
    // The portrait list is removed from the tree while LivePlayContent renders
    // the native PiP surface, so a list-local PiP worker never observes the
    // complete true -> false transition. Publish the restore from this
    // persistent controller and flush any batch that was waiting when the
    // Activity changed presentation.
    _flushDanmakuMessages();
    danmakuPresentationRevision.value++;
    _danmakuPresentationRecovery.request();
  }

  Future<void> _recoverDanmakuAfterPresentation() async {
    final detail = state.value.room.detail;
    if (detail == null || !state.value.room.success || isClosed || _ownerClosed) return;
    try {
      await danmakuController.recoverRoomConnection(detail);
    } catch (error, stackTrace) {
      Log.dev(
        'Danmaku recovery after PiP/foreground failed',
        name: 'LivePlayController',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _initControllers() {
    timerController = Get.put(TimerController(onEnded: _onRoomPlaybackTimerEnded), tag: 'timer-$_controllerTag');
    danmakuController = Get.put(DanmakuController(this), tag: 'danmaku-$_controllerTag');
    playerController = Get.put(PlayerController(this), tag: 'player-$_controllerTag');

    playerController.initSite(currentSite);

    danmakuController.initDanmaku(currentSite.liveSite.getDanmaku());
  }

  void _initTab() {
    tabController = TabController(length: tabs.length, vsync: this, animationDuration: pureLiveTabTransitionDuration);
  }

  Future<void> _initCore() async {
    // Emoji resources are presentation data. Keeping their disk/network work
    // off the playback critical path makes a cold room start as soon as its
    // detail and play URL are available.
    _preloadEmojiInBackground();
    await onInitPlayerState();
  }

  Future<void> _updateWakelock() async {
    final shouldKeepOn = SettingsService.to.app.enableScreenKeepOn.v;

    WakelockPlus.enabled.then((isEnabled) {
      if (isEnabled != shouldKeepOn) {
        WakelockPlus.toggle(enable: shouldKeepOn);
      }
    });
  }

  void _preloadEmojiInBackground() {
    unawaited(
      _preloadEmoji().catchError((Object error, StackTrace stackTrace) {
        Log.dev('Emoji preload failed', name: 'LivePlayController', error: error, stackTrace: stackTrace);
      }),
    );
  }

  Future<void> _preloadEmoji() async {
    emojiCache.clear();
    await EmojiManager().preload(
      site,
      Sites.danmakuCapability(site)?.parseDanmakuEmoji,
      onAtlasChanged: emojiCache.clear,
    );
  }

  Future<void> getSuperChatMessage(LiveRoom liveroom, {required int loadEpoch}) async {
    if (!_isRoomLoadCurrent(loadEpoch, liveroom)) return;
    final liveSite = currentSite.liveSite;
    try {
      final sc = await liveSite.getSuperChatMessage(liveroom: liveroom);
      if (isClosed || _ownerClosed || !_isRoomLoadCurrent(loadEpoch, liveroom)) return;
      addBatchSuperChat(sc);
    } catch (e) {
      if (!isClosed && !_ownerClosed && _isRoomLoadCurrent(loadEpoch, liveroom)) {
        addSystemMessage(i18n('live_sc_read_failed'));
      }
    }
  }

  /// How many copies each chat line stands for (see [countDanmakuRepeat]).
  /// Held beside the message rather than on it, and weakly, so a line that
  /// leaves the history takes its count with it.
  final Expando<RxInt> _danmakuRepeats = Expando<RxInt>('danmakuRepeats');

  /// Observable copy count of a chat line: 1 until repeats are folded into it.
  RxInt danmakuRepeatsOf(LiveMessage message) => _danmakuRepeats[message] ??= RxInt(1);

  @override
  void countDanmakuRepeat(LiveMessage shown) {
    if (isClosed) return;
    danmakuRepeatsOf(shown).value++;
  }

  @override
  void addAddSuperChat(LiveMessage msg) {
    addSingleSuperChat(msg.data as LiveSuperChatMessage);
  }

  void _removeExpiredSuperChats() {
    if (isClosed || _ownerClosed) return;
    // 留言板常驻: nothing leaves the list before the room closes.
    if (SettingsService.to.danmaku.superChatPinned.v) {
      _superChatExpiryTimer?.cancel();
      _superChatExpiryTimer = null;
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final filtered = superChats.where((x) => x.endTime.millisecondsSinceEpoch > now).toList(growable: false);
    if (filtered.length != superChats.length) {
      superChats.assignAll(filtered);
    }
    _scheduleSuperChatExpiry();
  }

  void _scheduleSuperChatExpiry() {
    _superChatExpiryTimer?.cancel();
    _superChatExpiryTimer = null;
    if (isClosed || _ownerClosed || SettingsService.to.danmaku.superChatPinned.v) return;
    final delay = nextSuperChatExpiryDelay(superChats, DateTime.now());
    if (delay == null) return;
    _superChatExpiryTimer = Timer(delay, _removeExpiredSuperChats);
  }

  @visibleForTesting
  static Duration? nextSuperChatExpiryDelay(Iterable<LiveSuperChatMessage> messages, DateTime now) {
    final iterator = messages.iterator;
    if (!iterator.moveNext()) return null;
    var nextExpiry = iterator.current.endTime;
    while (iterator.moveNext()) {
      final candidate = iterator.current.endTime;
      if (candidate.isBefore(nextExpiry)) nextExpiry = candidate;
    }
    final remaining = nextExpiry.difference(now);
    return remaining.isNegative || remaining == Duration.zero ? const Duration(milliseconds: 1) : remaining;
  }

  void addSingleSuperChat(LiveSuperChatMessage item) {
    if (isClosed || _ownerClosed) return;
    final next = <LiveSuperChatMessage>{...superChats, item}.toList(growable: false);
    superChats.assignAll(next);
    _scheduleSuperChatExpiry();
  }

  void addBatchSuperChat(List<LiveSuperChatMessage> sc) {
    if (sc.isEmpty || isClosed || _ownerClosed) return;
    final next = <LiveSuperChatMessage>{...superChats, ...sc}.toList(growable: false);
    superChats.assignAll(next);
    _scheduleSuperChatExpiry();
  }

  void clearSuperChats() {
    _superChatExpiryTimer?.cancel();
    _superChatExpiryTimer = null;
    if (superChats.isNotEmpty) superChats.clear();
  }

  /// A metadata retry on the same room is not a new paid-message session.
  /// Keep already delivered messages until they expire or the room changes.
  @visibleForTesting
  void beginRoomMetadataLoad() => updateRoom(isLoading: true, loadError: null);

  /// Restores the normal room presentation for one system-back attempt.
  ///
  /// The route-local PopScope owns whether the route can pop. Keeping teardown
  /// out of this pre-pop path prevents a failed gesture from leaving the room
  /// visible after its player listeners have already been removed.
  Future<void> exitPresentationForSystemBack() async {
    if (_handlingSystemBackPresentation || isClosed || _ownerClosed) return;
    _handlingSystemBackPresentation = true;

    final player = GlobalPlayerService.instance.player;
    final mode = state.value.ui.screenMode;
    final wasFullscreen = player.isSystemFullscreen.value || requiresSystemFullscreenExit(mode);
    try {
      setNormalScreen();
      player.isWindowFullscreen.value = false;

      if (wasFullscreen) {
        final videoController = state.value.player.videoController;
        if (videoController != null) {
          await videoController.exitFullScreen();
        } else {
          player.isSystemFullscreen.value = false;
        }
      } else {
        player.isSystemFullscreen.value = false;
      }
    } finally {
      player.isSystemFullscreen.value = false;
      player.isWindowFullscreen.value = false;
      _handlingSystemBackPresentation = false;
    }
  }

  Future<void> enterPipPresentation() async {
    final player = GlobalPlayerService.instance.player;
    if (player.isSystemFullscreen.value ||
        player.isWindowFullscreen.value ||
        state.value.ui.screenMode != VideoMode.normal) {
      await exitPresentationForSystemBack();
    }
    await player.enablePip();
  }

  @override
  void updateRoom({LiveRoom? liveroom, bool? isLiving, bool? success, bool? isLoading, String? loadError}) {
    state.value = state.value.copyWith(
      room: state.value.room.copyWith(
        detail: liveroom,
        isLiving: isLiving,
        success: success,
        isLoading: isLoading,
        loadError: loadError,
      ),
    );
  }

  @override
  void updatePlayer({
    VideoController? videoController,
    bool clearVideoController = false,
    List<LivePlayQuality>? qualites,
    int? currentQuality,
    List<String>? playUrls,
    Map<String, HlsSourceQueryPolicy>? sourceQueryPolicies,
    Map<String, LiveStreamFacts>? streamFacts,
    OwnedPlaybackSource? ownedSource,
    bool clearOwnedSource = false,
    int? currentLineIndex,
    bool? isCurrentRoomAudioOnly,
    bool? hasUseDefaultResolution,
  }) {
    state.value = state.value.copyWith(
      player: state.value.player.copyWith(
        // Nullable optional parameters cannot distinguish "not supplied" from
        // "clear this field". Passing the default null on every unrelated
        // player-state update used to remove the live VideoController; toggling
        // audio mode therefore replaced the room with a permanent loading page.
        videoController: resolveVideoControllerUpdate(
          current: state.value.player.videoController,
          next: videoController,
          clear: clearVideoController,
        ),
        qualites: qualites,
        currentQuality: currentQuality,
        playUrls: playUrls,
        sourceQueryPolicies: sourceQueryPolicies,
        streamFacts: streamFacts,
        ownedSource: ownedSource,
        clearOwnedSource: clearOwnedSource,
        currentLineIndex: currentLineIndex,
        isCurrentRoomAudioOnly: isCurrentRoomAudioOnly,
        hasUseDefaultResolution: hasUseDefaultResolution,
      ),
    );
  }

  void updateUI({VideoMode? screenMode, int? refreshKey, bool? isMenuOpen, int? closeTimes, bool? closeTimeFlag}) {
    state.value = state.value.copyWith(
      ui: state.value.ui.copyWith(
        screenMode: screenMode,
        refreshKey: refreshKey,
        isMenuOpen: isMenuOpen,
        closeTimes: closeTimes,
        closeTimeFlag: closeTimeFlag,
      ),
    );
  }

  void updateDanmaku({List<LiveMessage>? messages}) {
    if (messages != null) {
      danmakuMessages.assignAll(messages);
    }
  }

  @override
  void addDanmakuMessage(LiveMessage msg, {bool immediate = false}) {
    if (isClosed) return;
    if (_pendingDanmakuMessages.length >= _maxPendingDanmakuBatch) {
      _pendingDanmakuMessages.removeAt(0);
    }
    _pendingDanmakuMessages.add(msg);
    if (immediate) {
      _danmakuFlushTimer?.cancel();
      _danmakuFlushTimer = null;
      _flushDanmakuMessages();
      return;
    }
    _danmakuFlushTimer ??= Timer(_danmakuBatchWindow, _flushDanmakuMessages);
  }

  void _flushDanmakuMessages() {
    _danmakuFlushTimer?.cancel();
    _danmakuFlushTimer = null;
    if (_pendingDanmakuMessages.isEmpty || isClosed) return;
    final next = <LiveMessage>[...danmakuMessages, ..._pendingDanmakuMessages];
    _pendingDanmakuMessages.clear();
    if (next.length > _maxDanmakuHistory) {
      next.removeRange(0, next.length - _maxDanmakuHistory);
    }
    danmakuMessages.assignAll(next);
  }

  void removeDanmakuWhere(bool Function(LiveMessage message) predicate) {
    if (!_danmakuRemovals.isClosed) _danmakuRemovals.add(predicate);
    _pendingDanmakuMessages.removeWhere(predicate);
    final next = danmakuMessages.where((message) => !predicate(message)).toList(growable: false);
    if (next.length != danmakuMessages.length) danmakuMessages.assignAll(next);
  }

  @override
  void removeRetractedMessages(LiveRetraction target) {
    if (isClosed) return;
    removeDanmakuWhere(
      (message) => target.matches(userId: message.userId, userName: message.userName, messageId: message.messageId),
    );
    if (target.all) {
      clearRenderedDanmaku();
    } else {
      state.value.player.videoController?.retractDanmaku(
        (message) => target.matches(userId: message.userId, userName: message.userName, messageId: message.messageId),
      );
    }
  }

  Future<void> _onRoomPlaybackTimerEnded() async {
    _markUserPause();
    updateUI(closeTimeFlag: false);
    await GlobalPlayerService.instance.player.pause();
    await LiveAudioService.stop();
    ToastUtil.show(i18n('room_playback_timer_finished'));
  }

  @override
  void updateRuntimeAudience(dynamic value) {
    if (isClosed) return;
    final update = value is LiveAudienceUpdate ? value : null;
    final rawValue = (update?.value ?? value)?.toString().trim() ?? '';
    if (!RegExp(r'[0-9]').hasMatch(rawValue)) return;
    final count = LiveRoom.parseAudienceNumber(rawValue);
    final detail = state.value.room.detail;
    if (detail == null) return;
    if (count < 0) return;
    final text = count.toString();
    final inferredKind = detail.platform == Sites.bilibiliSite
        ? LiveAudienceMetricKind.popularity
        : LiveAudienceMetricKind.onlineViewers;
    final kind = update?.kind ?? inferredKind;
    final candidate = switch (kind) {
      LiveAudienceMetricKind.popularity => detail.copyWith(
        watching: text,
        popularity: text,
        audienceMetricType: AudienceMetricType.popularity,
      ),
      LiveAudienceMetricKind.onlineViewers => detail.copyWith(onlineViewers: text),
      LiveAudienceMetricKind.totalViewers => detail.copyWith(totalViewers: text),
    };
    updateRoom(liveroom: candidate.withAudienceFallbackFrom(detail));
  }

  /// Applies the headphone action to this room only. Restoring video also
  /// ends an automatically started ASMR timer, while manually entering audio
  /// mode does not implicitly create a sleep session.
  @override
  Future<void> setCurrentRoomAudioOnlyFromUser(bool value) async {
    if (!value && _asmrSessionActive) {
      _asmrSessionActive = false;
      // Stopping the sleep timer updates its in-memory state synchronously, but
      // the Android keep-alive channel may answer slowly on a busy vendor ROM.
      // Keep that platform cleanup out of the native video-track transition so
      // restoring video never waits behind the foreground service.
      unawaited(
        LiveAudioService.configureSleepTimer(
          enabled: false,
          minutes: SettingsService.to.app.asmrSleepMinutes.v,
        ).catchError((Object error, StackTrace stackTrace) {
          Log.dev(
            'Sleep timer cleanup failed during video restore',
            name: 'LivePlayController',
            error: error,
            stackTrace: stackTrace,
          );
        }),
      );
    }
    await playerController.changeCurrentRoomAudioOnly(value);
  }

  @override
  void addSystemMessage(String text) {
    final msg = LiveMessage(
      type: LiveMessageType.chat,
      userName: i18n('system_message'),
      message: text,
      color: LiveMessageColor.white,
    );
    addDanmakuMessage(msg);
  }

  void clearDanmakuMessages() {
    _danmakuFlushTimer?.cancel();
    _danmakuFlushTimer = null;
    _pendingDanmakuMessages.clear();
    danmakuMessages.clear();
    clearRenderedDanmaku();
  }

  @override
  void updateDanmakuRoomId(String? roomId) {
    if (state.value.danmaku.currentDanmakuRoomId == roomId) return;
    state.value = state.value.copyWith(danmaku: state.value.danmaku.copyWith(currentDanmakuRoomId: roomId));
  }

  @override
  void clearRenderedDanmaku() {
    state.value.player.videoController?.clearDanmaku();
  }

  void updateTimerFlag(bool flag) {
    updateUI(closeTimeFlag: flag);
    timerController.toggleTimer(flag, state.value.ui.closeTimes);
  }

  void updateTimerTimes(int times) {
    updateUI(closeTimes: times);
    if (state.value.ui.closeTimeFlag) {
      timerController.toggleTimer(true, times);
    }
  }

  /// Commits the timer editor draft as one state/timer transaction.
  ///
  /// Applying duration and enabled state through the two legacy setters can
  /// restart an existing timer twice, while changing the switch inside a
  /// dialog used to mutate the live session even when the user cancelled.
  void applyRoomPlaybackTimer({required bool enabled, required int minutes}) {
    final normalizedMinutes = minutes.clamp(1, AppSettingsController.maxSleepMinutes).toInt();
    updateUI(closeTimes: normalizedMinutes, closeTimeFlag: enabled);
    timerController.toggleTimer(enabled, normalizedMinutes);
  }

  Future<LiveRoom> onInitPlayerState({
    ReloadDataType reloadDataType = ReloadDataType.refresh,
    int line = 0,
    bool isReCalculate = true,
  }) async {
    // Keep one immutable request snapshot. Reading state again after the
    // platform request completes can merge an old response with a newly opened
    // room before the epoch fence has a chance to reject it.
    final requestedRoom = state.value.room.detail;
    final roomId = requestedRoom?.roomId;
    final requestedPlatform = requestedRoom?.platform;
    if (requestedRoom == null || roomId == null || requestedPlatform == null) return LiveRoom();
    final loadEpoch = ++_roomLoadEpoch;

    beginRoomMetadataLoad();
    PlaybackStartupTiming.instance.begin(site: requestedPlatform, roomId: roomId);

    try {
      final fetchedRoom = await currentSite.liveSite.getRoomDetail(requestedRoom);
      PlaybackStartupTiming.instance.mark('detail');

      var liveRoom = fetchedRoom.withAudienceFallbackFrom(requestedRoom);
      liveRoom = liveRoom.fillFromDetail(requestedRoom);
      if (!_isRoomLoadCurrent(loadEpoch, liveRoom)) return liveRoom;
      updateRoom(liveroom: liveRoom);

      if (currentSite.id == Sites.iptvSite) {
        await _initIptvPlayer(liveRoom, loadEpoch: loadEpoch);
        return liveRoom;
      }

      _handleCurrentLineAndQuality(reloadDataType, line, isReCalculate);

      if (liveRoom.isLiveStatusPending) {
        _handleUnknownStatus();
        return liveRoom;
      }

      final liveStatus = _playableAfter(requestedRoom, liveRoom);

      if (liveStatus) {
        unawaited(getSuperChatMessage(liveRoom, loadEpoch: loadEpoch));
        await _handleLiveRoom(liveRoom, loadEpoch: loadEpoch);
      } else {
        await _handleNotLiveRoom(liveRoom);
      }

      updateRoom(isLoading: false);
      return liveRoom;
    } catch (e) {
      if (!_isRoomLoadCurrent(loadEpoch, requestedRoom)) return LiveRoom();
      Log.dev('Room load failed: $e', name: 'LivePlayController');
      updateRoom(isLoading: false, loadError: e.toString());
      ToastUtil.show(i18n('get_room_info_failed_retry'));
      return LiveRoom();
    }
  }

  bool _isRoomLoadCurrent(int epoch, LiveRoom liveroom) {
    final roomId = liveroom.roomId ?? '';
    final platform = liveroom.platform ?? '';
    final current = state.value.room.detail;
    return epoch == _roomLoadEpoch && current?.roomId == roomId && current?.platform == platform;
  }

  void invalidateRoomLoad() => _roomLoadEpoch++;

  Future<void> _handleLiveRoom(LiveRoom liveRoom, {required int loadEpoch}) async {
    updateRoom(isLiving: true, success: false);

    try {
      await playerController.getPlayQualites();
      if (loadEpoch != _roomLoadEpoch) return;

      if (liveRoom.platform != Sites.iptvSite) {
        await _addRoomToHistory(liveRoom);
        await _updateFavoriteRoomSnapshot(liveRoom);
      }

      await _syncDanmakuConnection(liveRoom);
    } catch (error, stackTrace) {
      Log.dev(
        'Live room initialization failed (${error.runtimeType})',
        name: 'LivePlayController',
        stackTrace: stackTrace,
      );
      if (liveRoom.isRestricted) {
        ToastUtil.show(roomStateMessage(liveRoom));
      }
      updateRoom(success: false);
    }
  }

  Future<void> _syncDanmakuConnection(LiveRoom liveRoom) async {
    const except = [Sites.iptvSite, Sites.ccSite];
    final danmakuSettings = SettingsService.to.danmaku;
    final shouldConnectDanmaku = !danmakuSettings.hideDanmaku.v;
    if (!except.contains(liveRoom.platform) && shouldConnectDanmaku) {
      await danmakuController.connectRoom(liveRoom);
    } else {
      await danmakuController.stopDanmaku();
    }
  }

  Future<void> _handleNotLiveRoom(LiveRoom liveRoom) async {
    unawaited(danmakuController.stopDanmaku());
    clearSuperChats();
    updateRoom(success: false, isLiving: false);
    setNormalScreen();
    GlobalPlayerService.instance.player.isSystemFullscreen.value = false;
    GlobalPlayerService.instance.player.isWindowFullscreen.value = false;
    if (liveRoom.platform != Sites.iptvSite) {
      await _updateFavoriteRoomSnapshot(liveRoom);
    }
    ToastUtil.show(roomStateMessage(liveRoom));
    _restoreQualityAndLines();
  }

  Future<void> _updateFavoriteRoomSnapshot(LiveRoom liveroom) async {
    try {
      if (await FavoriteRoomController.to.updateRoomDurably(liveroom)) {
        EventBus.instance.emit('refresh_room_changed', true);
      }
    } catch (error, stackTrace) {
      Log.dev(
        'Persist favorite room refresh failed',
        name: 'LivePlayController',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _addRoomToHistory(LiveRoom liveroom) async {
    try {
      await HistoryController.to.addRoomToHistoryDurably(liveroom);
    } catch (error, stackTrace) {
      Log.dev('Persist room history failed', name: 'LivePlayController', error: error, stackTrace: stackTrace);
    }
  }

  void _handleUnknownStatus() {
    settleUnknownRoomMetadata();
    final message = unknownRoomStatusMessage(state.value.room.detail);
    if (state.value.player.hasPlaybackSource) {
      if (Get.currentRoute == '/live_play') ToastUtil.show(message);
      return;
    }
    unawaited(danmakuController.stopDanmaku());
    if (Get.currentRoute == '/live_play') {
      ToastUtil.show(message);
      setNormalScreen();
      GlobalPlayerService.instance.player.isSystemFullscreen.value = false;
      GlobalPlayerService.instance.player.isWindowFullscreen.value = false;
    }
  }

  @visibleForTesting
  void settleUnknownRoomMetadata() {
    final hasPlaybackSource = state.value.player.hasPlaybackSource;
    updateRoom(
      isLiving: hasPlaybackSource,
      success: hasPlaybackSource,
      isLoading: false,
      loadError: unknownRoomStatusMessage(state.value.room.detail),
    );
  }

  void _handleCurrentLineAndQuality(ReloadDataType reloadDataType, int line, bool isReCalculate) {
    if (reloadDataType == ReloadDataType.changeLine && isReCalculate && state.value.player.hasPlaybackSource) {
      final newLineIndex = (state.value.player.currentLineIndex + 1) % state.value.player.lineCount;
      updatePlayer(currentLineIndex: newLineIndex);
    }
  }

  Future<IptvPlaybackSwitchResult> _initIptvPlayer(LiveRoom liveRoom, {required int loadEpoch}) async {
    final link = liveRoom.link?.trim() ?? '';
    if (link.isEmpty || liveRoom.normalizedRoomId.isEmpty) {
      if (_isRoomLoadCurrent(loadEpoch, liveRoom)) {
        updateRoom(success: false, isLoading: false, loadError: i18n('invalid_play_url'));
        ToastUtil.show(i18n('invalid_play_url'));
      }
      return IptvPlaybackSwitchResult.failed;
    }

    updatePlayer(qualites: [LivePlayQuality(quality: '原画')], currentQuality: 0, currentLineIndex: 0);

    final started = await _switchToUrl(link, expectedRoom: liveRoom);
    if (!_isRoomLoadCurrent(loadEpoch, liveRoom)) {
      return IptvPlaybackSwitchResult.superseded;
    }

    try {
      await danmakuController.stopDanmaku();
    } catch (error, stackTrace) {
      Log.dev('IPTV danmaku cleanup failed', name: 'LivePlayController', error: error, stackTrace: stackTrace);
    }
    return started;
  }

  void _restoreQualityAndLines() {
    updatePlayer(playUrls: [], currentLineIndex: 0, qualites: [], currentQuality: 0);
  }

  /// Closing the old native player also ends ownership of its selected media.
  /// A failed detail lookup for the next room must not reuse that old source.
  @visibleForTesting
  void clearClosedPlaybackSource() => _restoreQualityAndLines();

  Future<void> switchRoom(LiveRoom newRoom) async {
    // A reconnect ladder, and a stall-refresh count, belong to the room they
    // started for.
    _stopReconnect();
    _roomHasPlayed = false;
    _stallRefreshes = 0;
    _lastStallRefreshAt = null;
    // Fence any room-detail/play-quality request that was started before this
    // switch. Its late result must not restore the previous room or socket.
    invalidateRoomLoad();
    _iptvPlaybackEpoch++;
    playerController.invalidateLoad();
    final sameRoom =
        state.value.room.detail?.roomId == newRoom.roomId && state.value.room.detail?.platform == newRoom.platform;

    if (!sameRoom) {
      // At once, before anything is awaited: the previous room's danmaku
      // leaves the screen, the chat list and the filters, and no more of it
      // gets in.
      danmakuController.cutOff();
      clearDanmakuMessages();
      await danmakuController.stopDanmaku();
    }

    final manager = GlobalPlayerService.instance.player;
    await manager.close();

    // The previous room's controller stays until the new room's replaces it
    // (setPlayer tears it down then): its controls, gestures and side panels
    // keep working through the load; only the title and the quality/line
    // labels wait, showing a spinner. A switch that ends without a player
    // (offline, failed) removes it below.
    final switchEpoch = ++_roomSwitchEpoch;
    final previousController = state.value.player.videoController;
    previousController?.clearDanmaku();
    updateRoom(success: false, isLiving: true, isLoading: true);
    clearClosedPlaybackSource();
    clearSuperChats();

    updatePlayer(hasUseDefaultResolution: false);
    updateUI(refreshKey: 0);

    final autoStartAsmr = Platform.isAndroid && SettingsService.to.app.enableAsmrSleepMode.v;
    _asmrSessionActive = autoStartAsmr;
    await LiveAudioService.configureSleepTimer(
      enabled: autoStartAsmr,
      minutes: SettingsService.to.app.asmrSleepMinutes.v,
    );
    updatePlayer(isCurrentRoomAudioOnly: autoStartAsmr);

    updateRoom(liveroom: newRoom);
    currentSite = Sites.of(newRoom.platform!);
    playerController.initSite(currentSite);

    if (!sameRoom) {
      await danmakuController.replaceDanmaku(currentSite.liveSite.getDanmaku());
    }

    await EmojiManager.instance.preload(
      newRoom.platform!,
      Sites.danmakuCapability(newRoom.platform)?.parseDanmakuEmoji,
      onAtlasChanged: emojiCache.clear,
    );

    await onInitPlayerState(
      reloadDataType: newRoom.platform == Sites.bilibiliSite ? ReloadDataType.changeLine : ReloadDataType.refresh,
    );
    if (previousController != null &&
        switchEpoch == _roomSwitchEpoch &&
        identical(state.value.player.videoController, previousController)) {
      await playerController.destroyPlayer();
    }
  }

  /// Bumped by every [switchRoom], so only the latest switch removes the
  /// controller it kept.
  int _roomSwitchEpoch = 0;

  Future<void> setResolution(ReloadDataType reloadDataType, int qualityIndex, int lineIndex) async {
    await playerController.switchStreamSelection(
      type: reloadDataType,
      qualityIndex: qualityIndex,
      lineIndex: lineIndex,
    );
  }

  Future<void> openNaviteAPP() async {
    if (_ownerClosed || _externalOpenInFlight) return;
    final detail = state.value.room.detail;
    if (detail == null) return;
    final roomId = detail.roomId;
    bool isCurrent() => !_ownerClosed && identical(state.value.room.detail, detail) && detail.roomId == roomId;
    _externalOpenInFlight = true;
    try {
      final result = await RoomExternalOpener.open(
        site: site,
        liveroom: detail,
        android: Platform.isAndroid,
        isCurrent: isCurrent,
        onBrowserFallback: () => ToastUtil.show(i18n('open_app_failed_fallback_browser')),
      );
      if (!isCurrent()) return;
      if (result == RoomExternalOpenResult.unavailable) {
        ToastUtil.show(i18n('open_room_external_unavailable'));
      } else if (result == RoomExternalOpenResult.failed) {
        ToastUtil.show(i18n('open_room_external_failed'));
      }
    } finally {
      _externalOpenInFlight = false;
    }
  }

  Future<IptvPlaybackSwitchResult> startCatchUp({required String catchUpUrl, int? startTime, int? endTime}) async {
    final currentRoom = state.value.room.detail;
    final normalizedUrl = catchUpUrl.trim();
    if (currentRoom == null || currentRoom.normalizedRoomId.isEmpty || normalizedUrl.isEmpty) {
      return IptvPlaybackSwitchResult.failed;
    }

    final updatedRoom = currentRoom.copyWith(
      catchUpUrl: normalizedUrl,
      isCatchUp: true,
      catchUpStart: startTime,
      catchUpEnd: endTime,
    );

    updateRoom(liveroom: updatedRoom);
    return _switchToUrl(normalizedUrl, expectedRoom: updatedRoom);
  }

  Future<IptvPlaybackSwitchResult> returnToLive() async {
    final currentRoom = state.value.room.detail;
    final liveUrl = currentRoom?.link?.trim() ?? '';
    if (currentRoom == null || currentRoom.normalizedRoomId.isEmpty || liveUrl.isEmpty) {
      return IptvPlaybackSwitchResult.failed;
    }
    if (!currentRoom.isCatchUpActive) {
      return IptvPlaybackSwitchResult.started;
    }

    final liveRoom = currentRoom.withoutCatchUp();
    updateRoom(liveroom: liveRoom);
    return _switchToUrl(liveUrl, expectedRoom: liveRoom);
  }

  Future<IptvPlaybackSwitchResult> _switchToUrl(String url, {required LiveRoom expectedRoom}) async {
    final playbackEpoch = ++_iptvPlaybackEpoch;
    updateRoom(success: false, isLoading: true, loadError: null);
    updatePlayer(playUrls: [url], currentLineIndex: 0);
    try {
      final injectedStarter = _iptvPlayerStarter;
      final started = injectedStarter != null
          ? await injectedStarter(expectedRoom)
          : await playerController.setDirectPlayer(liveroom: expectedRoom, site: currentSite) != null;
      if (!_isIptvPlaybackCurrent(playbackEpoch, expectedRoom)) {
        return IptvPlaybackSwitchResult.superseded;
      }
      if (!started) {
        updateRoom(success: false, isLoading: false, loadError: i18n('play_video_failed'));
        return IptvPlaybackSwitchResult.failed;
      }
      updateRoom(success: true, isLoading: false, loadError: null);
      return IptvPlaybackSwitchResult.started;
    } catch (error, stackTrace) {
      Log.dev(
        'IPTV direct player start failed',
        name: 'LivePlayController',
        error: error,
        stackTrace: stackTrace,
      );
      if (!_isIptvPlaybackCurrent(playbackEpoch, expectedRoom)) {
        return IptvPlaybackSwitchResult.superseded;
      }
      updateRoom(success: false, isLoading: false, loadError: i18n('play_video_failed'));
      rethrow;
    }
  }

  bool _isIptvPlaybackCurrent(int playbackEpoch, LiveRoom expectedRoom) {
    final currentRoom = state.value.room.detail;
    return !_ownerClosed &&
        !isClosed &&
        playbackEpoch == _iptvPlaybackEpoch &&
        currentRoom?.normalizedRoomId == expectedRoom.normalizedRoomId &&
        currentRoom?.normalizedPlatformId == expectedRoom.normalizedPlatformId &&
        currentRoom?.catchUpUrl == expectedRoom.catchUpUrl;
  }

  void setNormalScreen() => updateUI(screenMode: VideoMode.normal);
  void setWidescreen() => updateUI(screenMode: VideoMode.widescreen);
  void setFullScreen() => updateUI(screenMode: VideoMode.fullscreen);
  void setPortraitFullScreen() => updateUI(screenMode: VideoMode.portraitFullscreen);

  /// Hides media_kit's native surface before opening the recorder route.
  ///
  /// Keeping the live route mounted preserves playback and room state.  The
  /// video layer policy decides whether the native texture is retained
  /// (Android) or detached (Windows). Restoration belongs to the route
  /// observer, which waits for the recorder route's reverse
  /// transition to finish before attaching a Windows texture again.
  Future<void> openRecordCenter() async {
    await Get.toNamed(RoutePath.kRecordPage);
  }

  Future<void> _disposeNormalRouteResources() async {
    try {
      // Explicitly stop the global source so decoder/network workers do not
      // survive on the home page. LivePlayerFacade keeps a short reopen grace
      // window and then releases the native player completely.
      await GlobalPlayerService.instance.player.close();
    } finally {
      try {
        final videoController = state.value.player.videoController;
        await danmakuController.stopDanmaku();
        videoController?.dispose();
      } finally {
        _releaseChildControllers();
        _closeReactiveState();
      }
    }
  }

  void _releaseChildControllers() {
    if (_childControllersReleased) return;
    _childControllersReleased = true;
    Get.delete<TimerController>(tag: 'timer-$_controllerTag', force: true);
    Get.delete<DanmakuController>(tag: 'danmaku-$_controllerTag', force: true);
    Get.delete<PlayerController>(tag: 'player-$_controllerTag', force: true);
  }

  void _closeReactiveState() {
    if (_reactiveStateClosed) return;
    _reactiveStateClosed = true;
    state.close();
  }

  @override
  void onClose() {
    _nativeFullscreenSync.detach();
    unawaited(LiveAudioFocus.instance.detach());
    _stopReconnect();
    unawaited(_longStallSub?.cancel());
    _longStallSub = null;
    unawaited(_playerPhaseSub?.cancel());
    _playerPhaseSub = null;
    _awaySwitchTimer?.cancel();
    _awaySwitchTimer = null;
    // The player outlives the room: give its picture back.
    if (_videoOffByUs && !GlobalPlayerService.instance.player.desiredAudioOnlyMode) {
      unawaited(GlobalPlayerService.instance.player.setAudioOnly(false));
    }
    _videoOffByUs = false;
    _roomStateHoldWorker?.dispose();
    LiveAudioFocus.instance.pausedByInterruption.removeListener(_syncBackgroundHold);
    if (LiveAudioFocus.instance.onNoisyPause == _markUserPause) LiveAudioFocus.instance.onNoisyPause = null;
    if (LiveAudioService.onSleepTimerPause == _markUserPause) LiveAudioService.onSleepTimerPause = null;
    BackgroundPlaybackService.clearRemotePauseListener(_remotePauseListener);
    _backgroundKeeper.dispose();
    unawaited(BackgroundPlaybackService.setForegroundHold(false));
    _ownerClosed = true;
    _roomLoadEpoch++;
    _iptvPlaybackEpoch++;
    WidgetsBinding.instance.removeObserver(this);
    _pipStateWorker?.dispose();
    _screenKeepOnWorker?.dispose();
    _superChatPinnedWorker?.dispose();
    _danmakuPresentationRecovery.dispose();
    clearSuperChats();
    playerController.invalidateLoad();
    _danmakuFlushTimer?.cancel();
    _pendingDanmakuMessages.clear();
    tabController.dispose();
    unawaited(_danmakuRemovals.close());

    // The sleep session belongs to this room; a later room must not be
    // paused by its timer.
    if (_asmrSessionActive || LiveAudioService.isSleepSessionActive) {
      unawaited(
        LiveAudioService.configureSleepTimer(enabled: false, minutes: SettingsService.to.app.asmrSleepMinutes.v),
      );
    }
    unawaited(_disposeNormalRouteResources());
    super.onClose();
  }
}

/// Follows the desktop window leaving native fullscreen on its own.
///
/// macOS lets the window leave fullscreen without the app's controls (the green
/// window button, ⌃⌘F, a trackpad swipe). The room kept believing it was
/// fullscreen, so the next Back was spent "leaving" a presentation that was
/// already gone (the page flashed black) and a second Back was needed to
/// leave the room.
class _NativeFullscreenSync with WindowListener {
  _NativeFullscreenSync(this._owner);

  final LivePlayController _owner;
  bool _attached = false;

  bool get _supported => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  void attach() {
    if (!_supported || _attached) return;
    _attached = true;
    windowManager.addListener(this);
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    windowManager.removeListener(this);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (_owner.isClosed) return;
    final player = GlobalPlayerService.instance.player;
    final mode = _owner.state.value.ui.screenMode;
    if (!player.isSystemFullscreen.value && mode == VideoMode.normal) return;
    unawaited(_owner.exitPresentationForSystemBack());
  }
}
