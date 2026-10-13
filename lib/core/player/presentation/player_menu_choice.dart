import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The widest of [labels] in [style], so every entry of a menu can take that
/// width and centre its label.
double menuLabelWidth(BuildContext context, Iterable<String> labels, TextStyle style) {
  final scaler = MediaQuery.textScalerOf(context);
  final direction = Directionality.of(context);
  var widest = 0.0;
  for (final label in labels) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    widest = math.max(widest, painter.width);
    painter.dispose();
  }
  return widest.ceilToDouble() + 1;
}

/// Horizontal padding a menu entry puts around its label (16 px a side, the
/// theme's menu button padding).
const double playerMenuItemPadding = 32;

/// One choice in a player menu (quality, line, 画面比例): the label centred
/// in the width of the menu's longest label, the current choice bold in the
/// primary colour. Measured with the bold style, so selecting never reflows.
class PlayerMenuChoice extends StatelessWidget {
  const PlayerMenuChoice({
    super.key,
    required this.label,
    required this.labels,
    required this.selected,
    required this.onPressed,
  });

  final String label;

  /// Every label of the menu, for the shared width.
  final List<String> labels;
  final bool selected;
  final VoidCallback? onPressed;

  static TextStyle styleOf(BuildContext context) =>
      (Theme.of(context).textTheme.labelLarge ?? const TextStyle()).copyWith(fontWeight: FontWeight.w800);

  @override
  Widget build(BuildContext context) {
    final bold = styleOf(context);
    final colors = Theme.of(context).colorScheme;
    return MenuItemButton(
      // The current choice stays enabled (it only closes the menu); selecting
      // it again must not reload the stream.
      onPressed: selected ? () {} : onPressed,
      child: SizedBox(
        width: menuLabelWidth(context, labels, bold),
        child: Text(
          label,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: selected ? bold.copyWith(color: colors.primary) : bold.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Width of a player menu whose entries carry a leading icon before their
/// label: the widest
/// of [labels] in the menu entry style plus the entry's padding, icon column
/// and the gap after it. [context] must be inside the menu's text scope
/// (e.g. under `CompactText`).
double playerMenuPanelWidth(BuildContext context, Iterable<String> labels) {
  final style = (Theme.of(context).textTheme.labelLarge ?? const TextStyle()).merge(playerMenuLabelStyle);
  // 16 px entry padding either side, the 18 px icon (a submenu's arrow hangs
  // in the padding), the 12 px gap, and the 12 px a SubmenuButton keeps
  // before its (hidden) trailing icon (画面比例 wrapped on phones without it).
  // Labels are single-line, so a rounding pixel ellipsises rather than wraps.
  const chrome = playerMenuItemPadding + 18 + 12 + 12;
  return menuLabelWidth(context, labels, style) + chrome;
}

/// The label weight of a plain player menu entry (⋯ entries, submenu
/// titles): one step above the menu default.
const TextStyle playerMenuLabelStyle = TextStyle(fontWeight: FontWeight.w600);
