import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// A record of every startup step, written straight to disk.
///
/// A launch that hangs before the first frame never reaches the app log: the
/// log writer starts late in startup, and nothing can be opened while the app
/// sits on its launch screen. This file is written line by line and flushed
/// at once, so after such a launch the next one finds where it stopped:
/// `startup.log` is the current launch, `startup-previous.log` the one before,
/// both listed among the log files on the log page.
abstract final class StartupTrace {
  static const String currentFileName = 'startup.log';
  static const String previousFileName = 'startup-previous.log';

  static final Stopwatch _clock = Stopwatch();
  static File? _file;

  /// Opens the trace in [directory], keeping the last launch's trace as
  /// [previousFileName]. Never throws: without a trace, startup goes on.
  static Future<void> begin(Future<Directory> Function() directory) async {
    _clock.start();
    try {
      final dir = await directory().timeout(const Duration(seconds: 2));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final current = File(p.join(dir.path, currentFileName));
      if (current.existsSync()) current.renameSync(p.join(dir.path, previousFileName));
      current.writeAsStringSync('Startup ${DateTime.now().toIso8601String()} (pid $pid)\n', flush: true);
      _file = current;
    } catch (_) {
      _file = null;
    }
  }

  /// Appends [message] with the time since [begin].
  static void mark(String message) {
    final file = _file;
    if (file == null) return;
    try {
      file.writeAsStringSync(
        '${_clock.elapsedMilliseconds.toString().padLeft(6)} ms  $message\n',
        mode: FileMode.append,
        flush: true,
      );
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
