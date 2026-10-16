import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// A record of every startup step, in this launch's app log.
///
/// A launch that hangs before the first frame never reaches the app log's own
/// writer: it starts late in startup, and nothing can be opened while the app
/// sits on its launch screen. So the steps are written here line by line and
/// flushed at once, into the same file the app log continues.
///
/// Like every log, the trace follows the log switch: the steps before the
/// settings can be read wait in memory, and [attach] either writes them out
/// or drops them.
abstract final class StartupTrace {
  /// Files earlier builds wrote beside the app log whatever the switch said.
  static const List<String> _legacyFileNames = ['startup.log', 'startup-previous.log'];

  static final Stopwatch _clock = Stopwatch();
  static final List<String> _held = <String>[];
  static File? _file;
  static bool _attached = false;

  /// Starts the clock. Lines are held until [attach].
  static void begin() {
    _clock.start();
    _held.add('Startup ${DateTime.now().toIso8601String()} (pid $pid)');
  }

  /// Once the settings can be read: with the log switch [enabled], the held
  /// lines and every later one go to [file], each flushed at once; with it
  /// off nothing is written. Never throws: without a trace, startup goes on.
  static Future<void> attach({required bool enabled, required Future<File> Function() file}) async {
    if (_attached) return;
    _attached = true;
    final held = List<String>.of(_held);
    _held.clear();
    try {
      final target = await file().timeout(const Duration(seconds: 2));
      final dir = target.parent;
      for (final name in _legacyFileNames) {
        final legacy = File(p.join(dir.path, name));
        if (legacy.existsSync()) legacy.deleteSync();
      }
      if (!enabled) return;
      if (!dir.existsSync()) dir.createSync(recursive: true);
      target.writeAsStringSync(held.map(_format).join(), mode: FileMode.append, flush: true);
      _file = target;
    } catch (_) {
      _file = null;
    }
  }

  static String _format(String line) => '[STARTUP] $line\r\n';

  /// Stops writing the trace: its file was deleted (日志 › 清空日志) and a
  /// late line must not bring it back.
  static void detach() => _file = null;

  /// Appends [message] with the time since [begin].
  static void mark(String message) {
    final line = '${_clock.elapsedMilliseconds.toString().padLeft(6)} ms  $message';
    if (!_attached) {
      _held.add(line);
      return;
    }
    final file = _file;
    if (file == null) return;
    try {
      file.writeAsStringSync(_format(line), mode: FileMode.append, flush: true);
    } catch (_) {
      // A trace that cannot be written must not stop the app.
    }
  }

  /// Runs [body] between a start and an end line, so a step that never
  /// returns is the last one started.
  static Future<T> step<T>(String name, Future<T> Function() body) async {
    mark('start  $name');
    try {
      final result = await body();
      mark('done   $name');
      return result;
    } catch (error) {
      mark('failed $name: $error');
      rethrow;
    }
  }
}
