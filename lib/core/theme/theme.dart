import 'dart:math' as math;

import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/platform/platform_utils.dart';

/// Height of a floating menu entry (popup menus, the home and player menus),
/// the same on every platform: Material's adaptive density otherwise took
/// 8 px off on desktop only, leaving desktop menus cramped and phone menus
/// airy with one setting.
const double kFloatingMenuItemHeight = 32;

/// Top and bottom padding of a floating menu panel (75 % of the default 8).
const double kFloatingMenuVerticalPadding = 6;

/// Space on either side of a floating menu entry.
const double kFloatingMenuItemHorizontalPadding = 16;

/// Space between a floating menu and the button that opened it: every menu
/// opens this far below its button's bottom edge.
const double kFloatingMenuAnchorGap = 4;

/// Corner radius of a floating menu panel: nearly square.
const double kFloatingMenuCornerRadius = 4;

/// Opacity of a floating menu panel, the same over a page and over the
/// picture: fully opaque, nothing behind a menu shows through.
const double kFloatingMenuOpacity = 1;

/// The shape of every floating menu panel: nearly square, no outline.
const OutlinedBorder kFloatingMenuShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(kFloatingMenuCornerRadius)),
);

/// Radius of a slider's thumb, the same on every platform (30 % above the
/// former 5.6 px); its drag halo is twice as wide.
const double kSliderThumbRadius = 7.28;

/// The knob of a switch that is on, in dark mode.
const Color kDarkSwitchThumbColor = Color(0xFF3A3D42);

/// The neutral greys of every slider and its value badge, one set per
/// brightness, whatever the theme colour: the thumb shares the filled
/// track's grey, the empty track sits one step above the page, and the tick
/// dots are a shade off the track under them. A badge (the value shown
/// beside a slider, and the bubble while dragging) is a grey pill with
/// near-white text in dark mode and near-black text in light mode.
class SliderPalette {
  const SliderPalette._({
    required this.track,
    required this.emptyTrack,
    required this.tick,
    required this.emptyTick,
    required this.badge,
    required this.badgeText,
  });

  final Color track;
  final Color emptyTrack;
  final Color tick;
  final Color emptyTick;
  final Color badge;
  final Color badgeText;

  static const SliderPalette dark = SliderPalette._(
    track: Color(0xFF878B92),
    emptyTrack: Color(0xFF3C3F44),
    tick: Color(0xFFADB1B6),
    emptyTick: Color(0xFF62666C),
    badge: Color(0xFF303338),
    badgeText: Color(0xFFE8EAED),
  );

  static const SliderPalette light = SliderPalette._(
    track: Color(0xFFA3A7AD),
    emptyTrack: Color(0xFFE2E4E7),
    tick: Color(0xFFD9DBDE),
    emptyTick: Color(0xFFBABDC1),
    badge: Color(0xFFE3E5E8),
    badgeText: Color(0xFF26292E),
  );

  static SliderPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// The colour of every floating menu panel (MenuAnchor menus, their
/// submenus and popup menus): one tonal grey at [kFloatingMenuOpacity] in
/// every mode. Pure-black mode keeps the grey too, so a menu over a black
/// page reads as a layer without an outline.
Color floatingMenuColor(ColorScheme colors) => colors.surfaceContainerHigh.withValues(alpha: kFloatingMenuOpacity);

const PageTransitionsTheme appPageTransitionsTheme = PageTransitionsTheme(
  builders: <TargetPlatform, PageTransitionsBuilder>{
    // Keep Android's system back dispatch, but let an unclaimed gesture commit
    // through Navigator's regular pop path. Flutter's gesture-owned shared
    // element transition can retain input after its visual commit on some
    // Android/ColorOS versions (Pure Live #852; Flutter #153577).
    TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
  },
);

/// Resolves the app-wide font without overriding a platform's native default.
///
/// Downloaded fonts are registered under their persisted IDs and therefore
/// take precedence. The bundled MI Sans is the app-wide default on every
/// platform: it ships with CJK coverage, so no platform needs to fall back
/// to a system font (Microsoft YaHei on Windows, device defaults elsewhere).
String? resolveAppFontFamily({
  required String selectedName,
  required Iterable<String> customFonts,
  required bool isWindows,
  bool isMacOS = false,
}) {
  if (customFonts.contains(selectedName)) {
    return selectedName;
  }
  // macOS keeps the system font (SF with PingFang for CJK): Impeller draws
  // the bundled MI Sans with broken, overlapping CJK glyphs there.
  if (isMacOS) return null;
  return 'MI_Sans_Regular';
}

/// The colour scheme for the chosen theme colour [seed], used when dynamic
/// colour is off.
///
/// Material's seeding only takes the seed's hue and picks its own tones:
/// tonal spot turned a grey or white seed blue, and monochrome made every
/// grey white in dark mode (black in light mode). The accent roles still
/// come from Material - a true grey set for a near-neutral seed
/// (monochrome), otherwise one close to the seed (fidelity) - but the
/// primary colour is the chosen colour itself, so each shade looks as
/// picked. It is only lightened or darkened as far as it must be to stay
/// readable on the page ([kMinPrimaryContrast]).
///
/// With [tinted] (动态取色 on) the surfaces, text and outlines are
/// Material's own for the seed, so pages, cards, bars, sheets and dialogs
/// carry the theme colour's hue, and elevation tints with it. Otherwise
/// they take no colour from the seed: they are Material's neutral greys
/// ([_neutralSurfaces]) and surfaceTint is transparent, so the theme
/// colour only marks accents (buttons, switches, sliders, selection).
ColorScheme seededColorScheme(Color seed, Brightness brightness, {bool tinted = false}) {
  final neutral = HSLColor.fromColor(seed).saturation < 0.12;
  final seeded = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    dynamicSchemeVariant: neutral ? DynamicSchemeVariant.monochrome : DynamicSchemeVariant.fidelity,
  );
  final base = tinted ? seeded : _neutralSurfaces(seeded, brightness);
  final primary = readablePrimary(seed.withValues(alpha: 1), base.surface);
  final onPrimary = _contrast(Colors.white, primary) >= _contrast(Colors.black, primary) ? Colors.white : Colors.black;
  final container = Color.alphaBlend(primary.withValues(alpha: 0.3), base.surface);
  return base.copyWith(
    primary: primary,
    onPrimary: onPrimary,
    primaryContainer: container,
    onPrimaryContainer: base.onSurface,
    inversePrimary: Color.alphaBlend(primary.withValues(alpha: 0.6), base.inverseSurface),
    surfaceTint: tinted ? primary : Colors.transparent,
  );
}

/// [scheme] with every surface, text and outline role replaced by
/// Material 3's neutral palette at chroma 0 (the tone of each role is
/// Material's own, e.g. surface T98 light / T6 dark).
ColorScheme _neutralSurfaces(ColorScheme scheme, Brightness brightness) {
  if (brightness == Brightness.dark) {
    return scheme.copyWith(
      surface: const Color(0xFF131313),
      onSurface: const Color(0xFFE2E2E2),
      onSurfaceVariant: const Color(0xFFC6C6C6),
      surfaceDim: const Color(0xFF131313),
      surfaceBright: const Color(0xFF393939),
      surfaceContainerLowest: const Color(0xFF0E0E0E),
      surfaceContainerLow: const Color(0xFF1B1B1B),
      surfaceContainer: const Color(0xFF1F1F1F),
      surfaceContainerHigh: const Color(0xFF2A2A2A),
      surfaceContainerHighest: const Color(0xFF353535),
      outline: const Color(0xFF919191),
      outlineVariant: const Color(0xFF474747),
      inverseSurface: const Color(0xFFE2E2E2),
      onInverseSurface: const Color(0xFF303030),
    );
  }
  return scheme.copyWith(
    surface: const Color(0xFFF9F9F9),
    onSurface: const Color(0xFF1B1B1B),
    onSurfaceVariant: const Color(0xFF474747),
    surfaceDim: const Color(0xFFDADADA),
    surfaceBright: const Color(0xFFF9F9F9),
    surfaceContainerLowest: const Color(0xFFFFFFFF),
    surfaceContainerLow: const Color(0xFFF3F3F3),
    surfaceContainer: const Color(0xFFEEEEEE),
    surfaceContainerHigh: const Color(0xFFE8E8E8),
    surfaceContainerHighest: const Color(0xFFE2E2E2),
    outline: const Color(0xFF777777),
    outlineVariant: const Color(0xFFC6C6C6),
    inverseSurface: const Color(0xFF303030),
    onInverseSurface: const Color(0xFFF1F1F1),
  );
}

/// The least contrast the primary colour keeps against the page (WCAG's
/// minimum for large text and icons).
const double kMinPrimaryContrast = 3;

/// [color] moved toward black or white in small lightness steps until it
/// reaches [kMinPrimaryContrast] against [surface]; unchanged when it
/// already does.
Color readablePrimary(Color color, Color surface) {
  if (_contrast(color, surface) >= kMinPrimaryContrast) return color;
  final darkPage = surface.computeLuminance() < 0.5;
  var hsl = HSLColor.fromColor(color);
  for (var i = 0; i < 100 && _contrast(hsl.toColor(), surface) < kMinPrimaryContrast; i++) {
    final lightness = (hsl.lightness + (darkPage ? 0.01 : -0.01)).clamp(0.0, 1.0);
    if (lightness == hsl.lightness) break;
    hsl = hsl.withLightness(lightness);
  }
  return hsl.toColor();
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Background of the current choice in a floating menu: the primary colour,
/// faint. With a pale theme colour (grey, white) the primary-coloured label
/// alone barely stands out; the band marks the row.
const double kFloatingMenuSelectedOpacity = 0.16;

Color floatingMenuSelectedColor(ColorScheme colors) => colors.primary.withValues(alpha: kFloatingMenuSelectedOpacity);

/// Opacity of a divider line: the text colour, faint, so a hairline over a
/// black or dark page is only just visible (Material's outlineVariant stood
/// out as a bright grey there). Outlines that must read clearly keep their
/// own roles.
const double kDividerOpacity = 0.12;

Color dividerLineColor(ColorScheme colors) => colors.onSurface.withValues(alpha: kDividerOpacity);

class MyTheme {
  final Color? primaryColor;

  MyTheme({this.primaryColor});

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semiBold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;

  ThemeData get lightThemeData => _buildTheme(Brightness.light);
  ThemeData get darkThemeData => _buildTheme(Brightness.dark);

  String? _resolveFontFamily(String selectedName, List<String> customFonts) {
    return resolveAppFontFamily(
      selectedName: selectedName,
      customFonts: customFonts,
      isWindows: PlatformUtils.isWindows,
      isMacOS: PlatformUtils.isMacOS,
    );
  }

  TextTheme _buildTextTheme({required TextTheme base, required String? fontFamily}) {
    final localized = fontFamily != null ? base.apply(fontFamily: fontFamily) : base;

    TextStyle scale(TextStyle? style, double target) {
      return (style ?? const TextStyle()).copyWith(fontSize: target);
    }

    final font = SettingsService.to.font;

    return localized.copyWith(
      displayLarge: scale(localized.displayLarge, font.fontSizeBodySmall.v * 4.75),
      displayMedium: scale(localized.displayMedium, font.fontSizeBodySmall.v * 3.75),
      displaySmall: scale(localized.displaySmall, font.fontSizeBodySmall.v * 3.0),

      headlineLarge: scale(localized.headlineLarge, font.fontSizeTitleLarge.v * 1.6),
      headlineMedium: scale(localized.headlineMedium, font.fontSizeTitleLarge.v * 1.4),
      headlineSmall: scale(localized.headlineSmall, font.fontSizeTitleLarge.v * 1.2),

      titleLarge: scale(localized.titleLarge, font.fontSizeTitleLarge.v).copyWith(fontWeight: semiBold),
      titleMedium: scale(localized.titleMedium, font.fontSizeTitleMedium.v).copyWith(fontWeight: medium),
      titleSmall: scale(localized.titleSmall, font.fontSizeBodyLarge.v).copyWith(fontWeight: medium),

      bodyLarge: scale(localized.bodyLarge, font.fontSizeBodyLarge.v),
      bodyMedium: scale(localized.bodyMedium, font.fontSizeBodyMedium.v),
      bodySmall: scale(localized.bodySmall, font.fontSizeBodySmall.v),

      labelLarge: scale(localized.labelLarge, font.fontSizeBodyMedium.v).copyWith(fontWeight: medium),
      labelMedium: scale(localized.labelMedium, font.fontSizeBodySmall.v),
      // AppText.tag: platform tags, badges, counts.
      labelSmall: scale(localized.labelSmall, font.fontSizeBodySmall.v - 1).copyWith(fontWeight: medium),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;

    final customFonts = SettingsService.to.font.fontList.map((e) => e.id).toList();
    final fontFamily = _resolveFontFamily(SettingsService.to.font.fontFamilyName.v, customFonts);

    final resolvedScheme = primaryColor == null
        // ThemeData's own Material 3 default when no colour is given.
        ? ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4), brightness: brightness)
        // 动态取色 tints the surfaces with the theme colour.
        : seededColorScheme(primaryColor!, brightness, tinted: SettingsService.to.theme.enableDynamicTheme.v);
    // Text takes the scheme's own onSurface. ThemeData.dark()/light() carry
    // the default (purple-tinted, dimmer) text colours, and a text theme
    // passed in explicitly is not recoloured by the scheme, so text sat a
    // shade grey and off-hue next to the scheme's icons.
    final baseTextTheme = (isDark ? ThemeData.dark() : ThemeData.light()).textTheme.apply(
      bodyColor: resolvedScheme.onSurface,
      displayColor: resolvedScheme.onSurface,
    );
    final textTheme = _buildTextTheme(base: baseTextTheme, fontFamily: fontFamily);

    var baseTheme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily,
      colorScheme: resolvedScheme,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
    );
    // 深色模式纯黑背景: pages, dialogs (the player's side panels), sheets and
    // menus go pure black; cards inside them keep their tonal greys so they
    // stay distinct.
    final pureBlack = isDark && SettingsService.to.theme.pureBlackDark.v;
    if (pureBlack) {
      baseTheme = baseTheme.copyWith(
        scaffoldBackgroundColor: Colors.black,
        canvasColor: Colors.black,
        colorScheme: baseTheme.colorScheme.copyWith(surface: Colors.black),
      );
    }

    // Floating menus follow 深色模式纯黑背景 too: a black just lifted off
    // the page (7 % of the text colour) so a menu still stands apart from
    // the black under it, without an outline.
    final menuColor = pureBlack
        ? Color.alphaBlend(baseTheme.colorScheme.onSurface.withValues(alpha: 0.07), Colors.black)
        : floatingMenuColor(baseTheme.colorScheme);

    final sliderPalette = isDark ? SliderPalette.dark : SliderPalette.light;

    return baseTheme.copyWith(
      splashFactory: NoSplash.splashFactory,
      // A smaller drag halo makes every slider shorter than Material's 48 px;
      // the thumb scales with it. Sliders are grey (see SliderPalette).
      sliderTheme: baseTheme.sliderTheme.copyWith(
        overlayShape: const RoundSliderOverlayShape(overlayRadius: kSliderThumbRadius * 2),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: kSliderThumbRadius),
        activeTrackColor: sliderPalette.track,
        inactiveTrackColor: sliderPalette.emptyTrack,
        activeTickMarkColor: sliderPalette.tick,
        inactiveTickMarkColor: sliderPalette.emptyTick,
        thumbColor: sliderPalette.track,
        overlayColor: sliderPalette.track.withValues(alpha: 0.12),
        valueIndicatorColor: sliderPalette.badge,
        valueIndicatorTextStyle: textTheme.labelMedium?.copyWith(
          color: sliderPalette.badgeText,
          fontWeight: FontWeight.bold,
        ),
      ),
      // A switch's track is the theme colour in both modes; when on, its knob
      // is white in light mode (the default) and dark grey in dark mode,
      // where the default near-black read as a hole in the track.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>(
          (states) => isDark && states.contains(WidgetState.selected) && !states.contains(WidgetState.disabled)
              ? kDarkSwitchThumbColor
              : null,
        ),
      ),
      pageTransitionsTheme: appPageTransitionsTheme,
      appBarTheme: AppBarTheme(
        elevation: 0.0,
        scrolledUnderElevation: 0.0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: semiBold),
        // Bar icons (back, menus) as bright as the bar's text.
        iconTheme: IconThemeData(color: baseTheme.colorScheme.onSurface),
        actionsIconTheme: IconThemeData(color: baseTheme.colorScheme.onSurface),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.label,
        // The Material 3 default rounds only the top corners of its 3 px
        // line, which reads as a trapezoid; same weight, both ends rounded.
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(width: 3, color: baseTheme.colorScheme.primary),
          borderRadius: const BorderRadius.all(Radius.circular(1.5)),
        ),
        tabAlignment: TabAlignment.center,
        // Bold whether selected or not, as the room panel's tabs: the colour
        // marks the current tab. A regular-weight unselected label read thin
        // on phones (bundled single-weight fonts) and the selected one only
        // faintly heavier, while desktop system fonts hid the difference.
        labelStyle: textTheme.titleMedium?.copyWith(fontWeight: bold),
        unselectedLabelStyle: textTheme.titleMedium?.copyWith(fontWeight: bold),
        labelColor: baseTheme.colorScheme.primary,
        unselectedLabelColor: baseTheme.colorScheme.onSurfaceVariant,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: semiBold),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: medium),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        // A list row reads like a settings row: the section title role over
        // the secondary role (see AppText), whatever builds it.
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodySmall?.copyWith(color: baseTheme.colorScheme.onSurfaceVariant),
        leadingAndTrailingTextStyle: textTheme.labelMedium,
        selectedColor: baseTheme.colorScheme.primary,
        selectedTileColor: baseTheme.colorScheme.primary.withValues(alpha: 0.06),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: baseTheme.colorScheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        labelStyle: textTheme.bodyMedium,
        hintStyle: textTheme.bodyMedium?.copyWith(color: baseTheme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: baseTheme.colorScheme.primary, width: 1.5),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 0,
        showDragHandle: true,
        backgroundColor: pureBlack ? Colors.black : baseTheme.colorScheme.surfaceContainer,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      // Every floating menu (MenuAnchor menus, their submenus and popup
      // menus) is the same panel: [floatingMenuColor], [kFloatingMenuShape],
      // no outline, at 75 % of the Material spacing (entries and panel
      // padding). A menu must not set its own colour or shape.
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(menuColor),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: const WidgetStatePropertyAll(kFloatingMenuShape),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: kFloatingMenuVerticalPadding)),
          visualDensity: VisualDensity.standard,
        ),
      ),
      menuButtonTheme: const MenuButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(64, kFloatingMenuItemHeight)),
          padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: kFloatingMenuItemHorizontalPadding)),
          visualDensity: VisualDensity.standard,
          // Phones otherwise pad every entry to a 48 px tap target, which
          // undid the 32 px entries on touch platforms only.
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        menuPadding: const EdgeInsets.symmetric(vertical: kFloatingMenuVerticalPadding),
        color: menuColor,
        surfaceTintColor: Colors.transparent,
        shape: kFloatingMenuShape,
      ),
      // Every Divider and VerticalDivider that does not set its own colour.
      dividerTheme: DividerThemeData(color: dividerLineColor(baseTheme.colorScheme)),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: pureBlack ? Colors.black : baseTheme.colorScheme.surfaceContainerHigh,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: semiBold),
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }
}
