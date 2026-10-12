import 'package:flutter/material.dart';

/// The app's text roles. Every piece of UI text uses one of these, read from
/// the theme where the widget sits; nothing names a font size.
///
/// | Role           | Used for                                        | Font setting  | Default |
/// |----------------|-------------------------------------------------|---------------|---------|
/// | [pageTitle]    | app bars, a page's main heading                 | 大标题         | 20      |
/// | [sectionTitle] | card/streamer names, setting titles, dialog titles | 中号标题    | 15      |
/// | [listPrimary]  | the first line of a list row                    | 正文大         | 14      |
/// | [body]         | ordinary text and descriptions                  | 正文中         | 13      |
/// | [secondary]    | subtitles, times, secondary details             | 正文小         | 12      |
/// | [tag]          | platform tags, badges, counts                   | 正文小 − 1     | 11      |
///
/// Sizes come from 字体设置 through the theme (see `MyTheme`), so they follow
/// the user's choices. Inside a [CompactText] area (the room's side panel,
/// player menus) every role is one step smaller.
///
/// Text that has its own size setting is not a role: the danmaku over the
/// video and the chat list.
@immutable
class AppText {
  const AppText._(this._theme);

  factory AppText.of(BuildContext context) => AppText._(Theme.of(context).textTheme);

  /// For code that already holds the [ThemeData] of where it builds.
  factory AppText.from(ThemeData theme) => AppText._(theme.textTheme);

  final TextTheme _theme;

  TextStyle get pageTitle => _theme.titleLarge!;
  TextStyle get sectionTitle => _theme.titleMedium!;
  TextStyle get listPrimary => _theme.bodyLarge!;
  TextStyle get body => _theme.bodyMedium!;
  TextStyle get secondary => _theme.bodySmall!;
  TextStyle get tag => _theme.labelSmall!;
}

/// Makes every text role in [child] one step smaller (see [AppText]): the
/// dense surfaces — side panel, player menus, the 关注 panel — use the same
/// roles as the rest of the app at a size that fits them, instead of scaling
/// the whole subtree.
///
/// Material widgets inside (list tiles, switches' labels, buttons) take their
/// text from the same theme, so they follow too. Nesting has no further
/// effect.
class CompactText extends StatelessWidget {
  const CompactText({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (context.dependOnInheritedWidgetOfExactType<_CompactTextMarker>() != null) return child;
    final theme = Theme.of(context);
    final compact = compactTextTheme(theme.textTheme);
    final tiles = theme.listTileTheme;
    return _CompactTextMarker(
      child: Theme(
        data: theme.copyWith(
          textTheme: compact,
          // List tiles take their text from their own theme, fixed when the
          // theme was built: shrink those to the compact roles too.
          listTileTheme: tiles.copyWith(
            titleTextStyle: tiles.titleTextStyle?.copyWith(fontSize: compact.titleMedium?.fontSize),
            subtitleTextStyle: tiles.subtitleTextStyle?.copyWith(fontSize: compact.bodySmall?.fontSize),
          ),
        ),
        child: DefaultTextStyle.merge(style: TextStyle(fontSize: compact.bodyMedium?.fontSize), child: child),
      ),
    );
  }
}

class _CompactTextMarker extends InheritedWidget {
  const _CompactTextMarker({required super.child});

  @override
  bool updateShouldNotify(_CompactTextMarker oldWidget) => false;
}

/// [theme] with every slot taking the size of the role one step below it.
/// The smallest role ([AppText.tag]) loses one more pixel, down to 9.
TextTheme compactTextTheme(TextTheme theme) {
  double? size(TextStyle? style) => style?.fontSize;
  TextStyle? resize(TextStyle? style, double? fontSize) =>
      style == null || fontSize == null ? style : style.copyWith(fontSize: fontSize);

  final tagSize = size(theme.labelSmall);
  final smallestTag = tagSize == null ? null : (tagSize - 1 < 9 ? 9.0 : tagSize - 1);

  return theme.copyWith(
    titleLarge: resize(theme.titleLarge, size(theme.titleMedium)),
    titleMedium: resize(theme.titleMedium, size(theme.bodyLarge)),
    titleSmall: resize(theme.titleSmall, size(theme.bodyMedium)),
    bodyLarge: resize(theme.bodyLarge, size(theme.bodyMedium)),
    bodyMedium: resize(theme.bodyMedium, size(theme.bodySmall)),
    bodySmall: resize(theme.bodySmall, size(theme.labelSmall)),
    labelLarge: resize(theme.labelLarge, size(theme.bodySmall)),
    labelMedium: resize(theme.labelMedium, size(theme.labelSmall)),
    labelSmall: resize(theme.labelSmall, smallestTag),
  );
}
