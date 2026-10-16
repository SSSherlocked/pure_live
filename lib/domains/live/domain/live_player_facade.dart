import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/core/config/settings_service.dart';
import 'package:pure_live/core/storage/hive_rx.dart';
import 'package:pure_live/domains/live/domain/playback_startup_timing.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core_live/media_core_live.dart';
import 'package:pure_live/core/models/live_room.dart';
import 'package:pure_live/core/player/models/player_engine.dart';
import 'package:pure_live/core/stream/hls_source_query_policy.dart';
import 'package:pure_live/core/player/core/audio_only_mode_policy.dart';
import 'package:pure_live/core/player/core/dummy_video_policy.dart';
import 'package:pure_live/core/player/core/playback_lifecycle_coordinator.dart';
import 'package:pure_live/core/player/core/playback_source.dart';
import 'package:pure_live/core/models/live_play_quality.dart';
import 'package:pure_live/shared/platforms/live_site.dart' show LiveStreamFacts;
import 'package:pure_live/domains/live/domain/playback_source_interceptor.dart';
import 'package:pure_live/domains/live/domain/playback_source_refresh.dart';
import 'package:media_core_media_kit/media_core_media_kit.dart';
import 'package:pure_live/core/logging/app_log.dart';
import 'package:pure_live/core/player/presentation/windows_pip_driver.dart';
import 'package:pure_live/core/player/core/portrait_stream_support.dart';
import 'package:pure_live/core/player/kernel/player_kernel_service.dart';
import 'package:pure_live/core/player/kernel/open_volume.dart';
import 'package:pure_live/core/player/presentation/fullscreen_window.dart' show fullscreenDriver;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:pure_live/domains/live/presentation/playback/widgets/danmaku/compact_danmaku_overlay.dart';
import 'package:media_core_better_player/media_core_better_player.dart' show kBetterPlayerBackendId;
import 'package:media_core_ijk_player/media_core_ijk_player.dart' show kIjkPlayerBackendId;

final class LivePlayerFacade {
  LivePlayerFacade({
    PlayerEngine defaultEngine = PlayerEngine.mediaKit,
    PlaybackSourceInterceptor? sourceInterceptor,
    bool Function()? useHardStopOnExit,
  }) : preferredEngine = defaultEngine,
       _useHardStopOnExit = useHardStopOnExit ?? (() => SettingsService.to.player.useHardStopOnExit.v) {
    _sourceInterceptor = sourceInterceptor;
    // Both refresh questions — "the lines died, give me new ones" and "the
    // engine is changing, give me lines it can use" — have one answer: ask the
    // platform again. The engine id the second port passes adds nothing the
    // resolver could act on, since a refreshed plan is rebuilt from the room.
    _controller = LivePlaybackController(
      kernel,
      // A line that opens but never starts is dropped after 10 s instead of
      // the package's 18 s. A fresh player (the first room after start, or after
      // the 45 s idle release) verifies each line before showing it, so a dead
      // CDN node held the first room black, and silent, for the full window.
      watchdogs: LiveWatchdogs(sourceReadyTimeout: const Duration(seconds: 10)),
      onRecoverySources: _refreshSources,
      onEngineFallbackSources: (nextEngine, current) => _refreshSources(current),
    );
    _bindController();
    // The fullscreen driver is the single source of truth for the fullscreen
    // presentation; the Rx mirror only makes it observable to GetX widgets.
    fullscreenDriver.onFullscreenChanged.listen((_) => _syncSystemFullscreenFromDriver());
    _syncSystemFullscreenFromDriver();
  }

  void _syncSystemFullscreenFromDriver() {
    isSystemFullscreen.value = fullscreenDriver.isSystemFullscreen;
  }

  PlaybackSourceInterceptor? _sourceInterceptor;

  /// 播放器强制销毁: when on, leaving a room releases the native player at
  /// once; when off the room's stream is stopped and the engine released
  /// after [idleReleaseDelay], so a room opened meanwhile reuses the warm
  /// engine instead of a cold start.
  final bool Function() _useHardStopOnExit;
  static const Duration idleReleaseDelay = Duration(seconds: 45);
  Timer? _idleReleaseTimer;

  /// Keeps a paused player for the next request instead of releasing it.
  void _cancelIdleRelease() {
    _idleReleaseTimer?.cancel();
    _idleReleaseTimer = null;
  }

  PlaybackSourceResolver? _sourceResolver;

  static PlayerKernel get kernel => PlayerKernelService.instance.kernel;

  late final LivePlaybackController _controller;

  PlayerEngine preferredEngine;
  void Function(PlayerEngine engine)? onEngineChanged;

  final _stateSubject = StreamController<PlayerCoreState>.broadcast();
  final _playingSubject = StreamController<bool>.broadcast();
  final _errorSubject = StreamController<PlayerException>.broadcast();
  final _commitSubject = StreamController<FacadeStreamCommit?>.broadcast();

  StreamSubscription<PlayerCoreState>? _stateSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<PlayerFailure>? _errorSub;
  bool _disposed = false;

  FacadeStreamCommit? commit;
  Map<String, String> _lastHeaders = const {};

  /// Kernel preference order: the line swept first, the rest behind it.
  List<String> _lastLines = const [];
  LiveRoom? _room;

  int _commitRevision = 0;

  LiveRoom? get room => _room;

  /// Whether a room's stream is open: set by the opens, cleared by [close].
  /// Between rooms the engine stays warm with its last source still known,
  /// so anything that rebuilds or replays it (an output setting, a kernel
  /// switch) would bring the room left back, sound and all, over whatever
  /// page is on screen.
  bool get isServingRoom => _servingRoom;
  bool _servingRoom = false;

  /// Counts the rooms opened, and the user's own play/pause commands: a
  /// pause made for the background is only undone on return when neither
  /// moved since.
  int _roomSession = 0;
  int _userIntentRevision = 0;

  /// Set when a setting that only a new engine picks up changed while a
  /// room played: [close] then releases the engine instead of keeping it
  /// warm, so the next room starts on the new settings.
  bool _retireOnClose = false;
  void retireEngineOnClose() {
    Log.i('player: engine to be released when this room closes (settings changed)');
    _retireOnClose = true;
  }
  PlayerHandle? get handle => _controller.handle;

  /// Kernel-side handle lifecycle: emitted when an engine is attached and
  /// when the current one is released. Video surfaces follow this to mount
  /// as soon as the engine exists instead of waiting for an unrelated
  /// rebuild.
  Stream<PlayerHandle?> get onHandleChanged => _controller.onHandleChanged;
  bool get hasPlaybackSource => commit != null;
  bool get isPlayingNow => _playingSubject.hasListener && _lastPlaying;
  bool _lastPlaying = false;
  PlayerPlaybackState? _lastLoggedPlayback;
  int get currentLineIndex => commit?.currentLineIndex ?? 0;
  int get lineCount => _lastLines.length;
  List<String> get playUrls => _lastLines;
  List<LivePlayQuality> get qualites => commit?.qualities ?? const [];
  int get currentQuality => commit?.currentQuality ?? 0;
  Map<String, String> get sourceQueryPolicies => const {};

  Stream<PlayerCoreState> get onStateChanged => _stateSubject.stream;
  Stream<bool> get onPlaying => _playingSubject.stream;
  Stream<PlayerException> get onError => _errorSubject.stream;
  Stream<PlayerFailure> get onKernelError => _controller.onError;
  Stream<FacadeStreamCommit?> get onCommitChanged => _commitSubject.stream;

  void _bindController() {
    _stateSub = _controller.onStateChanged.listen((state) {
      _stateSubject.add(state);
      _onStateChanged(state);
      _tryApplyPendingSeek();
      final playing = state.playback == PlayerPlaybackState.playing;
      if (playing != _lastPlaying) {
        _lastPlaying = playing;
        _playingSubject.add(playing);
      }
      // No room is open, so nothing may play: a stream that comes back to
      // life after its room was left (a late reconnect, an open that was
      // still running) is stopped, not heard behind the home page.
      if (playing && !_servingRoom && !_disposed) {
        Log.w('player: playing with no room open; stopped');
        unawaited(_controller.stop());
      }
      _watchForStall(state.playback);
      // Transitions only: the kernel repeats its state on every tick.
      if (state.playback != _lastLoggedPlayback) {
        _lastLoggedPlayback = state.playback;
        Log.i('player: ${state.playback.name}');
      }
    });
    _errorSub = _controller.onError.listen((failure) {
      Log.w('player failure ${failure.code}: ${failure.message}');
      _errorSubject.add(
        PlayerException(
          code: failure.code,
          message: failure.message,
          cause: failure.cause,
          stackTrace: failure.stackTrace,
        ),
      );
    });
  }

  Future<void> play(
    String url,
    List<String> playUrls,
    Map<String, String> headers, {
    LiveRoom? liveroom,
    List<LivePlayQuality> qualities = const [],
    int currentQuality = 0,
    bool audioOnly = false,
    PlaybackSourceResolver? sourceResolver,
    DateTime? sourceRefreshAt,
    Object? sourceSelection,
  }) async {
    if (_disposed) return;
    _sourceResolver = sourceResolver;
    // The open says what the room wants, both ways: a 纯音频 left on by the
    // previous room must not carry over, with the picture covered or its
    // decoder still off.
    if (audioOnly) {
      await setAudioOnlyMode(true, stopVideoDecoding: true);
    } else if (_audioOnlyMode.value) {
      await setAudioOnlyMode(false, stopVideoDecoding: true);
    }
    final sourceUrl = url.trim();
    if (sourceUrl.isEmpty) throw ArgumentError('Remote playback source is empty');
    PlaybackStartupTiming.instance.mark('urls');

    final urls = <String>[sourceUrl, ...playUrls.where((value) => value != sourceUrl)];
    _room = liveroom;
    // A stream still playing when a room opens is one that outlived the room
    // it belonged to (what played behind the home page).
    if (_lastPlaying && !_servingRoom) Log.w('player: a stream was still playing when this room opened');
    _servingRoom = true;
    _resetPictureWatch();
    _roomSession++;
    _lastHeaders = Map<String, String>.unmodifiable(headers);
    _lastLines = List<String>.unmodifiable(urls);

    // The caller's sourceSelection (the quality confirmation from the stream
    // switch) is authoritative: dropping it left the quality label pinned on the
    // first entry after every switch. It also carries the platform's per-line
    // stream facts, which is what the ingest wiring decides from.
    final committed = sourceSelection is PlaybackSourceQualitySelection ? sourceSelection : null;
    final streamFacts = committed?.streamFacts ?? const <String, LiveStreamFacts>{};

    // Declared before the open so libmpv starts at the room's level; a
    // post-open setVolume let one 100% frame of audio through first.
    OpenVolume.pending = _openVolumeFor(liveroom);
    _cancelIdleRelease();
    // Hosts only: a signed live URL carries its token in the query.
    Log.i('player: open ${urls.length} line(s): ${urls.map((line) => Uri.tryParse(line)?.host ?? '?').join(', ')}');
    final openClock = Stopwatch()..start();
    await _controller.play(
      LiveSourceRequest(
        sources: await _intercept(
          livePlanSources(
            urls,
            headers: headers,
            streamFacts: streamFacts,
            // The rotation-room start is seeked to once, on first open only, so
            // these lines must stay force-seekable; ordinary live lines get no
            // stamp and drop force-seekable (see MediaKitLiveProperties).
            startAt: committed?.startAt ?? Duration.zero,
            // What the status-bar notification and the lock screen show: the
            // room the viewer opened, not the stream URL's file name.
            title: liveroom == null ? null : liveSourceTitle(liveroom),
            artUri: liveroom == null ? null : liveSourceArtUri(liveroom),
          ),
          streamFacts: streamFacts,
          sourceQueryPolicies: committed?.sourceQueryPolicies ?? const {},
        ),
        title: liveroom?.title,
      ),
      preferredBackend: backendIdOfEngine(preferredEngine),
    );
    Log.i('player: open returned after ${openClock.elapsedMilliseconds} ms');
    PlaybackStartupTiming.instance.mark('open');
    // The commit carries the platform's line order — the list the line
    // selector, the label and the next-line cycling are all written against.
    // `_lastLines` above is the kernel's fallback preference (selected first)
    // and must not leak into it, or every commit would report line 1.
    _declaredAspectRatio = committed?.declaredAspectRatio;
    _pendingSeekAt = committed?.startAt;
    _publishCommit(
      sourceUrl,
      playUrls,
      committed?.qualities ?? qualities,
      committed?.currentQuality ?? currentQuality,
      streamFacts: streamFacts,
    );
    if (liveroom != null) await setVolume(_openVolumeFor(liveroom));
  }

  Future<void> playOwned(
    OwnedPlaybackSource source,
    LiveRoom liveroom, {
    List<LivePlayQuality> qualities = const [],
    int currentQuality = 0,
    Object? sourceSelection,
    bool audioOnly = false,
    PlaybackSourceResolver? sourceResolver,
  }) async {
    if (_disposed) return;
    _sourceResolver = sourceResolver;
    // The open says what the room wants, both ways: a 纯音频 left on by the
    // previous room must not carry over, with the picture covered or its
    // decoder still off.
    if (audioOnly) {
      await setAudioOnlyMode(true, stopVideoDecoding: true);
    } else if (_audioOnlyMode.value) {
      await setAudioOnlyMode(false, stopVideoDecoding: true);
    }
    _room = liveroom;
    // A stream still playing when a room opens is one that outlived the room
    // it belonged to (what played behind the home page).
    if (_lastPlaying && !_servingRoom) Log.w('player: a stream was still playing when this room opened');
    _servingRoom = true;
    _resetPictureWatch();
    _roomSession++;
    _lastHeaders = const {};
    _lastLines = const [];
    OpenVolume.pending = _openVolumeFor(liveroom);
    _cancelIdleRelease();
    await _controller.play(
      LiveSourceRequest(sources: await _intercept([ownedPlanSource(source, liveroom)])),
      preferredBackend: backendIdOfEngine(preferredEngine),
    );
    final committed = sourceSelection is PlaybackSourceQualitySelection ? sourceSelection : null;
    _publishCommit(
      'owned:${liveroom.identityKey}',
      const [],
      committed?.qualities ?? qualities,
      committed?.currentQuality ?? currentQuality,
      source: source,
    );
    await setVolume(_openVolumeFor(liveroom));
  }

  void _publishCommit(
    String url,
    List<String> uiLines,
    List<LivePlayQuality> qualities,
    int currentQuality, {
    Map<String, LiveStreamFacts> streamFacts = const {},
    Object? source,
  }) {
    // `uiLines` is the platform-ordered line list; the index is the line the
    // selector highlighted. Deriving it from `_lastLines` (kernel fallback
    // order, selected line first) would report line 1 for every commit.
    final lineIndex = uiLines.isEmpty ? 0 : uiLines.indexOf(url).clamp(0, uiLines.length - 1);
    commit = FacadeStreamCommit(
      revision: ++_commitRevision,
      room: _room ?? LiveRoom(platform: '', roomId: ''),
      urls: List<String>.unmodifiable(uiLines),
      currentUrl: url,
      currentLineIndex: lineIndex,
      headers: _lastHeaders,
      qualities: List<LivePlayQuality>.unmodifiable(qualities),
      currentQuality: currentQuality,
      streamFacts: streamFacts,
      source: source,
    );
    _commitSubject.add(commit);
  }

  Future<void> playSource(
    OwnedPlaybackSource source, {
    LiveRoom? liveroom,
    bool audioOnly = false,
    PlaybackSourceResolver? sourceResolver,
    Object? sourceSelection,
    DateTime? sourceRefreshAt,
  }) => playOwned(
    source,
    liveroom ?? _room ?? LiveRoom(platform: '', roomId: ''),
    sourceSelection: sourceSelection,
    audioOnly: audioOnly,
    sourceResolver: sourceResolver,
  );

  Future<void> switchLine(int index) {
    _cancelIdleRelease();
    return _controller.switchLine(index);
  }

  Future<void> retry() {
    _cancelIdleRelease();
    return _controller.retry();
  }

  Future<void> togglePlayPause() {
    Log.i('player: toggle play/pause');
    _userIntentRevision++;
    return _controller.togglePlayPause();
  }

  Future<void> pause() {
    Log.i('player: pause');
    _userIntentRevision++;
    return _controller.pause();
  }

  /// Pauses a playing room because the app went to the background without
  /// background play (mobile only; see GlobalPlayerService). Returns what
  /// [resumeFromLifecycle] needs to resume it, or null when nothing was
  /// paused.
  Future<PlaybackLifecyclePauseToken?> pauseForLifecycle() async {
    if (!_servingRoom || !_lastPlaying) return null;
    final token = (sessionId: _roomSession, intentRevision: _userIntentRevision);
    // Told first, or the kernel's unexpected-pause watchdog takes this pause
    // for a fault and resumes the room the user cannot see.
    _controller.noteBackgrounded();
    await _controller.pause();
    return token;
  }

  /// Resumes the room [pauseForLifecycle] paused, unless the room changed or
  /// the user played or paused since.
  Future<bool> resumeFromLifecycle(PlaybackLifecyclePauseToken token) async {
    if (!_servingRoom || token.sessionId != _roomSession || token.intentRevision != _userIntentRevision) return false;
    await _controller.resume();
    return true;
  }

  Future<void> resume() {
    Log.i('player: resume');
    _userIntentRevision++;
    _cancelIdleRelease();
    return _controller.resume();
  }
  Future<void> setVolume(double volume) => _controller.setVolume(volume.clamp(0.0, 1.0));

  /// 系统音量滑杆平台(Android/iOS)上,房间内滑杆控制的是系统音量;
  /// 播放器内部增益必须恒定 1.0 —— 开屏若应用房间记忆音量(默认 0.5),
  /// 滑杆显示 100% 而实际只有一半增益,用户既看不到也改不了这层衰减。
  /// 无系统音量控制的平台保留房间记忆音量。
  double _openVolumeFor(LiveRoom? room) {
    if (Platform.isAndroid || Platform.isIOS) return 1.0;
    return (room?.getSavedVolume() ?? 1.0).clamp(0.0, 1.0);
  }
  Future<void> setAudioOnly(bool audioOnly) {
    _videoOff = audioOnly;
    return _controller.setAudioOnly(audioOnly);
  }

  /// Whether video decoding was turned off on purpose (audio-only, or
  /// 后台只播声音 while away): no picture is then expected.
  bool _videoOff = false;
  void setPresentationVisible(bool visible) => _controller.setPresentationVisible(visible);

  Future<void> switchEngine(PlayerEngine engine, {bool isManual = false, bool resumeCurrentSource = true}) async {
    preferredEngine = engine;
    onEngineChanged?.call(engine);
    if (!_servingRoom) {
      // No room open: the next one starts on the new engine.
      await releaseIdleEngine();
      return;
    }
    final current = commit;
    if (current != null && current.urls.isNotEmpty) {
      // commit.urls is the platform-ordered line list; the playing line stays
      // the kernel's first candidate across the engine rebuild.
      final lines = current.currentUrl.isEmpty
          ? current.urls
          : <String>[current.currentUrl, ...current.urls.where((url) => url != current.currentUrl)];
      _cancelIdleRelease();
      await _controller.play(
        LiveSourceRequest(
          sources: await _intercept(
            livePlanSources(
              lines,
              headers: current.headers,
              streamFacts: current.streamFacts,
              title: _room == null ? null : liveSourceTitle(_room!),
              artUri: _room == null ? null : liveSourceArtUri(_room!),
            ),
            streamFacts: current.streamFacts,
            sourceQueryPolicies: current.sourceQueryPolicies,
          ),
          title: _room?.title,
        ),
        preferredBackend: backendIdOfEngine(engine),
      );
    }
  }

  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------

  final RxBool hasError = false.obs;
  final RxBool _audioOnlyMode = false.obs;
  final RxBool isVerticalVideo = false.obs;

  final RxBool isDummyVideo = false.obs;
  final _loadingSubject = StreamController<bool>.broadcast();
  bool _lastLoading = false;

  /// True while the player says it is playing but its position has stood
  /// still for [stallThreshold]: a freeze the engine does not report as
  /// buffering (ijkplayer's adapter reports none mid-play, and mpv reports
  /// only the dry spells cache-pause catches). This is how the picture's
  /// spinner learns about it; while the player reports buffering, the
  /// spinner already shows.
  final RxBool isStalled = false.obs;
  static const Duration stallThreshold = Duration(milliseconds: 1200);

  /// How long the position may stand still before [onLongStall] fires: a
  /// stream that stops without an error (mpv keeps "playing" through a dead
  /// connection) is left to the room to refresh. Buffering gets longer, since
  /// the engine is at least waiting for data.
  static const Duration longStallWhilePlaying = Duration(seconds: 10);
  static const Duration longStallWhileBuffering = Duration(seconds: 30);
  final _longStallSubject = StreamController<Duration>.broadcast();
  Stream<Duration> get onLongStall => _longStallSubject.stream;

  static const Duration _stallPollInterval = Duration(milliseconds: 300);
  Timer? _stallTimer;
  Duration? _stallLastPosition;
  PlayerPlaybackState? _stallPlayback;
  final Stopwatch _sinceAdvance = Stopwatch();
  // Only a position that has moved since the watch began counts: an engine
  // that never reports one must not spin, or be refreshed, forever.
  bool _positionAdvanced = false;
  bool _longStallReported = false;

  /// The watch runs while the player is trying to play (playing or
  /// buffering) and stops on anything else (paused, opening, stopped, ...).
  void _watchForStall(PlayerPlaybackState playback) {
    _stallPlayback = playback;
    final trying = playback == PlayerPlaybackState.playing || playback == PlayerPlaybackState.buffering;
    if (!trying) {
      _stallTimer?.cancel();
      _stallTimer = null;
      _setStalled(false);
      return;
    }
    if (playback != PlayerPlaybackState.playing) _setStalled(false);
    if (_stallTimer != null) return;
    _stallLastPosition = _controller.handle?.position;
    _positionAdvanced = false;
    _longStallReported = false;
    _sinceAdvance
      ..reset()
      ..start();
    _stallTimer = Timer.periodic(_stallPollInterval, (_) => _checkStall());
  }

  void _checkStall() {
    final position = _controller.handle?.position;
    if (position != _stallLastPosition) {
      _stallLastPosition = position;
      _positionAdvanced = true;
      _longStallReported = false;
      _sinceAdvance
        ..reset()
        ..start();
      _setStalled(false);
      return;
    }
    if (!_positionAdvanced) return;
    final still = _sinceAdvance.elapsed;
    final playing = _stallPlayback == PlayerPlaybackState.playing;
    if (playing && still >= stallThreshold) _setStalled(true);
    final longStall = playing ? longStallWhilePlaying : longStallWhileBuffering;
    if (!_longStallReported && still >= longStall) {
      _longStallReported = true;
      Log.w('player: no progress for ${still.inSeconds} s while ${_stallPlayback?.name}');
      if (!_longStallSubject.isClosed) _longStallSubject.add(still);
    }
  }

  /// How long a room may play sound with no picture before its stream is
  /// reopened.
  static const Duration noPictureGrace = Duration(seconds: 4);
  Timer? _noPictureTimer;

  /// Whether this room's stream was already reopened for want of a picture.
  bool _noPictureReopened = false;

  /// Whether this stream has shown a picture: only a stream that never did
  /// is reopened, not one whose picture went away later.
  bool _pictureSeen = false;

  /// A room that plays sound but never gets a picture is reopened once.
  ///
  /// Some FLV edges (seen on Bilibili) send a header that declares only an
  /// audio stream: FFmpeg's probe then stops as soon as the audio is found,
  /// the video track is never created and the picture stays black while the
  /// sound plays. A new connection gets a proper header, so one reopen
  /// brings the picture back. Audio-only modes and audio-only platforms are
  /// left alone.
  void _watchForPicture({required bool playing, required bool hasPicture, required bool dummy}) {
    if (hasPicture) _pictureSeen = true;
    if (hasPicture || !playing || dummy || _audioOnlyMode.value || _videoOff || _pictureSeen || _noPictureReopened) {
      if (hasPicture || !playing) {
        _noPictureTimer?.cancel();
        _noPictureTimer = null;
      }
      return;
    }
    _noPictureTimer ??= Timer(noPictureGrace, _checkForPicture);
  }

  void _checkForPicture() {
    _noPictureTimer = null;
    if (_disposed || _noPictureReopened || _pictureSeen || !_servingRoom || _audioOnlyMode.value || _videoOff) return;
    final snapshot = _controller.handle?.combinedSnapshot;
    final size = snapshot?.geometry.videoSize;
    if (size != null && size.width > 0 && size.height > 0) return;
    // "Playing" is reported as soon as a line is being opened. Only a stream
    // whose position moves is actually sounding; one still connecting (or
    // being walked through failing lines) is looked at again later.
    if ((snapshot?.playback.position ?? Duration.zero) < const Duration(seconds: 1)) {
      _noPictureTimer = Timer(noPictureGrace, _checkForPicture);
      return;
    }
    _noPictureReopened = true;
    Log.w('player: sound but no picture after ${noPictureGrace.inSeconds} s; reopening the stream');
    unawaited(_controller.retry());
  }

  void _resetPictureWatch() {
    _noPictureTimer?.cancel();
    _noPictureTimer = null;
    _noPictureReopened = false;
    _pictureSeen = false;
  }

  void _setStalled(bool stalled) {
    if (isStalled.value == stalled) return;
    isStalled.value = stalled;
    Log.i(stalled ? 'player: stalled at ${_stallLastPosition?.inMilliseconds} ms' : 'player: stall over');
  }

  bool get isAudioOnlyMode => _audioOnlyMode.value;
  bool get desiredAudioOnlyMode => _audioOnlyMode.value;
  Stream<bool> get onLoading => _loadingSubject.stream;
  Stream<FacadeStreamCommit> get onSourceCommitted =>
      _commitSubject.stream.where((commit) => commit != null).cast<FacadeStreamCommit>();
  FacadeStreamCommit? get currentSourceCommit => commit;
  bool isSourceCommitCurrent(FacadeStreamCommit value) => identical(value, commit);

  Future<void> setAudioOnlyMode(bool audioOnly, {bool stopVideoDecoding = false}) async {
    _audioOnlyMode.value = audioOnly;
    if (audioOnlyStopsVideoDecoding(entering: audioOnly, stopVideoDecoding: stopVideoDecoding)) {
      await setAudioOnly(audioOnly);
    }
  }

  Widget getVideoWidget(BoxFit fit) {
    // The room UI mounts before the kernel finishes creating its engine, so
    // the first call usually sees no handle yet. The widget has to follow the
    // kernel's handle stream: a widget built once at mount would stay black
    // forever — nothing else re-reads the attached handle — until a full
    // subtree remount (fullscreen toggle, PiP) forced a rebuild.
    return StreamBuilder<PlayerHandle?>(
      stream: _controller.onHandleChanged.distinct(),
      initialData: _controller.handle,
      builder: (context, snapshot) {
        // Read the getter, not the snapshot: a released engine replays its
        // old handle on the stream, and the getter is the only source of truth.
        final handle = _controller.handle;
        if (handle == null) return const SizedBox.expand();
        return MediaPlayerView(handle: handle, fit: fit);
      },
    );
  }

  void changeVideoFit(Object fitOrIndex, {List<BoxFit>? fitList}) {
    final fit = fitOrIndex is int
        ? (fitList == null || fitList.isEmpty ? BoxFit.contain : fitList[fitOrIndex.clamp(0, fitList.length - 1)])
        : fitOrIndex as BoxFit;
    (_controller.handle?.adapter as PlayerVideo?)?.setVideoFit(fit);
  }

  dynamic get currentPlayer => _controller.handle;

  /// The live room's [VideoController], when one is attached. Used by the
  /// picture-in-picture overlay to mount the compact
  /// danmaku surface.
  dynamic get activeVideoController => _activeVideoController;
  LiveRoom? get currentFloatRoom => _room;
  bool hasActivePlaybackSession(LiveRoom liveroom) => _room == liveroom && isPlayingNow;

  /// True while the video surface is presented compactly — the system/desktop
  /// picture-in-picture. The danmaku layer reads this per message to decide
  /// whether the compact barrage surface is fed; a hardcoded false starves the
  /// overlay of danmaku entirely.
  bool get isCompactModeActive => isInPip.value;
  void refreshPortraitPresentationPolicy() {}

  /// The video controller that currently owns playback (volume, status
  /// arbitration). Attached when a room's controller is constructed and
  /// detached on dispose; `ownsVideoController` gates the controller's
  /// init path — a false answer makes it return before opening the media.
  dynamic _activeVideoController;

  void attachVideoController(dynamic controller) {
    _activeVideoController = controller;
  }

  void detachVideoController(dynamic controller) {
    if (identical(_activeVideoController, controller)) {
      _activeVideoController = null;
    }
  }

  bool ownsVideoController(dynamic controller) => identical(_activeVideoController, controller);

  void _onStateChanged(PlayerCoreState state) {
    final loading = state.playback == PlayerPlaybackState.buffering;
    if (loading != _lastLoading) {
      _lastLoading = loading;
      _loadingSubject.add(loading);
    }
    final handle = _controller.handle;
    final size = handle?.combinedSnapshot.geometry.videoSize;
    final next = size != null && size.height > size.width;
    if (next != isVerticalVideo.value) isVerticalVideo.value = next;
    // Layouts that follow the picture's aspect ratio watch this counter; the
    // size itself lives in the handle snapshot, which is not observable.
    if (size != _lastPresentedVideoSize) {
      _lastPresentedVideoSize = size;
      videoPresentationRevision.value++;
    }
    final dummy =
        (size != null && isDummyVideoSize(width: size.width, height: size.height)) ||
        isAudioOnlyPlatform(_room?.platform);
    if (dummy != isDummyVideo.value) isDummyVideo.value = dummy;
    // The compact window is shaped from the aspect it was fed when PiP began.
    // A live stream often reports its real size only after the first frame, and
    // a room can switch between landscape and portrait, so keep feeding it:
    // otherwise the window keeps the old shape and the picture arrives with
    // black bars that the shape snap then locks in.
    if (size != null && size.width > 0 && size.height > 0) {
      windowsPipDriver.onVideoSize((size.width / size.height * 1000).round(), 1000);
    }
    final hasPicture = size != null && size.width > 0 && size.height > 0 && !dummy;
    _watchForPicture(playing: state.playback == PlayerPlaybackState.playing, hasPicture: hasPicture, dummy: dummy);
    PlaybackStartupTiming.instance.reportPlaybackState(
      playing: state.playback == PlayerPlaybackState.playing,
      hasPicture: hasPicture,
      audioOnly: dummy || _audioOnlyMode.value,
    );
    videoGeometryState.value = _computeVideoGeometry();
  }

  Future<List<PlayerSource>> _intercept(
    List<PlayerSource> sources, {
    Map<String, LiveStreamFacts> streamFacts = const {},
    Map<String, HlsSourceQueryPolicy> sourceQueryPolicies = const {},
  }) async {
    final interceptor = _sourceInterceptor;
    if (interceptor == null) return sources;
    final intercepted = await interceptor.intercept(
      PlaybackSourceInterception(sources: sources, streamFacts: streamFacts, sourceQueryPolicies: sourceQueryPolicies),
    );
    return intercepted.isEmpty ? sources : intercepted;
  }

  Future<List<PlayerSource>> _refreshSources(List<PlayerSource> current) async {
    final resolver = _sourceResolver;
    final committed = commit;
    final room = _room;
    if (resolver == null || committed == null || room == null || _disposed) return const [];

    final fenceRevision = _commitRevision;
    final result = await resolver(sourceRefreshRequestFor(committed));
    if (!canAdoptSourceRefresh(
      disposed: _disposed,
      sameRoom: identical(_room, room),
      revisionMoved: _commitRevision != fenceRevision,
      result: result,
    )) {
      return const [];
    }

    final refreshed = await refreshedPlaybackCommit(
      result,
      committed: committed,
      room: room,
      intercept: (sources) => _intercept(
        sources,
        streamFacts: result.selection?.streamFacts ?? const {},
        sourceQueryPolicies: result.selection?.sourceQueryPolicies ?? const {},
      ),
    );
    if (refreshed.sources.isEmpty) return const [];

    _lastLines = refreshed.lines;
    _publishCommit(
      refreshed.currentUrl,
      refreshed.urls,
      refreshed.qualities,
      refreshed.currentQuality,
      streamFacts: refreshed.streamFacts,
      source: refreshed.ownedSource,
    );
    return refreshed.sources;
  }

  final RxBool isInPip = false.obs;
  final RxBool isPipPreparing = false.obs;
  final RxInt videoPresentationRevision = 0.obs;
  VideoSize? _lastPresentedVideoSize;
  StreamSubscription<bool>? _pipStateSub;

  /// System fullscreen — immersive + orientation lock on mobile, window
  /// fullscreen on desktop. Mirrored from the fullscreen driver, which every
  /// presentation transition routes through; the mirror replaces the deleted
  /// GlobalPlayerState hand-synced flags. Manual writes stay meaningful as
  /// timing aids (the title-bar shell must hide before the native
  /// transition), and the next driver event re-states the truth.
  final RxBool isSystemFullscreen = false.obs;

  /// Widescreen room layout. Pure UI state — the presentation drivers have no
  /// notion of it, so unlike [isSystemFullscreen] this is never mirrored.
  final RxBool isWindowFullscreen = false.obs;

  bool get fullscreenUI => isSystemFullscreen.value || isWindowFullscreen.value;

  void setVideoPresentationVisible(bool visible) => setPresentationVisible(visible);

  Future<void> enablePip() async {
    _pipStateSub ??= windowsPipDriver.onPipChanged.listen((pip) {
      // The pip driver is the authority on whether the presentation is
      // active; without this bridge the room UI never learns the window
      // changed and keeps rendering the full room inside the shrunk frame.
      isInPip.value = pip;
    });
    isPipPreparing.value = true;
    try {
      // The kernel chain forwards requests without lifecycle calls. The
      // mobile path only installs its system-pip implementation and starts
      // observing the platform status stream during initialize(); without it
      // every pip request throws "no system pip implementation" and the
      // Android back gesture silently falls back to leaving the room.
      await windowsPipDriver.initialize();
      // Both platforms size the small window from the video's shape. Mobile
      // refuses to enter PiP at all without a positive size.
      final ratio = currentPresentationAspectRatio;
      windowsPipDriver.onVideoSize((ratio * 1000).round(), 1000);
      final driver = kernel.presentationDriver;
      if (driver != null) {
        await driver.apply(handle?.id ?? PlayerId('pure-live'), PresentationRequest.pip());
      }
    } finally {
      isPipPreparing.value = false;
    }
  }

  /// Leaves picture-in-picture and restores the window.
  Future<void> exitPip() async {
    final driver = kernel.presentationDriver;
    if (driver != null) {
      await driver.apply(handle?.id ?? PlayerId('pure-live'), PresentationRequest.normal());
    }
  }

  Widget buildPiPOverlay({Widget? pictureCover}) => _PipOverlayView(
    facade: this,
    pictureCover: pictureCover,
    danmaku: _activeVideoController != null ? CompactDanmakuOverlay(controller: _activeVideoController) : null,
  );

  double get currentPresentationAspectRatio {
    final size = handle?.combinedSnapshot.geometry.videoSize;
    if (size == null || size.width <= 0 || size.height <= 0) {
      // 尺寸快照还没到时不能一律按 16:9 报：竖屏流会拿到一个横屏 PiP 窗口，
      // contain 缩放后四周全是黑边。声明的比例优先，都没有时按已观察到的
      // 方向（isVerticalVideo 由帧尺寸事件驱动）兜底。
      if (_declaredAspectRatio != null) return _declaredAspectRatio!;
      return isVerticalVideo.value ? 9 / 16 : 16 / 9;
    }
    return size.width / size.height;
  }

  double? _declaredAspectRatio;

  /// Applied once per source, so a reconnect does not seek back to the declared start.
  Duration? _pendingSeekAt;

  void _tryApplyPendingSeek() {
    final pending = _pendingSeekAt;
    if (pending == null || pending <= Duration.zero) return;
    final player = handle;
    if (player == null) return;
    if (player.playback.duration <= pending) return;
    _pendingSeekAt = null;
    unawaited(
      player.seek(pending).catchError((Object error, StackTrace stackTrace) {
        debugPrint('Seek to the declared start failed: $error');
      }),
    );
  }

  VideoSourceOrientation get effectiveVideoOrientation =>
      isVerticalVideo.value ? VideoSourceOrientation.portrait : VideoSourceOrientation.landscape;

  final Rx<VideoGeometrySnapshot> videoGeometryState = Rx<VideoGeometrySnapshot>(const VideoGeometrySnapshot.unknown());

  VideoGeometrySnapshot get videoGeometry => videoGeometryState.value;

  VideoGeometrySnapshot _computeVideoGeometry() {
    final size = handle?.combinedSnapshot.geometry.videoSize;
    if (size == null || size.width <= 0 || size.height <= 0) {
      return const VideoGeometrySnapshot.unknown();
    }
    final width = size.width.toInt();
    final height = size.height.toInt();
    final vertical = height > width;
    final orientation = vertical ? VideoOrientationKind.portrait : VideoOrientationKind.landscape;
    return VideoGeometrySnapshot(
      width: width,
      height: height,
      aspectRatio: width / height,
      orientation: orientation,
      candidateOrientation: orientation,
      stableSampleCount: 1,
      confidence: 1,
      observedAt: DateTime.now(),
    );
  }

  Duration get audioModeSwitchTimeout => const Duration(seconds: 5);

  Widget getVideoWidgetCompat(
    Object fit, {
    List<BoxFit>? fitList,
    Widget? controls,
    bool trackPipSource = false,
    Widget? pictureCover,
    Color? surfaceColor,
    double? videoViewportAspectRatio,
    Object? portraitFullscreenDisplayMode,
  }) {
    final resolved = fit is int
        ? (fitList == null || fitList.isEmpty ? BoxFit.contain : fitList[fit.clamp(0, fitList.length - 1)])
        : fit as BoxFit;
    final video = getVideoWidget(resolved);
    final children = <Widget>[video, ?pictureCover, ?controls];
    if (children.length == 1) return video;
    // expand is load-bearing: a default (loose) Stack sizes itself to the
    // non-positioned child, and in an unbounded ancestor that hands the video
    // infinite constraints — MediaPlayerView's AspectRatio then throws
    // "BoxConstraints forces an infinite width and height" every frame and
    // the room shows nothing.
    return Stack(fit: StackFit.expand, children: children);
  }

  Future<void> close() async {
    Log.i('player: close (room left)');
    _servingRoom = false;
    _resetPictureWatch();
    _cancelIdleRelease();
    await _sourceInterceptor?.release();
    final retire = _retireOnClose;
    _retireOnClose = false;
    if (_useHardStopOnExit() || retire) {
      await _controller.close();
      return;
    }
    // Stop, not pause: the room's stream ends (its connection closes and the
    // engine drops its picture), so the next room - or this one again -
    // never shows the last frame of the room left; only the engine stays.
    await _controller.stop();
    _idleReleaseTimer = Timer(idleReleaseDelay, () {
      _idleReleaseTimer = null;
      if (!_disposed) unawaited(_controller.close());
    });
  }

  /// Between rooms, lets the warm engine go now instead of after
  /// [idleReleaseDelay], so the next room builds one with the current
  /// settings. Does nothing while a room is open.
  Future<void> releaseIdleEngine() async {
    if (_servingRoom || _disposed) return;
    Log.i('player: warm engine released (settings changed between rooms)');
    _cancelIdleRelease();
    _retireOnClose = false;
    await _controller.close();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cancelIdleRelease();
    _stallTimer?.cancel();
    _stallTimer = null;
    _noPictureTimer?.cancel();
    await _sourceInterceptor?.close();
    await _stateSub?.cancel();
    await _playingSub?.cancel();
    await _errorSub?.cancel();
    await _controller.dispose();
    await _stateSubject.close();
    await _playingSubject.close();
    await _errorSubject.close();
    await _commitSubject.close();
    await _loadingSubject.close();
    await _longStallSubject.close();
  }
}

@immutable
class FacadeStreamCommit {
  const FacadeStreamCommit({
    this.revision = 0,
    required this.room,
    List<String>? urls,
    String? currentUrl,
    this.currentLineIndex = 0,
    this.headers = const {},
    this.qualities = const [],
    this.currentQuality = 0,
    Object? source,
    Object? ownedSource,
    this.isAudioOnly = false,
    this.isLiving = true,
    this.dataSource = '',
    List<String>? playUrls,
    this.sourceQueryPolicies = const {},
    this.streamFacts = const {},
    this.hasUseDefaultResolution = true,
  }) : urls = urls ?? playUrls ?? const [],
       currentUrl = currentUrl ?? dataSource,
       ownedSource = source ?? ownedSource;

  final int revision;
  final LiveRoom room;
  final List<String> urls;
  final String currentUrl;
  final int currentLineIndex;
  final Map<String, String> headers;
  final List<LivePlayQuality> qualities;
  final int currentQuality;
  final Object? ownedSource;
  List<String> get linesOrUrls => urls;
  final bool isAudioOnly;
  final bool isLiving;
  final String dataSource;
  final Map<String, HlsSourceQueryPolicy> sourceQueryPolicies;

  final Map<String, LiveStreamFacts> streamFacts;
  final bool hasUseDefaultResolution;

  FacadeStreamCommit copyWith({
    String? dataSource,
    List<String>? playUrls,
    Object? source,
    Object? ownedSource,
    Map<String, HlsSourceQueryPolicy>? sourceQueryPolicies,
    Map<String, LiveStreamFacts>? streamFacts,
    Map<String, String>? headers,
    bool? isAudioOnly,
  }) => FacadeStreamCommit(
    revision: revision,
    room: room,
    urls: playUrls ?? urls,
    currentUrl: dataSource ?? currentUrl,
    currentLineIndex: currentLineIndex,
    headers: headers ?? this.headers,
    qualities: qualities,
    currentQuality: currentQuality,
    ownedSource: source ?? ownedSource ?? this.ownedSource,
    isAudioOnly: isAudioOnly ?? this.isAudioOnly,
    isLiving: isLiving,
    dataSource: dataSource ?? this.dataSource,
    sourceQueryPolicies: sourceQueryPolicies ?? this.sourceQueryPolicies,
    streamFacts: streamFacts ?? this.streamFacts,
    hasUseDefaultResolution: hasUseDefaultResolution,
  );
}

typedef PlaybackSourceCommitSnapshot = FacadeStreamCommit;
typedef PlaybackSourceResolver = Future<PlaybackSourceRefreshResult> Function(PlaybackSourceRefreshRequest request);

extension FacadeStreamCommitLegacy on FacadeStreamCommit {
  List<String> get playUrls => urls;
  String get currentUrl_ => currentUrl;
  Map<String, HlsSourceQueryPolicy> get queryPolicies => sourceQueryPolicies;
  PlaybackSourceQualitySelection? get selection => qualities.isEmpty
      ? null
      : PlaybackSourceQualitySelection(
          qualities: qualities,
          currentQuality: currentQuality,
          sourceQueryPolicies: sourceQueryPolicies,
          streamFacts: streamFacts,
        );
}

@immutable
class PlaybackSourceRefreshRequest {
  const PlaybackSourceRefreshRequest({
    required this.currentLineIndex,
    required this.advanceLine,
    required this.currentUrl,
    this.currentSource,
    this.currentQuality,
  });
  final int currentLineIndex;
  final bool advanceLine;
  final String? currentUrl;
  final Object? currentSource;
  final LivePlayQuality? currentQuality;
}

@immutable
class PlaybackSourceRefreshResult {
  const PlaybackSourceRefreshResult({
    required this.urls,
    required this.preferredLineIndex,
    this.refreshAt,
    this.invalidAt,
    this.selection,
    this.startAt = Duration.zero,
  }) : ownedSource = null;

  const PlaybackSourceRefreshResult.owned({
    required Object? source,
    this.refreshAt,
    this.invalidAt,
    this.selection,
    this.startAt = Duration.zero,
  }) : ownedSource = source,
       urls = const [],
       preferredLineIndex = 0;

  final Object? ownedSource;
  List<String> get linesOrUrls => urls;
  bool get hasSources => ownedSource != null || urls.isNotEmpty;
  final List<String> urls;
  final int preferredLineIndex;
  final DateTime? refreshAt;
  final DateTime? invalidAt;
  final PlaybackSourceQualitySelection? selection;

  final Duration startAt;
}

@immutable
class PlaybackSourceQualitySelection {
  const PlaybackSourceQualitySelection({
    required this.qualities,
    required this.currentQuality,
    this.sourceQueryPolicies = const {},
    this.streamFacts = const {},
    this.declaredAspectRatio,
    this.startAt = Duration.zero,
  });
  final List<LivePlayQuality> qualities;
  final int currentQuality;
  final Map<String, HlsSourceQueryPolicy> sourceQueryPolicies;

  final Map<String, LiveStreamFacts> streamFacts;

  final double? declaredAspectRatio;

  final Duration startAt;
}

/// The desktop/system PiP surface: hover reveals the controls (a large
/// centered play/pause plus corner actions), the video corners are rounded,
/// and the pointer drag hands the window to the native move loop. Touch
/// platforms keep the controls always visible — there is no hover there.
class _PipOverlayView extends StatefulWidget {
  const _PipOverlayView({required this.facade, required this.danmaku, this.pictureCover});

  final LivePlayerFacade facade;
  final Widget? danmaku;

  final Widget? pictureCover;

  @override
  State<_PipOverlayView> createState() => _PipOverlayViewState();
}

class _PipOverlayViewState extends State<_PipOverlayView> {
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _reassertContain();
  }

  void _reassertContain() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.facade.changeVideoFit(BoxFit.contain);
    });
  }

  bool get _isTouchDevice {
    return defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
  }

  // 触屏（移动端）的画中画不显示任何 UI 控件：窗口小，控件只会挡住画面，
  // 系统的 PiP 窗口本身就带播放/暂停和全屏手势。桌面保留 hover 显隐。
  bool get _showControls => !_isTouchDevice && _hovered;

  @override
  Widget build(BuildContext context) {
    final facade = widget.facade;
    // The adapter's viewport fit is shared state across every view of this
    // handle: the fullscreen page may have left it at the user's fit-height
    // preference, and fit-height in a compact window whose shape differs
    // from the video overflows and crops the picture. The compact face
    // always shows the whole picture; re-assert contain on every rebuild
    // (the adapter notifier dedupes no-op writes). Leaving PiP remounts the
    // room's own view, which re-applies the user's preference.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) facade.changeVideoFit(BoxFit.contain);
    });
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          // expand keeps MediaPlayerView off infinite constraints if this
          // Scaffold's body is ever composed inside a loose/unbounded ancestor.
          fit: StackFit.expand,
          children: [
            // Rounded video corners: the window itself is rounded by the
            // desktop backend; the clip keeps the surface corners soft even
            // where the system does not round (older Windows). 移动端的系统
            // PiP 窗口是方的且自己管理外观，别再裁圆角——圆角会切掉画面四角。
            ClipRRect(
              borderRadius: _isTouchDevice ? BorderRadius.zero : BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 触屏端（Android/iOS 系统 PiP）不挂任何手势识别器：Flutter
                  // 一旦消费了拖动，系统的 PiP 窗口就收不到事件，窗口拖不动、
                  // 单击也不会弹出系统的播放/关闭菜单。让系统全权处理。
                  // 桌面小窗没有系统手势，surface 手势是唯一的操作入口。
                  if (_isTouchDevice)
                    facade.getVideoWidget(BoxFit.contain)
                  else
                    GestureDetector(
                      // The video surface stays gesture-first: single tap
                      // toggles playback, double tap leaves PiP, and a drag
                      // hands the pointer to the native caption-drag loop —
                      // the compact window has no title bar, so a
                      // surface-initiated drag is the only way to move it.
                      onDoubleTap: () => unawaited(facade.exitPip()),
                      onTap: facade.togglePlayPause,
                      onPanStart: (_) => unawaited(windowsPipWindow.startDragging()),
                      child: facade.getVideoWidget(BoxFit.contain),
                    ),
                  ?widget.pictureCover,
                  if (widget.danmaku != null) Positioned.fill(child: widget.danmaku!),
                ],
              ),
            ),
            // Hover-revealed center play/pause: large enough to hit from a
            // small floating window without aiming.
            Center(
              child: IgnorePointer(
                ignoring: !_showControls,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: StreamBuilder<bool>(
                    stream: facade.onPlaying,
                    initialData: facade.isPlayingNow,
                    builder: (context, snapshot) {
                      final isPlay = snapshot.data ?? true;
                      return IconButton.filledTonal(
                        iconSize: 56,
                        tooltip: isPlay ? '暂停' : '播放',
                        style: IconButton.styleFrom(backgroundColor: Colors.black45, foregroundColor: Colors.white),
                        icon: Icon(isPlay ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        onPressed: facade.togglePlayPause,
                      );
                    },
                  ),
                ),
              ),
            ),
            // Corner actions share the hover reveal.
            Positioned(
              right: 8,
              top: 8,
              child: IgnorePointer(
                ignoring: !_showControls,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _pipControlButton(
                        icon: Icons.open_in_full_rounded,
                        semanticLabel: '回到直播间',
                        onTap: facade.exitPip,
                      ),
                      const SizedBox(width: 6),
                      _pipControlButton(
                        icon: Icons.close_rounded,
                        semanticLabel: '关闭',
                        onTap: () async {
                          // Leaving the presentation first: closing playback
                          // alone would strand the window in its shrunk
                          // frameless state.
                          await facade.exitPip();
                          await facade.close();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pipControlButton({
    required IconData icon,
    required String semanticLabel,
    required Future<void> Function() onTap,
  }) {
    return IconButton(
      iconSize: 26,
      tooltip: semanticLabel,
      style: IconButton.styleFrom(backgroundColor: Colors.black45, foregroundColor: Colors.white),
      icon: Icon(icon),
      onPressed: () => unawaited(onTap()),
    );
  }
}

String backendIdOfEngine(PlayerEngine engine) => switch (engine) {
  PlayerEngine.mediaKit => kMediaKitPlayerBackendId,
  PlayerEngine.fijk => kIjkPlayerBackendId,
  PlayerEngine.exo => kBetterPlayerBackendId,
};
