import 'package:flutter/material.dart';
import 'package:pure_live/core/theme/app_text.dart';
import 'package:pure_live/core/player/presentation/player_menu_choice.dart';

/// `FLV` or `HLS` from a play line's path; null when the path tells neither
/// (the site's own stream facts, where it has them, come first).
String? streamFormatTagOfUrl(String url) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
  if (path.endsWith('.flv')) return 'FLV';
  if (path.endsWith('.m3u8') || path.endsWith('.m3u')) return 'HLS';
  return null;
}

/// Gap between a line's name and its format tag.
const double _tagGap = 6;

/// Side padding inside the tag.
const double _tagPadding = 4;

/// Border width of the tag.
const double _tagBorder = 0.8;

/// Corner radius of the tag: a small rounded rectangle, not a pill.
const double _tagRadius = 3;

/// The tag's text: the tag role one step smaller (down to 9, see
/// [compactTextTheme]), so it reads as a quiet note after the line's name.
TextStyle _tagTextStyle(TextStyle role) =>
    compactTextTheme(TextTheme(labelSmall: role)).labelSmall!.copyWith(fontWeight: FontWeight.w600);

/// The room a menu entry keeps after its label for the widest of [tags]:
/// the gap, the tag's text, padding and border. Zero when no line has one.
/// [style] is the tag role where the entries build (the compact one in a
/// [CompactText] menu); it defaults to the role at [context].
double streamFormatTagSlot(BuildContext context, Iterable<String?> tags, {TextStyle? style}) {
  final labels = tags.whereType<String>().toList();
  if (labels.isEmpty) return 0;
  final text = _tagTextStyle(style ?? AppText.of(context).tag);
  return _tagGap + menuLabelWidth(context, labels, text) + (_tagPadding + _tagBorder) * 2;
}

/// A line's stream format after its name in a line menu (线路1 FLV): a small
/// rounded rectangle with no fill, only a thin outline, text and outline in
/// the entry's own colour so the current line's tag takes the primary colour
/// with it.
class StreamFormatTag extends StatelessWidget {
  const StreamFormatTag({super.key, required this.label, this.color});

  final String label;

  /// The entry's text colour; the theme's default text colour when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = _tagTextStyle(AppText.of(context).tag);
    final resolved = color ?? DefaultTextStyle.of(context).style.color ?? style.color ?? Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: _tagPadding),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_tagRadius),
        border: Border.all(color: resolved, width: _tagBorder),
      ),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        style: style.copyWith(color: resolved),
      ),
    );
  }
}

/// A line menu entry's label with its format [tag] after it: the label
/// centred in [labelWidth], the tag in the [tagSlot] that follows (left
/// empty for a line without one, so every label stays in one column).
class StreamLineLabel extends StatelessWidget {
  const StreamLineLabel({
    super.key,
    required this.label,
    required this.labelWidth,
    required this.style,
    this.tag,
    this.tagSlot = 0,
  });

  final String label;
  final double labelWidth;
  final TextStyle style;
  final String? tag;
  final double tagSlot;

  @override
  Widget build(BuildContext context) {
    final text = SizedBox(
      width: labelWidth,
      child: Text(label, maxLines: 1, textAlign: TextAlign.center, style: style),
    );
    if (tagSlot <= 0) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        text,
        SizedBox(
          width: tagSlot,
          child: tag == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(left: _tagGap),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: StreamFormatTag(label: tag!, color: style.color),
                  ),
                ),
        ),
      ],
    );
  }
}
