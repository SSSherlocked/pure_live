import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// How the phone is physically held, for 横屏自动全屏.
enum HeldOrientation { portrait, landscape }

/// Android: reports when the phone settles into portrait or landscape while
/// the system's auto-rotate is on (`DeviceOrientationChannel` in the host).
///
/// A room's normal layout is locked to portrait, so Flutter never sees the
/// phone turn; this reads the orientation sensor instead. The sensor runs
/// only while someone holds a [watch] (and the app is in front).
class DeviceOrientationWatcher {
  DeviceOrientationWatcher._();

  static final DeviceOrientationWatcher instance = DeviceOrientationWatcher._();
  static const MethodChannel _channel = MethodChannel('pure_live/device_orientation');

  final StreamController<HeldOrientation> _changes = StreamController<HeldOrientation>.broadcast();
  int _watchers = 0;
  bool _handlerInstalled = false;

  Stream<HeldOrientation> get changes => _changes.stream;

  /// Starts the sensor for the caller; the returned callback stops it again
  /// (once all callers did).
  VoidCallback watch() {
    if (!Platform.isAndroid) return () {};
    _installHandler();
    if (_watchers++ == 0) unawaited(_invoke('start'));
    var released = false;
    return () {
      if (released) return;
      released = true;
      if (--_watchers == 0) unawaited(_invoke('stop'));
    };
  }

  void _installHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'orientation') return;
      final held = switch (call.arguments) {
        'portrait' => HeldOrientation.portrait,
        'landscape' => HeldOrientation.landscape,
        _ => null,
      };
      if (held != null) _changes.add(held);
    });
  }

  Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // No host channel (tests, other embeddings).
    } on PlatformException {
      // The sensor is a convenience; nothing to recover.
    }
  }
}
