import 'dart:io';
import 'dart:async';
import 'dart:developer' as developer;

import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:pure_live/core/index.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pure_live/core/platform/app_path_manager.dart';
import 'package:pure_live/core/config/log_controller.dart';

class Log {
  static const int maxDebugEntries = 2000;
  static LogFileWriter? _logFileWriter;
  static final List<DebugLogModel> _allLogs = [];
  static int _statusGeneration = 0;
  static List<DebugLogModel> get allLogs => List<DebugLogModel>.unmodifiable(_allLogs);

  static String _two(int value) => value.toString().padLeft(2, '0');

  /// `HH:mm:ss`, formatted by hand: intl's DateFormat needs the locale data
  /// easy_localization loads when its widget mounts, and a DateFormat built
  /// before that (logging resumed at launch) threw and switched logging off.
  static String formatLogTime(DateTime time) => '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}';

  /// `yyyy-MM-dd_HH-mm-ss`, for file names.
  static String fileTimestamp(DateTime time) =>
      '${time.year}-${_two(time.month)}-${_two(time.day)}_${_two(time.hour)}-${_two(time.minute)}-${_two(time.second)}';

  /// Every buffered entry as text, one line per entry, for copying or sharing.
  static String exportText() {
    final buffer = StringBuffer();
    for (final entry in _allLogs) {
      buffer.writeln('${formatLogTime(entry.datetime)}  ${entry.content}');
    }
    return buffer.toString();
  }

  static bool get _localLoggingEnabled => Get.isRegistered<LogController>() && LogController.to.enableLog;

  /// The file the writer is appending to, if logging is on.
  static String? get activeLogFilePath => _logFileWriter?.path;

  /// Writes the lines still waiting in the writer's buffer.
  static Future<void> flush() => _logFileWriter?.flush() ?? Future<void>.value();

  static void clearDebugLogs() => _allLogs.clear();

  static bool _debugPrintCaptured = false;

  /// Mirrors `debugPrint` output into the local log while it is enabled. Most
  /// diagnostics in the app and its plugins go through `debugPrint`, so without
  /// this the log file stays nearly empty.
  static void captureDebugPrint() {
    if (_debugPrintCaptured) return;
    _debugPrintCaptured = true;
    final DebugPrintCallback original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      original(message, wrapWidth: wrapWidth);
      if (message == null) return;
      addDebugLog(message);
      writeLog(message, Level.debug);
    };
  }

  static void dispose() {
    _statusGeneration++;
    final writer = _logFileWriter;
    _logFileWriter = null;
    if (writer != null) unawaited(writer.close());
  }

  static Future<bool> setEnabled(bool enabled) async {
    final generation = ++_statusGeneration;
    final previous = _logFileWriter;
    _logFileWriter = null;
    if (previous != null) await previous.close();
    if (generation != _statusGeneration) return false;
    if (!enabled) return true;

    final writer = LogFileWriter();
    if (!await writer.init()) {
      await writer.close();
      return false;
    }
    if (generation != _statusGeneration) {
      await writer.close();
      return false;
    }
    _logFileWriter = writer;
    return true;
  }

  static void writeLog(Object content, [Level level = Level.info]) {
    if (!_localLoggingEnabled || _logFileWriter == null) return;
    _logFileWriter?.write("[${level.name.toUpperCase()}] $_currentTime：$content");
  }

  /// `dart:developer`'s `log`, also kept in the app log (the in-app page and,
  /// while the switch is on, the file). `developer.log` alone reaches only an
  /// attached debugger, so a release build lost every one of these lines.
  /// An entry with an error, a stack or `level >= 1000` counts as an error,
  /// `level >= 900` as a warning.
  static void dev(String message, {String name = '', int level = 0, Object? error, StackTrace? stackTrace}) {
    developer.log(message, name: name, level: level, error: error, stackTrace: stackTrace);
    final line = StringBuffer(name.isEmpty ? message : '[$name] $message');
    if (error != null && !message.contains('$error')) line.write(': $error');
    if (stackTrace != null) line.write('\n$stackTrace');
    final failed = level >= 1000 || error != null || stackTrace != null;
    final warning = !failed && level >= 900;
    addDebugLog(line.toString(), failed ? Colors.red : (warning ? Colors.pink : null));
    writeLog(line.toString(), failed ? Level.error : (warning ? Level.warning : Level.info));
  }

  static void addDebugLog(String content, [Color? color]) {
    String processedContent = content;
    if (content.contains("请求响应")) {
      processedContent = content.split("\n").join('\n💡 ');
    }

    _allLogs.add(DebugLogModel(DateTime.now(), processedContent, color: color));
    final overflow = _allLogs.length - maxDebugEntries;
    if (overflow > 0) {
      _allLogs.removeRange(0, overflow);
    }
  }

  static final Logger logger = Logger(
    filter: ProductionFilter(),
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.none,
    ),
    output: kReleaseMode ? _NullOutput() : ConsoleOutput(),
  );

  static void d(String message) {
    final localLoggingEnabled = _localLoggingEnabled;
    addDebugLog(message, Colors.orange);
    if (!kReleaseMode) {
      logger.d(message);
    }
    if (localLoggingEnabled) writeLog(message, Level.debug);
  }

  static void i(String message) {
    final localLoggingEnabled = _localLoggingEnabled;
    addDebugLog(message, Colors.blue);
    if (!kReleaseMode) {
      logger.i(message);
    }
    if (localLoggingEnabled) writeLog(message, Level.info);
  }

  static void e(String message, StackTrace stackTrace) {
    final localLoggingEnabled = _localLoggingEnabled;
    addDebugLog('$message\r\n\r\n$stackTrace', Colors.red);
    if (!kReleaseMode) {
      logger.e(message, stackTrace: stackTrace);
    }
    if (localLoggingEnabled) writeLog("$message\n$stackTrace", Level.error);
  }

  static void w(String message) {
    final localLoggingEnabled = _localLoggingEnabled;
    addDebugLog(message, Colors.pink);
    if (!kReleaseMode) {
      logger.w(message);
    }
    if (localLoggingEnabled) writeLog(message, Level.warning);
  }

  static void logPrint(dynamic obj) {
    final String content = obj.toString();
    final localLoggingEnabled = _localLoggingEnabled;
    addDebugLog(content, Colors.red);
    if (!kReleaseMode) {
      if (kDebugMode) {
        print(content);
      }
    }
    if (localLoggingEnabled) writeLog(content, Level.info);
  }

  static String get _currentTime => formatLogTime(DateTime.now());
}

class _NullOutput extends LogOutput {
  @override
  void output(OutputEvent event) {}
}

class LogFileWriter {
  final String _fileName;
  RandomAccessFile? _file;
  String? _path;
  bool _isInitialized = false;
  // Lines wait here and reach the disk once a second, so the file stays
  // current while the app runs instead of only when logging is switched off.
  final StringBuffer _pending = StringBuffer();
  Timer? _drainTimer;
  bool _draining = false;

  LogFileWriter() : _fileName = '${Log.fileTimestamp(DateTime.now())}.log';

  Future<bool> init() async {
    if (_isInitialized) return true;

    try {
      final logDir = await resolveLogDirectory();
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }

      var logFile = File("${logDir.path}/$_fileName");
      _file = await logFile.open(mode: FileMode.append);
      _path = logFile.path;
      _isInitialized = true;
      _drainTimer = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_drain()));

      await _writeSystemInfo();
      return true;
    } catch (e, stackTrace) {
      debugPrint('Init log file failed: $e\n$stackTrace');
      return false;
    }
  }

  static Future<Directory> resolveLogDirectory() async {
    if (Platform.isAndroid) {
      final dir = await getDownloadsDirectory();
      if (dir == null) {
        throw const FileSystemException('Downloads directory is unavailable');
      }
      return Directory(AppPathManager.logFilesDirectoryPath(p.join(dir.path, AppPathManager.dirLogs)));
    }
    return AppPathManager().logFilesDir;
  }

  String? get path => _path;

  Future<void> flush() => _drain();

  void write(String content) {
    if (!_isInitialized) return;
    _pending.write("$content\r\n");
  }

  Future<void> _drain() async {
    final file = _file;
    if (_draining || file == null || _pending.isEmpty) return;
    _draining = true;
    final chunk = _pending.toString();
    _pending.clear();
    try {
      await file.writeString(chunk);
      await file.flush();
    } catch (_) {
      // Dropped on purpose: reporting through Log or debugPrint would feed
      // the failure back into this writer.
    } finally {
      _draining = false;
    }
  }

  Future<void> close() async {
    _drainTimer?.cancel();
    _drainTimer = null;
    for (var i = 0; _draining && i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await _drain();
    _isInitialized = false;
    final file = _file;
    _file = null;
    try {
      await file?.close();
    } catch (_) {}
  }

  Future<void> _writeSystemInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final deviceInfo = DeviceInfoPlugin();

      _pending.write("=========================================================\r\n");
      _pending.write("  ____  _   _ ____  _____   _     _____     _______ \r\n");
      _pending.write(" |  _ \\| | | |  _ \\| ____| | |   |_ _\\ \\   / / ____|\r\n");
      _pending.write(" | |_) | | | | |_) |  _|   | |    | | \\ \\ / /|  _|  \r\n");
      _pending.write(" |  __/| |_| |  _ <| |___  | |___ | |  \\ V / | |___ \r\n");
      _pending.write(" |_|    \\___/|_| \\_\\_____| |_____|___|  \\_/  |_____|\r\n");
      _pending.write("=========================================================\r\n");
      _pending.write(" 🕒 Current Time : ${DateTime.now()}\r\n");
      _pending.write(" 📱 Platform     : ${Platform.operatingSystem}\r\n");
      _pending.write(" ⚙️ OS Version   : ${Platform.operatingSystemVersion}\r\n");
      _pending.write(" 🌐 Locale       : ${Platform.localeName}\r\n");
      _pending.write(" 📦 App Version  : v${packageInfo.version} (${packageInfo.buildNumber})\r\n");

      String model = "Unknown";
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        model = "${info.brand} ${info.model} (API ${info.version.sdkInt})";
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        model = "${info.name} ${info.systemVersion}";
      } else if (Platform.isLinux) {
        final info = await deviceInfo.linuxInfo;
        model = "${info.name} (${info.versionId})";
      } else if (Platform.isMacOS) {
        final info = await deviceInfo.macOsInfo;
        model = "${info.computerName} (macOS ${info.osRelease})";
      } else if (Platform.isWindows) {
        final info = await deviceInfo.windowsInfo;
        model = "${info.computerName} (Build ${info.buildNumber})";
      }

      _pending.write(" 💻 Device Model : $model\r\n");
      _pending.write("=========================================================\r\n\r\n");
      await _drain();
    } catch (e, stackTrace) {
      Log.e("Init log file failed: $e", stackTrace);
    }
  }
}

class DebugLogModel {
  final String content;
  final DateTime datetime;
  final Color? color;
  DebugLogModel(this.datetime, this.content, {this.color});
}
