import 'dart:ui';
import 'package:flame_barrage/flame_barrage.dart';

class BarrageItem {
  const BarrageItem({
    required this.content,
    this.type = BarrageType.scroll,
    this.userId,
    this.userName,
    this.id,
    this.at,
    this.priority = 0,
    this.effect,
    this.textColor,
    this.fontSize,
    this.fontWeight,
    this.fontStyle,
    this.fontFamily,
    this.letterSpacing,
    this.opacity,
    this.showStroke,
    this.strokeColor,
    this.strokeWidth,
    this.showShadow,
    this.shadowColor,
    this.shadowBlur,
    this.shadowOffset,
    this.fixedDuration,
    this.emojiSize,
    this.baseSpeed,
    this.overlapSafeGap,
    this.cachedFragments,
    this.cachedLayout,
    this.cachedPicture,
    this.onTapDown,
    this.onLongTapDown,
    this.onTapUp,
    this.onTapCancel,
  });

  final String content;
  final BarrageType type;
  final String? userId;
  final String? userName;

  /// Host-side identity of this message (e.g. a platform message id). The
  /// engine never reads it, but [BarrageController.removeWhere] lets the host
  /// take one message back by it (retraction).
  final String? id;

  /// When this message belongs on the media timeline, for a recorded stream
  /// whose comments were fetched as one list.
  ///
  /// `null` means "dispatch on arrival", which is what a live chat socket
  /// wants. A non-null value only takes effect once the item has been handed
  /// to `loadTimeline`; sending it through `send` ignores the time, because a
  /// host that fires messages one by one is describing a live room.
  final Duration? at;
  final int priority;

  /// Motion effect: when non-null, [BarrageMotionEffect] takes over the
  /// choreography for this message (entrance, cruise path, exit, hand-drawn
  /// mount and particles) and the message owns a lane for the whole show.
  final BarrageMotionEffect? effect;

  final Color? textColor;
  final double? fontSize;
  final FontWeight? fontWeight;
  final FontStyle? fontStyle;
  final String? fontFamily;
  final double? letterSpacing;
  final double? opacity;
  final bool? showStroke;
  final Color? strokeColor;
  final double? strokeWidth;
  final bool? showShadow;
  final Color? shadowColor;
  final double? shadowBlur;
  final Offset? shadowOffset;
  final Duration? fixedDuration;
  final double? emojiSize;
  final double? baseSpeed;
  final double? overlapSafeGap;

  final List<Fragment>? cachedFragments;
  final LayoutResult? cachedLayout;
  final Picture? cachedPicture;
  final void Function()? onTapDown;
  final void Function()? onLongTapDown;
  final void Function()? onTapUp;
  final void Function()? onTapCancel;
}
