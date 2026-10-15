import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart' show Colors;
import 'package:logger/logger.dart' show Level;
import 'package:media_core_media_kit/media_core_media_kit.dart' as mk;
import 'package:pure_live/core/logging/app_log.dart';
import 'package:pure_live/core/player/kernel/media_kit_live_properties.dart';

final Expando<StreamSubscription<mk.PlayerLog>> _forwarders = Expando<StreamSubscription<mk.PlayerLog>>();

/// Copies mpv's log into the app log (the in-app page and the log file) as
/// well as the developer console. mpv is the only witness of what a stream
/// URL did (connect, 403, time out, demux), and `developer.log` alone never
/// reached a release build's log.
void attachMpvLogForwarder(mk.Player player) {
  if (_forwarders[player] != null) return;
  final verbose = MediaKitLiveProperties.mpvVerboseLog;
  _forwarders[player] = player.stream.log.listen((entry) {
    developer.log('${entry.prefix}/${entry.level}: ${entry.text}', name: 'mpv');
    final line = '[mpv:${entry.prefix}] ${entry.text}';
    switch (entry.level) {
      case 'fatal':
      case 'error':
        Log.addDebugLog(line, Colors.red);
        Log.writeLog(line, Level.error);
      case 'warn':
        Log.addDebugLog(line, Colors.pink);
        Log.writeLog(line, Level.warning);
      case 'info':
        Log.addDebugLog(line, Colors.blue);
        Log.writeLog(line, Level.info);
      case 'v' when verbose:
        // The log file only, not the in-app page.
        Log.writeLog(line, Level.debug);
      default:
        // debug / trace: too chatty for the app log.
        break;
    }
  });
}
