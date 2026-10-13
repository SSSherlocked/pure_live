import 'package:flutter/material.dart';
import 'package:pure_live/core/theme/app_text.dart';
import 'package:pure_live/core/theme/theme.dart';
import 'package:pure_live/core/player/presentation/player_menu_choice.dart';

/// One entry of a popup list that picks one of several values (sort order,
/// quality, line, display mode). Every such list in the app uses this, so
/// they all look and behave the same: the body role, the labels as wide as
/// the longest one and centred in the entry (a popup menu rounds its width
/// up in 56 px steps and starts entries at the left, which pushed fixed-width
/// labels off centre), the current choice bold in the primary colour.
PopupMenuItem<T> choiceMenuItem<T>(
  BuildContext context, {
  required T value,
  required String label,
  required List<String> labels,
  required bool selected,
  Key? key,
}) {
  final base = AppText.of(context).body;
  final colors = Theme.of(context).colorScheme;
  return PopupMenuItem<T>(
    key: key,
    height: kFloatingMenuItemHeight,
    value: value,
    child: Center(
      child: SizedBox(
        width: menuLabelWidth(context, labels, base.copyWith(fontWeight: FontWeight.w800)),
        child: Text(
          label,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: base.copyWith(
            color: selected ? colors.primary : null,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}
