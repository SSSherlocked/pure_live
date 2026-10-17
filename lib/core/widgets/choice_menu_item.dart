import 'package:flutter/material.dart';
import 'package:pure_live/core/theme/app_text.dart';
import 'package:pure_live/core/theme/theme.dart';
import 'package:pure_live/core/player/presentation/player_menu_choice.dart';
import 'package:pure_live/core/widgets/stream_format_tag.dart';

/// One entry of a popup list that picks one of several values (sort order,
/// quality, line, display mode). Every such list in the app uses this, so
/// they all look and behave the same: the body role, the labels as wide as
/// the longest one and centred in the entry (a popup menu rounds its width
/// up in 56 px steps and starts entries at the left, which pushed fixed-width
/// labels off centre), the current choice bold in the primary colour on a
/// faint band of it ([floatingMenuSelectedColor]).
/// Side padding of a choice entry.
const double _choicePadding = 16;

/// The width every choice list should be: its longest label plus the
/// entries' padding. Pass it as the PopupMenuButton's `constraints`; without
/// the cap the popup rounds its width up in 56 px steps and leaves wide empty
/// margins.
/// [tags] are the entries' stream format tags, when the list picks a line.
BoxConstraints choiceMenuConstraints(BuildContext context, List<String> labels, {List<String?> tags = const []}) {
  final width = _labelWidth(context, labels) + streamFormatTagSlot(context, tags) + _choicePadding * 2;
  return BoxConstraints(minWidth: width, maxWidth: width);
}

double _labelWidth(BuildContext context, List<String> labels) =>
    menuLabelWidth(context, labels, AppText.of(context).body.copyWith(fontWeight: FontWeight.w800));

PopupMenuItem<T> choiceMenuItem<T>(
  BuildContext context, {
  required T value,
  required String label,
  required List<String> labels,
  required bool selected,
  Key? key,
  String? tag,
  List<String?> tags = const [],
}) {
  final base = AppText.of(context).body;
  final colors = Theme.of(context).colorScheme;
  return PopupMenuItem<T>(
    key: key,
    height: kFloatingMenuItemHeight,
    // The band fills the whole row, so the entry's padding is inside it.
    padding: EdgeInsets.zero,
    value: value,
    child: Container(
      height: kFloatingMenuItemHeight,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: _choicePadding),
      color: selected ? floatingMenuSelectedColor(colors) : null,
      child: StreamLineLabel(
        label: label,
        labelWidth: _labelWidth(context, labels),
        style: base.copyWith(
          color: selected ? colors.primary : null,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        ),
        tag: tag,
        tagSlot: streamFormatTagSlot(context, tags),
      ),
    ),
  );
}
