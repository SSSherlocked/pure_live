import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' show Color, Colors;
import 'package:flutter/services.dart';
import 'package:logger/logger.dart' show Level;
import 'package:pure_live/core/logging/app_log.dart';

/// Android's other playback engines log only to logcat: ijkplayer (IJKMEDIA,
/// with ffmpeg's output), ExoPlayer and the platform decoders. The host reads
/// this process's lines from them (NativeLogPlugin.kt) and they join the app
/// log here, so an ijk or Exo start is as visible as an mpv one.
abstract final class NativeLogBridge {
  static const EventChannel _channel = EventChannel('pure_live/native_log');

  // `-v tag` lines: `P/TAG     : message`.
  static final RegExp _line = RegExp(r'^([VDIWEFA])/([^:]*?)\s*: ?(.*)$');

  static StreamSubscription<dynamic>? _subscription;

  static void start() {
    if (!Platform.isAndroid || _subscription != null) return;
    _subscription = _channel.receiveBroadcastStream().listen(
      _onBatch,
      onError: (Object error) => Log.dev('Native log stream failed: $error', name: 'NativeLog', level: 900),
    );
  }

  static void stop() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  static void _onBatch(dynamic batch) {
    if (batch is! List) return;
    for (final raw in batch) {
      if (raw is! String) continue;
      final match = _line.firstMatch(raw);
      if (match == null) continue;
      final tag = match.group(2)!.trim();
      // fijkplayer's Dart lines arrive under the Flutter tag.
      final line = '[native:${tag == 'flutter' ? 'fijk' : tag}] ${match.group(3)}';
      final (Color? color, Level level) = switch (match.group(1)) {
        'E' || 'F' || 'A' => (Colors.red, Level.error),
        'W' => (Colors.pink, Level.warning),
        _ => (null, Level.info),
      };
      Log.addDebugLog(line, color);
      Log.writeLog(line, level);
    }
  }
}
