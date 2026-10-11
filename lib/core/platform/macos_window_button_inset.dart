import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// Height of the macOS title bar strip the window buttons sit in.
///
/// The window uses a hidden title bar with full-size content, so Flutter draws
/// under the close/minimise/zoom buttons. Treating that strip like a system
/// inset (the way a phone's status bar is) lets every app bar, navigation rail
/// and player bar extend its background behind the buttons while its controls
/// start below them.
const double macOSWindowButtonInset = 28;

/// Reports the window-button strip to the subtree as top padding.
///
/// Widgets that already respect [MediaQuery.paddingOf] — [AppBar], [SafeArea],
/// the player's top bar — avoid the buttons without any page-level change. In
/// native fullscreen macOS hides the buttons, so the inset is removed there.
class MacOSWindowButtonInset extends StatefulWidget {
  const MacOSWindowButtonInset({super.key, required this.child});

  final Widget child;

  @override
  State<MacOSWindowButtonInset> createState() => _MacOSWindowButtonInsetState();
}

class _MacOSWindowButtonInsetState extends State<MacOSWindowButtonInset> with WindowListener {
  bool _fullScreen = false;

  bool get _enabled => Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    if (!_enabled) return;
    windowManager.addListener(this);
    windowManager.isFullScreen().then((value) {
      if (mounted && value != _fullScreen) setState(() => _fullScreen = value);
    }).catchError((Object _) {});
  }

  @override
  void dispose() {
    if (_enabled) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _fullScreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _fullScreen = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled || _fullScreen) return widget.child;
    final media = MediaQuery.of(context);
    EdgeInsets withInset(EdgeInsets insets) =>
        insets.copyWith(top: insets.top < macOSWindowButtonInset ? macOSWindowButtonInset : insets.top);
    return MediaQuery(
      data: media.copyWith(padding: withInset(media.padding), viewPadding: withInset(media.viewPadding)),
      child: widget.child,
    );
  }
}
