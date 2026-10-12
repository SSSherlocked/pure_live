import 'dart:math' as math;

import 'package:flutter/widgets.dart';

const contentFirstPanelHeaderActionExtent = 48.0;

@immutable
class RoomHistoryTextMetrics {
  const RoomHistoryTextMetrics({
    required this.headerHeight,
    required this.tabBarHeight,
    required this.cardFooterHeight,
    required this.mobileRowHeight,
    required this.scrollTabs,
  });

  final double headerHeight;
  final double tabBarHeight;
  final double cardFooterHeight;

  final double mobileRowHeight;
  final bool scrollTabs;
}

/// Sizes the room switcher's fixed text regions without shrinking accessible
/// text back into the original compact rows.
RoomHistoryTextMetrics resolveRoomHistoryTextMetrics({
  required TextScaler textScaler,
  double headerFontSize = 14,
  double headerLineHeight = 1.25,
  double tabFontSize = 12,
  double tabLineHeight = 1.33,
  double titleFontSize = 12,
  double titleLineHeight = 1.33,
  double detailFontSize = 11,
  double detailLineHeight = 1.45,
}) {
  double lineExtent(double fontSize, double lineHeight) => textScaler.scale(fontSize) * lineHeight;

  final tabLineExtent = lineExtent(tabFontSize, tabLineHeight);
  final titleLineExtent = lineExtent(titleFontSize, titleLineHeight);
  final detailLineExtent = lineExtent(detailFontSize, detailLineHeight);
  return RoomHistoryTextMetrics(
    headerHeight: math.max(contentFirstPanelHeaderActionExtent, lineExtent(headerFontSize, headerLineHeight) + 8),
    tabBarHeight: math.max(contentFirstPanelHeaderActionExtent, tabLineExtent + 10),
    // Six pixels are consumed by the vertical padding; two more absorb text
    // metric rounding across fonts and device pixel ratios.
    cardFooterHeight: math.max(36, titleLineExtent + detailLineExtent + 8),
    mobileRowHeight: math.max(72, 16 + titleLineExtent + 2 + detailLineExtent),
    scrollTabs: textScaler.scale(tabFontSize) > tabFontSize * 1.01,
  );
}
