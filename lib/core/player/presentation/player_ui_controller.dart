import 'dart:async';
import 'dart:math' as math;
import 'dart:io';

import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/player/presentation/player_level_indicator.dart';

/// What the shared player surface needs from whoever owns playback.
///
/// The gesture layer, the progress bar and the "leave the picture" half of the
/// control bar are the same on every surface this app plays video on: a live
/// room and a recorded file differ in *where the media comes from*, not in how a
/// viewer scrubs, changes volume, or leaves the picture. Those widgets live in
/// Core, which may not know about a room, a recording or a quality list — so they
/// talk to this instead, and each player supplies its own implementation.
///
/// Deliberately small: everything a shared control can drive, and nothing about
/// rooms, files, platform sites or EPG. A member belongs here only when at least
/// two players need it.
///
/// Responsibilities:
///
/// - expose play state, position and the transport actions
/// - expose the surface gestures' two targets: brightness and volume
/// - expose the danmaku surface a player is rendering
///
/// It does not:
///
/// - own playback (the kernel handle does)
/// - know which source is playing
/// - carry room, file or quality state
abstract interface class PlayerUiController {
  /// Whether the picture is currently playing.
  bool get uiIsPlaying;

  /// How far into the media playback is.
  Duration get uiPosition;

  /// Total length, or zero when the source does not report one (a live stream).
  Duration get uiDuration;

  /// Playback speed multiplier.
  double get uiRate;

  /// Starts or resumes playback.
  Future<void> uiPlay();

  /// Pauses playback.
  Future<void> uiPause();

  /// Jumps to an absolute position, clamped by the implementation.
  Future<void> uiSeekTo(Duration position);

  /// Sets the playback speed.
  Future<void> uiSetRate(double rate);

  /// Leaves the player surface: fullscreen, picture-in-picture or the small
  /// window depending on the host. Returns false when the player cannot.
  Future<bool> uiRequestExit();

  /// The current volume in `0..1`, or null when this player cannot report one.
  Future<double?> uiVolume();

  /// Applies a volume in `0..1`.
  Future<void> uiSetVolume(double value);

  /// The screen brightness in `0..1`, or null when the platform has none.
  Future<double?> uiBrightness();

  /// Applies a screen brightness in `0..1`.
  Future<void> uiSetBrightness(double value);

  /// Whether vertical drags on the surface change brightness (left half) and
  /// volume (right half).
  ///
  /// False on a desktop: there only the keyboard changes the volume, and a
  /// drag (a trackpad's two-finger swipe included) changes nothing.
  bool get uiSupportsDragGestures;

  /// Puts the control bars away while a level changes, so the level readout at
  /// the edge is the only thing on the picture (the fullscreen lock sits at the
  /// same right edge as the volume).
  void uiHideControls();

  /// The danmaku surface to overlay on the picture, or null when this player has
  /// none (a recording whose chat file is missing, a room with chat switched
  /// off).
  Widget? buildDanmakuSurface(BuildContext context);
}

/// Which half of the surface a brightness/volume drag started on.
enum PlayerDragSide { brightness, volume }

/// Resolves the side from a surface-local drag start.
///
/// The split is the surface's own midpoint, not the window's: the small window
/// and a split-view pane both hand their own box to the gesture.
PlayerDragSide resolvePlayerDragSide(double localDx, double surfaceWidth) {
  return localDx > surfaceWidth / 2 ? PlayerDragSide.volume : PlayerDragSide.brightness;
}

/// Launcher home-gesture strip (swipe up to the system desktop) at the bottom of
/// mobile screens.
///
/// Android and iOS deliver the pointer to the app first and cancel it once the
/// launcher recognises the gesture, so a brightness/volume drag started inside
/// the strip always ends with a half-applied change and no way to undo it. The
/// strip never starts such a drag.
const double systemHomeGestureZoneHeight = 48;

/// Whether a surface-local drag start lies inside the launcher gesture strip.
@visibleForTesting
bool startsInSystemHomeGestureZone({required Offset localPosition, required Size surfaceSize}) {
  if (surfaceSize.height <= 0) return false;
  final zoneHeight = systemHomeGestureZoneHeight.clamp(0.0, surfaceSize.height / 3);
  return localPosition.dy >= surfaceSize.height - zoneHeight;
}

/// Status-bar / notification-shade strip at the top of the screen.
///
/// Pulling the notification shade down starts on the screen's top edge; in
/// landscape and fullscreen the video reaches that edge, so the same swipe used
/// to also change brightness or volume. Drags that start this close to the
/// top of the screen are left to the system.
const double systemTopGestureZoneHeight = 40;

/// Vertical travel a drag needs before it changes brightness or volume.
///
/// Shorter, accidental movements (a tap that slides, a scroll that started on
/// the video) never change a level; once past the threshold only the travel
/// beyond it counts, so the value does not jump.
const double playerGestureActivationDistance = 24;

/// Whether a drag's global start lies in the status-bar / shade strip.
@visibleForTesting
bool startsInSystemTopGestureZone({required double globalDy, required double topInset}) {
  return globalDy <= topInset + systemTopGestureZoneHeight;
}

/// The full-surface gesture layer every player shares.
///
/// On a phone or tablet a vertical drag on the left half changes screen
/// brightness, on the right half the volume, and the level shows at that edge
/// while it runs ([PlayerLevelIndicator]); on a desktop the layer changes
/// nothing (the keyboard owns volume). The layer owns only the gesture and the
/// readout; the values themselves come from
/// [PlayerUiController], so a live room writes to the room's volume while a
/// recording writes to the ordinary player volume.
///
/// Responsibilities:
///
/// - recognise the brightness/volume drags
/// - show the level at the edge it is changed on for the duration of the gesture
/// - ignore drags that would race the system's own home gesture
///
/// It does not:
///
/// - store or persist a level (the controller does)
/// - draw the picture or the control bars
/// - handle taps (the page places its own tap target)
class PlayerGestureLayer extends StatefulWidget {
  const PlayerGestureLayer({super.key, required this.controller, this.child, this.enabled = true});

  final PlayerUiController controller;

  /// The surface the gesture sits on; null makes the layer a transparent
  /// overlay, which is how a page stacks it over its own picture.
  final Widget? child;

  /// Whether the layer takes brightness/volume drags at all.
  ///
  /// A host that owns the vertical drag for its own transition — the room's
  /// portrait-panel restore swipe, for example — turns this off while that
  /// transition is available, so one drag never means two things.
  final bool enabled;

  @override
  State<PlayerGestureLayer> createState() => PlayerGestureLayerState();
}

class PlayerGestureLayerState extends State<PlayerGestureLayer> {
  static const Duration _hideAfter = Duration(seconds: 1);

  /// Full travel of the surface maps to a quarter of the level range, which is
  /// the sensitivity the live room has always used.
  static const double _sensitivity = 0.25;

  Timer? _hideTimer;

  /// Hidden until the first drag: a HUD that greets the viewer with
  /// "brightness 100%" before any gesture happened is just noise.
  bool _visible = false;
  PlayerDragSide _side = PlayerDragSide.brightness;
  double _value = 1;
  bool _systemGesture = false;

  /// Vertical travel of the current drag not yet past the activation distance.
  double _pendingTravel = 0;
  bool _activated = false;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  Size get _surfaceSize {
    final size = context.size;
    if (size != null && size.height > 0) return size;
    return MediaQuery.sizeOf(context);
  }

  void _keepVisible() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideAfter, () {
      if (mounted) setState(() => _visible = false);
    });
    if (!_visible) setState(() => _visible = true);
  }

  Future<void> _apply(Offset localPosition, Offset delta, Size size) async {
    if (delta.distance < 0.5 || size.height <= 0) return;
    final resolved = resolvePlayerDragSide(localPosition.dx, size.width);

    if (_side != resolved || !_visible) {
      _side = resolved;
      try {
        final observed = resolved == PlayerDragSide.brightness
            ? await widget.controller.uiBrightness()
            : await widget.controller.uiVolume();
        if (!mounted) return;
        setState(() => _value = (observed ?? _value).clamp(0.0, 1.0).toDouble());
      } catch (_) {
        return;
      }
    }

    if (!mounted) return;
    _keepVisible();

    final target = (_value - delta.dy / (size.height / 2) * _sensitivity).clamp(0.0, 1.0).toDouble();
    if ((target - _value).abs() <= 0.001) return;
    setState(() => _value = target);
    if (_side == PlayerDragSide.brightness) {
      unawaited(widget.controller.uiSetBrightness(target));
    } else {
      unawaited(widget.controller.uiSetVolume(target));
    }
  }

  void _onVerticalDragStart(DragStartDetails details) {
    final media = MediaQuery.of(context);
    final topInset = math.max(media.viewPadding.top, media.systemGestureInsets.top);
    _systemGesture =
        startsInSystemHomeGestureZone(localPosition: details.localPosition, surfaceSize: _surfaceSize) ||
        startsInSystemTopGestureZone(globalDy: details.globalPosition.dy, topInset: topInset);
    _pendingTravel = 0;
    _activated = false;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled || _systemGesture) return;
    var delta = details.delta;
    if (!_activated) {
      _pendingTravel += delta.dy;
      if (_pendingTravel.abs() < playerGestureActivationDistance) return;
      _activated = true;
      widget.controller.uiHideControls();
      final excess = _pendingTravel - playerGestureActivationDistance * _pendingTravel.sign;
      delta = Offset(delta.dx, excess);
    }
    unawaited(_apply(details.localPosition, delta, _surfaceSize));
  }

  void _resetDrag() {
    _systemGesture = false;
    _pendingTravel = 0;
    _activated = false;
  }

  void _onVerticalDragEnd(DragEndDetails details) => _resetDrag();

  IconData get _brightnessIcon => _value < 0.5 ? Icons.brightness_low_rounded : Icons.brightness_high_rounded;

  @override
  Widget build(BuildContext context) {
    final drags = widget.controller.uiSupportsDragGestures;
    return GestureDetector(
      // Opaque on purpose: this layer paints nothing and its only child is an
      // empty expanding `Stack`, so `deferToChild` left the whole gesture
      // surface out of hit testing — a drag did nothing, and in the room panel
      // the tap layer stacked above it stopped receiving taps as well, which is
      // what made tapping the video unable to show the controls. Being a
      // hit-test target blocks nothing: this still reports a miss, so a control
      // bar above keeps its taps and a picture below keeps its own gestures.
      behavior: HitTestBehavior.opaque,
      // No drag recognizer at all on a desktop, so the layer never enters
      // the gesture arena against the surface's own drags.
      onVerticalDragStart: drags ? _onVerticalDragStart : null,
      onVerticalDragUpdate: drags ? _onVerticalDragUpdate : null,
      onVerticalDragEnd: drags ? _onVerticalDragEnd : null,
      onVerticalDragCancel: drags ? _resetDrag : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.child != null) widget.child!,
          PlayerLevelIndicator(
            side: PlayerLevelSide.left,
            visible: _visible && _side == PlayerDragSide.brightness,
            value: _value,
            icon: _brightnessIcon,
          ),
          PlayerLevelIndicator(
            side: PlayerLevelSide.right,
            visible: _visible && _side == PlayerDragSide.volume,
            value: _value,
            icon: playerVolumeIcon(_value),
          ),
        ],
      ),
    );
  }
}

/// Whether this platform has a screen brightness the app may set.
///
/// Kept here rather than in a player so the gesture layer can decide it without
/// reaching into a domain; the two mobile platforms are the only ones exposing a
/// per-application brightness.
bool get platformSupportsBrightness => Platform.isAndroid || Platform.isIOS;
