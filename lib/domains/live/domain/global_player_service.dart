import 'dart:io';

import 'package:pure_live/core/player/core/playback_lifecycle_coordinator.dart';
import 'package:pure_live/core/player/core/live_audio_service.dart';
import 'package:pure_live/core/player/core/live_playback_hooks.dart';
import 'package:pure_live/domains/live/domain/live_player_facade.dart';
import 'package:pure_live/domains/live/domain/playback_source_interceptor.dart';
import 'package:pure_live/core/player/models/player_engine.dart';
import 'package:pure_live/core/logging/app_log.dart';

class GlobalPlayerService {
  GlobalPlayerService._();

  static final GlobalPlayerService instance = GlobalPlayerService._();

  static PlaybackSourceInterceptor Function()? sourceInterceptorFactory;

  late final LivePlayerFacade playerManager;

  late final PlaybackLifecycleCoordinator lifecycle;

  LivePlayerFacade get player => playerManager;
  bool _initialized = false;
  Future<void>? _initializationFuture;

  bool get initialized => _initialized;

  Future<void> initialize({PlayerEngine defaultEngine = PlayerEngine.mediaKit}) async {
    if (_initialized) return;
    final inFlight = _initializationFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final operation = _initialize(defaultEngine);
    _initializationFuture = operation;
    try {
      await operation;
    } finally {
      if (identical(_initializationFuture, operation)) _initializationFuture = null;
    }
  }

  Future<void> _initialize(PlayerEngine defaultEngine) async {
    playerManager = LivePlayerFacade(defaultEngine: defaultEngine, sourceInterceptor: sourceInterceptorFactory?.call());
    // Without background play, a room the app leaves is paused (after the
    // coordinator's short delay) and resumed on return. Phones only: on a
    // desktop, minimizing the window must not pause. media_kit's Video
    // widget used to do this pause itself; it no longer does (media_core
    // 96fcde9), because with background play on it paused and the room was
    // resumed at once, cutting the sound for about a second.
    final mobile = Platform.isAndroid || Platform.isIOS;
    lifecycle = PlaybackLifecycleCoordinator(
      pauseForLifecycle: () async => mobile ? await playerManager.pauseForLifecycle() : null,
      resumeFromLifecycle: (token) async => mobile && await playerManager.resumeFromLifecycle(token),
      shouldContinueInBackground: () => LiveAudioService.shouldContinueInBackground,
      isAudioOnly: () => playerManager.desiredAudioOnlyMode,
      commitAudioOnlyPowerSaving: () => playerManager.setAudioOnly(true),
      prepareAudioOnlyVideoRestore: () => playerManager.setAudioOnly(false),
    )..start();
    // A recording opened over a live room pauses it first (recorder domain).
    LivePlaybackHooks.pauseIfPlaying = () async {
      if (playerManager.isPlayingNow) await playerManager.pause();
    };
    _initialized = true;
    Log.dev("GlobalPlayerService: kernel facade ready.", name: "GlobalPlayerService");
  }

  Future<void> dispose() async {
    if (!_initialized) return;
    await lifecycle.dispose();
    await playerManager.dispose();
    _initialized = false;
    Log.dev("GlobalPlayerService: Disposed.", name: "GlobalPlayerService");
  }
}
