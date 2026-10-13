import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:pure_live/core/storage/hive_rx.dart';
import 'package:pure_live/core/logging/app_log.dart';
import 'package:pure_live/get/get.dart';
import 'package:media_core_logging/media_core_logging.dart' as mlog;
import 'package:pure_live/core/player/kernel/player_kernel_service.dart';

typedef LogStatusApplier = Future<bool> Function(bool enabled);

/// A service, not a page controller: the first `Get.find` happens on the
/// backup page, and GetX's smart management deleted a route-linked controller
/// when that page closed, which disposed the log writer mid-session and reset
/// the switch. The switch itself is kept in Hive (local only, not backed up:
/// it is a diagnostic for this device) so logging resumes on the next launch,
/// which is what a cold-start problem needs.
class LogController extends GetxService {
  LogController({LogStatusApplier? applyLogStatus}) : _applyLogStatus = applyLogStatus ?? Log.setEnabled;

  static const String enableLocalLogKey = 'enableLocalLog';

  static LogController get to => Get.find<LogController>();
  final LogStatusApplier _applyLogStatus;

  // The endpoint belongs to the current HttpServer instance. Persisting it
  // makes the next process advertise a dead port before logging is enabled.
  final RxString serverAddress = ''.obs;
  final RxInt serverPort = 0.obs;

  final RxBool storedEnableLog = hiveBool(enableLocalLogKey, false);
  final RxBool _isApplyingLogStatus = false.obs;
  final RxString _logStatusKey = ''.obs;
  Worker? _logStatusWorker;
  Future<bool>? _activeOperation;
  bool? _pendingTarget;
  bool? _internalWrite;
  bool _lastConfirmedEnabled = false;
  Timer? _kernelLogTimer;
  int _kernelLogCursor = 0;

  static Function(Level, String)? onPrintLog;

  @override
  void onInit() {
    super.onInit();
    _logStatusWorker = ever<bool>(storedEnableLog, (value) {
      if (_internalWrite == value) {
        _internalWrite = null;
        return;
      }
      unawaited(_setLoggingEnabled(value));
    });
    // The kernel's (mpv) lines join the in-app log whether or not a file is
    // being written.
    _startKernelLogPump();
    // Nothing is running yet: a switch left on resumes logging now, and a
    // failure to do so turns the switch off again (the usual failure path).
    if (storedEnableLog.v) unawaited(_setLoggingEnabled(true));
  }

  Future<bool> _setLoggingEnabled(bool enabled) {
    _pendingTarget = enabled;
    final active = _activeOperation;
    if (active != null) {
      return active.then((_) => _lastConfirmedEnabled == enabled && _logStatusKey.v.isEmpty);
    }

    late final Future<bool> operation;
    operation = _drainStatusRequests().whenComplete(() {
      if (identical(_activeOperation, operation)) _activeOperation = null;
    });
    _activeOperation = operation;
    return operation.then((_) => _lastConfirmedEnabled == enabled && _logStatusKey.v.isEmpty);
  }

  Future<bool> _drainStatusRequests() async {
    if (!isClosed) _isApplyingLogStatus.v = true;
    var result = true;
    try {
      while (_pendingTarget != null) {
        final target = _pendingTarget!;
        _pendingTarget = null;
        result = await _applyStatusTarget(target);
      }
      return result;
    } finally {
      if (!isClosed) _isApplyingLogStatus.v = false;
    }
  }

  Future<bool> _applyStatusTarget(bool enabled) async {
    final previous = _lastConfirmedEnabled;
    try {
      if (!await _applyLogStatus(enabled)) {
        Log.addDebugLog('Local log file could not be ${enabled ? 'enabled' : 'disabled'}', Colors.red);
        return _recordFailure(previous);
      }
      _commitVerifiedState(enabled);
      if (!enabled) _clearRuntimeEndpoint();
      if (!isClosed) _logStatusKey.v = '';
      return true;
    } catch (error, stackTrace) {
      final action = enabled ? 'enabled' : 'disabled';
      Log.addDebugLog('Local log file could not be $action: $error\n$stackTrace', Colors.red);
      return _recordFailure(previous);
    }
  }

  void _startKernelLogPump() {
    _stopKernelLogPump();
    _drainKernelLogs();
    _kernelLogTimer = Timer.periodic(const Duration(seconds: 2), (_) => _drainKernelLogs());
  }

  void _stopKernelLogPump() {
    _kernelLogTimer?.cancel();
    _kernelLogTimer = null;
  }

  void _drainKernelLogs() {
    final ring = PlayerKernelService.logRing;
    if (ring == null) return;
    final records = ring.records;
    if (_kernelLogCursor > records.length) {
      _kernelLogCursor = 0;
    }
    while (_kernelLogCursor < records.length) {
      final record = records[_kernelLogCursor++];
      final color = switch (record.level) {
        mlog.LogLevel.error => Colors.redAccent,
        mlog.LogLevel.warning => Colors.orangeAccent,
        _ => null,
      };
      final line = '[kernel:${record.category.name}] ${record.message}';
      Log.addDebugLog(line, color);
      Log.writeLog(line, switch (record.level) {
        mlog.LogLevel.error => Level.error,
        mlog.LogLevel.warning => Level.warning,
        _ => Level.info,
      });
    }
  }

  bool _recordFailure(bool previous) {
    _commitVerifiedState(previous);
    if (!previous) _clearRuntimeEndpoint();
    if (!isClosed) _logStatusKey.v = 'local_log_apply_failed';
    return false;
  }

  void _commitVerifiedState(bool enabled) {
    _lastConfirmedEnabled = enabled;
    if (isClosed || storedEnableLog.v == enabled) return;
    _internalWrite = enabled;
    storedEnableLog.v = enabled;
  }

  void _clearRuntimeEndpoint() {
    if (serverAddress.v.isNotEmpty) serverAddress.v = '';
    if (serverPort.v != 0) serverPort.v = 0;
  }

  @override
  void onClose() {
    _stopKernelLogPump();
    _logStatusWorker?.dispose();
    _logStatusWorker = null;
    _pendingTarget = null;
    Log.dispose();
    super.onClose();
  }

  void updateServerInfo(String address, int port) {
    serverAddress.value = address;
    serverPort.value = port;
  }

  bool get enableLog => storedEnableLog.v;
}

extension LogControllerTransactions on LogController {
  RxBool get isApplyingLogStatus => _isApplyingLogStatus;

  RxString get logStatusKey => _logStatusKey;

  Future<bool> setLoggingEnabled(bool enabled) => _setLoggingEnabled(enabled);
}
