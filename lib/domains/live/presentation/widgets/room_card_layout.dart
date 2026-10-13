import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pure_live/core/config/room_card_settings_controller.dart';

/// Shared geometry for `RoomCard` and fixed-extent room grids.
///
/// Compact cards deliberately omit the 16:9 cover. Keeping their height in a
/// single helper prevents a grid delegate from reserving the old cover-card
/// extent and making the compact preset look ineffective.
abstract final class RoomCardLayoutMetrics {
  /// The shortest a room list row may be: the 关注 panel's rows and the
  /// compact room cards share it, so both lists have the same rhythm. Larger
  /// text grows a row past it.
  static const double listRowMinHeight = 72;

  /// A compact row is [listRowMinHeight] tall, or as tall as its text plus
  /// 8 px above and below when larger text needs more; the avatar and the
  /// delete button always fit within the minimum.
  static double compactHeight({
    required RoomCardAppearance appearance,
    required bool dense,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    final contentHeight = _textHeight(appearance: appearance, dense: dense, textScaler: textScaler);
    return math.max(listRowMinHeight, contentHeight + 16);
  }

  static double gridMainAxisExtent({
    required double itemWidth,
    required RoomCardAppearance appearance,
    required bool dense,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    if (appearance.layout == RoomCardLayout.compact) {
      return compactHeight(appearance: appearance, dense: dense, textScaler: textScaler);
    }

    final captionHeight = coverCaptionHeight(appearance: appearance, dense: dense, textScaler: textScaler);
    return math.max(0, itemWidth) * 9 / 16 + captionHeight;
  }

  /// Height of the single avatar + streamer-name row under a cover card (the
  /// room title sits on the cover itself). About 30 % below the former
  /// two-line caption; scaled text still gets the room it needs.
  static double coverCaptionHeight({
    required RoomCardAppearance appearance,
    required bool dense,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    if (!appearance.showAvatar && !appearance.showAnchorName) return 0;
    final baseCaptionHeight = dense ? 50.0 : 58.0;
    final avatarHeight = appearance.showAvatar ? (dense ? 34.0 : 40.0) : 0.0;
    final lineHeight = textScaler.scale(dense ? 13 : 15) * 1.3;
    final scaledCaptionHeight = math.max(avatarHeight, lineHeight) + (dense ? 12.0 : 16.0);
    return math.max(baseCaptionHeight, scaledCaptionHeight);
  }

  /// The gap between the streamer and the room title of a compact row: with
  /// the lines' own leading it reads as about 7.5 px.
  static const double compactLineGap = 4.5;

  /// The gap between the platform tag and the heat at a compact row's end.
  static const double compactMetricGap = 6;

  static double _textHeight({
    required RoomCardAppearance appearance,
    required bool dense,
    required TextScaler textScaler,
  }) {
    if (!appearance.showAnchorName) return textScaler.scale(dense ? 13 : 15) * 1.2;
    final nickHeight = textScaler.scale(dense ? 14 : 16) * 1.2;
    final titleHeight = textScaler.scale(dense ? 12 : 13) * 1.2;
    return nickHeight + compactLineGap + titleHeight;
  }
}
