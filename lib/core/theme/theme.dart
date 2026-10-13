import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/platform/platform_utils.dart';

/// Height of a floating menu entry (popup menus, the home and player menus),
/// the same on every platform: Material's adaptive density otherwise took
/// 8 px off on desktop only, leaving desktop menus cramped and phone menus
/// airy with one setting.
const double kFloatingMenuItemHeight = 32;

/// Top and bottom padding of a floating menu panel (75 % of the default 8).
const double kFloatingMenuVerticalPadding = 6;

/// Corner radius of a floating menu panel: nearly square.
const double kFloatingMenuCornerRadius = 4;

/// Opacity of a floating menu panel, the same over a page and over the
/// picture: fully opaque, nothing behind a menu shows through.
const double kFloatingMenuOpacity = 1;

/// The shape of every floating menu panel: nearly square, no outline.
const OutlinedBorder kFloatingMenuShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(kFloatingMenuCornerRadius)),
);

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

/// The colour scheme for the chosen theme colour [seed].
///
/// Material's default seeding (tonal spot) keeps only the seed's hue and
/// re-saturates it: a grey, white or light grey seed - which has almost no
/// hue - came out as a blue scheme, and muted colours such as brown drifted
/// too. A near-neutral seed now gives a true grey scheme (monochrome), and
/// any other seed a scheme whose primary stays close to it (fidelity).
ColorScheme seededColorScheme(Color seed, Brightness brightness) {
  final neutral = HSLColor.fromColor(seed).saturation < 0.12;
  return ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    dynamicSchemeVariant: neutral ? DynamicSchemeVariant.monochrome : DynamicSchemeVariant.fidelity,
  );
}

class MyTheme {
  final Color? primaryColor;
  final ColorScheme? colorScheme;

  MyTheme({this.primaryColor, this.colorScheme}) : assert(colorScheme == null || primaryColor == null);

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

    ColorScheme? scheme = colorScheme;
    if (isDark && scheme != null) {
      scheme = scheme.copyWith(error: const Color(0xFFFF6347));
    }

    final baseTextTheme = isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;
    final textTheme = _buildTextTheme(base: baseTextTheme, fontFamily: fontFamily);

    var baseTheme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily,
      colorScheme: scheme ?? (primaryColor == null ? null : seededColorScheme(primaryColor!, brightness)),
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

    return baseTheme.copyWith(
      splashFactory: NoSplash.splashFactory,
      // A smaller drag halo makes every slider about 22 px tall instead of 48;
      // the thumb shrinks with it.
      sliderTheme: baseTheme.sliderTheme.copyWith(
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 11.2),
        // Thumb and drag halo 30 % below the previous 8 / 16 px.
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.6),
      ),
      pageTransitionsTheme: appPageTransitionsTheme,
      appBarTheme: AppBarTheme(
        elevation: 0.0,
        scrolledUnderElevation: 0.0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: semiBold),
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
        labelStyle: textTheme.titleMedium?.copyWith(fontWeight: semiBold),
        unselectedLabelStyle: textTheme.titleMedium?.copyWith(fontWeight: regular),
        labelColor: baseTheme.colorScheme.primary,
        unselectedLabelColor: baseTheme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
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
          backgroundColor: WidgetStatePropertyAll(floatingMenuColor(baseTheme.colorScheme)),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: const WidgetStatePropertyAll(kFloatingMenuShape),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: kFloatingMenuVerticalPadding)),
          visualDensity: VisualDensity.standard,
        ),
      ),
      menuButtonTheme: const MenuButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(64, kFloatingMenuItemHeight)),
          // Room for a submenu arrow hanging left of the icon.
          padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
          visualDensity: VisualDensity.standard,
          // Phones otherwise pad every entry to a 48 px tap target, which
          // undid the 32 px entries on touch platforms only.
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        menuPadding: const EdgeInsets.symmetric(vertical: kFloatingMenuVerticalPadding),
        color: floatingMenuColor(baseTheme.colorScheme),
        surfaceTintColor: Colors.transparent,
        shape: kFloatingMenuShape,
      ),
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
