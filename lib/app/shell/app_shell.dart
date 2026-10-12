import 'dart:io';

import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/platform/platform_utils.dart';
import 'package:pure_live/core/platform/desktop_manager.dart';
import 'package:pure_live/core/platform/macos_window_button_inset.dart';
import 'package:pure_live/domains/wallpaper/presentation/app_background.dart';

/// Everything the app paints around its pages, in one place.
///
/// [child] is the app's Router. Every layer here must keep one widget shape
/// for the life of the process: a layer that appears, disappears or changes
/// type when some state flips (fullscreen, a wallpaper, a setting) remounts the
/// Router, and a fresh Router re-navigates to the current location - that
/// pushed a second live room on every fullscreen switch. So platform choices
/// are made once (they never change at runtime) and state-driven layers change
/// only what they paint, never their structure.
///
/// From the outside in:
/// - text scale for the whole app;
/// - the wallpaper behind everything, title bar included ([AppBackgroundLayer]);
/// - window chrome: the Windows/Linux title bar, or the macOS inset that keeps
///   content clear of the traffic-light buttons;
/// - the page canvas made transparent over a wallpaper, with the Material UI
///   theme bridged in ([WallpaperCanvasTransparency]);
/// - Android's adaptive refresh-rate scope;
/// - the Router.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.textScaleFactor, required this.child});

  final double textScaleFactor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    Widget content = child ?? const SizedBox.shrink();
    if (Platform.isAndroid) {
      content = AdaptiveRefreshRateScope(mode: SettingsService.to.app.refreshRateMode, child: content);
    }
    // The canvas transparency stays inside the title bar, so the chrome reads
    // the real theme colours; the wallpaper below wraps the title bar too, so
    // the picture reaches the top edge of the window.
    content = WallpaperCanvasTransparency(child: MaterialUiThemeBridge(child: content));
    if (PlatformUtils.isDesktopNotMac) {
      content = DesktopManager.buildWithTitleBar(content);
    } else if (PlatformUtils.isMacOS) {
      content = MacOSWindowButtonInset(child: content);
    }
    content = AppBackgroundLayer(child: content);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScaleFactor)),
      child: content,
    );
  }
}
