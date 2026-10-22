import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:pure_live/core/config/display_mode_service.dart';
import 'package:pure_live/core/utils/latest_async_value_queue.dart';

/// Android: keeps the display's highest compatible refresh rate requested
/// while the app is in the foreground.
///
/// Without a request Android picks the window's rate itself, and on many
/// 90/120/144 Hz devices that is 60 Hz for an app showing video: the floating
/// danmaku, which follows the display, then ran at 60 FPS whatever the screen
/// could do. Leaving the app releases the request.
class HighRefreshRateScope extends StatefulWidget {
  const HighRefreshRateScope({super.key, required this.child});

  final Widget child;

  @override
  State<HighRefreshRateScope> createState() => _HighRefreshRateScopeState();
}

class _HighRefreshRateScopeState extends State<HighRefreshRateScope> with WidgetsBindingObserver {
  static final LatestAsyncValueQueue<bool> _transitions = LatestAsyncValueQueue<bool>(
    (high) async => DisplayModeService.setHighRefreshRate(high),
  );

  bool? _requestedHigh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _request(true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android PiP is visible while Flutter reports `inactive`. Keep the
    // request there so PiP danmaku and the native surface agree; hidden,
    // paused and detached states release it.
    _request(state == AppLifecycleState.resumed || state == AppLifecycleState.inactive);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _request(false);
    super.dispose();
  }

  void _request(bool high) {
    if (_requestedHigh == high) return;
    _requestedHigh = high;
    unawaited(_transitions.submit(high));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
