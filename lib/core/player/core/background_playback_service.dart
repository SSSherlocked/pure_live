import 'dart:io';

import 'package:flutter/services.dart';
import 'package:media_core_mediasession/media_core_mediasession.dart';
import 'package:pure_live/core/utils/latest_async_value_queue.dart';

/// What a room playing away from the app holds on to on Android: the media
/// notification's foreground service (held "playing" through the media
/// session) and the CPU/Wi-Fi locks.
///
/// Both follow one switch, [setForegroundHold], driven by the room's
/// `BackgroundPlaybackKeeper`: on while the room plays, reconnects, waits for
/// its broadcast or for a call away from the app; off in front of the app and
/// after the user's own pause. Android 12 and later refuse to start the
/// foreground service again from the background, so it must never drop in
/// between.
class BackgroundPlaybackService {
  static const _channel = MethodChannel('pure_live/background_playback');
  static bool sleepSessionActive = false;
  static bool audioOnlySessionActive = false;
  static bool? _appliedKeepAlive;
  static bool _foregroundHeld = false;
  static final LatestAsyncValueQueue<bool> _keepAliveTransitions = LatestAsyncValueQueue<bool>(_applyKeepAlive);

  /// Whether the foreground hold is on ([setForegroundHold]).
  static bool get foregroundHeld => _foregroundHeld;

  /// Holds (or lets go of) the media notification's foreground service and
  /// the CPU/Wi-Fi locks. Repeats are ignored.
  static Future<void> setForegroundHold(bool hold) async {
    if (_foregroundHeld == hold) return;
    _foregroundHeld = hold;
    // Synchronous on purpose: the session must say "playing" before the
    // player's next state reaches the notification.
    MediaSessionBootstrap.current?.setForegroundHold(hold);
    await setKeepAlive(hold);
  }

  /// Routes the notification's / lock screen's pause and stop to [listener]
  /// (the room that holds the foreground service).
  static void setRemotePauseListener(void Function() listener) {
    MediaSessionBootstrap.current?.onRemotePause = listener;
  }

  /// Removes [listener] when it is still the one installed.
  static void clearRemotePauseListener(void Function() listener) {
    final driver = MediaSessionBootstrap.current;
    if (driver != null && driver.onRemotePause == listener) driver.onRemotePause = null;
  }

  static Future<void> setKeepAlive(bool enabled) async {
    if (!Platform.isAndroid) return;
    if (!_keepAliveTransitions.isRunning && _appliedKeepAlive == enabled) return;
    await _keepAliveTransitions.submit(enabled);
  }

  static Future<void> _applyKeepAlive(bool enabled) async {
    if (_appliedKeepAlive == enabled) return;
    try {
      await _channel.invokeMethod<void>('setKeepAlive', {'enabled': enabled});
      _appliedKeepAlive = enabled;
    } on PlatformException {
      // Older installations do not expose this channel yet.
      _appliedKeepAlive = enabled;
    }
  }
}
