import 'package:flutter/widgets.dart';
import 'package:pure_live/core/layout/app_layout.dart';
import 'package:pure_live/core/platform/platform_utils.dart';
import 'package:pure_live/domains/live/domain/global_player_service.dart';

/// Slots of the player's top bar, in order (see [PlayerControlPolicy]).
enum TopActionLeadingSlot { back, datetime, battery }

enum TopActionTrailingSlot { roomHistory, datetime, battery, pip }

/// Every rule for which player control appears where, in one table.
///
/// The bars ask this instead of each control carrying its own condition, so a
/// new mode or a new control is one edit here and every mode agrees. Two kinds
/// of input decide: the app layout (phone or wide, touch or pointer — see
/// [AppLayout]) and what the platform can do (picture-in-picture, rotation,
/// window fullscreen), which a display mode never changes.
@immutable
class PlayerControlPolicy {
  const PlayerControlPolicy({
    required this.layout,
    required this.fullscreen,
    required this.android,
    required this.windows,
    required this.mobilePlatform,
  });

  /// The rules for the player as it is now.
  factory PlayerControlPolicy.of(BuildContext context) => PlayerControlPolicy(
    layout: AppLayout.of(context),
    fullscreen: GlobalPlayerService.instance.player.fullscreenUI,
    android: PlatformUtils.isAndroid,
    windows: PlatformUtils.isWindows,
    mobilePlatform: PlatformUtils.isMobile,
  );

  final AppLayout layout;
  final bool fullscreen;
  final bool android;
  final bool windows;
  final bool mobilePlatform;

  // --- Size --------------------------------------------------------------

  /// Smaller, closer controls: the phone layout's inline player is a strip of
  /// the page. Fullscreen keeps the full size.
  bool get compactControls => layout.phone && !fullscreen;

  // --- Interaction -------------------------------------------------------

  /// Touch: a second tap on the picture hides visible controls, as in other
  /// video apps. Pointer clicks keep revealing them.
  bool get tapTogglesControls => layout.touch;

  // --- Top bar -----------------------------------------------------------

  /// Fullscreen has its own back button; Android puts the clock and battery
  /// beside it, where the status bar would be.
  List<TopActionLeadingSlot> get leadingSlots => [
    if (fullscreen) TopActionLeadingSlot.back,
    if (fullscreen && android) TopActionLeadingSlot.datetime,
    if (fullscreen && android) TopActionLeadingSlot.battery,
  ];

  /// 关注 (switching rooms) and, off Android, the clock and battery only in
  /// fullscreen, where the page around the player is hidden. Picture-in-
  /// picture wherever the platform has it.
  List<TopActionTrailingSlot> get trailingSlots => [
    if (fullscreen) TopActionTrailingSlot.roomHistory,
    if (fullscreen && !android) TopActionTrailingSlot.datetime,
    if (fullscreen && !android) TopActionTrailingSlot.battery,
    if (android || windows) TopActionTrailingSlot.pip,
  ];

  /// 投屏 is a ⋯ menu entry wherever casting exists (Android), never a bar
  /// button. 纯音频 and 画面比例 are ⋯ entries everywhere.
  bool get castInMoreMenu => android;

  // --- Bottom bar --------------------------------------------------------

  /// The quality/line menu: everywhere except the phone layout's inline
  /// player, whose page has its own quality and line row under the video.
  bool get streamSelector => fullscreen || !layout.phone;

  /// Orientation and portrait display controls need a rotating device.
  bool get orientationControls => mobilePlatform;

  /// The volume slider and the window-fullscreen button are Windows window
  /// features.
  bool get volumeSlider => windows;
  bool get windowFullscreenButton => windows;

  // --- Panels ------------------------------------------------------------

  /// Danmaku settings open as the docked side panel (the 关注 panel's shape)
  /// in the wide layout and in fullscreen; otherwise as a centred sheet.
  bool get dockedDanmakuPanel => layout.wide || fullscreen;
}
