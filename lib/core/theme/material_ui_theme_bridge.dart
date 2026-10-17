import 'package:flutter/material.dart' as flutter;
import 'package:material_ui/material_ui.dart' as material;

// The `material_ui` theme bridge. It lived in dynamic_color_adapter.dart until
// 2026-10-17 (4a3b40e7d dropped dynamic_color and with it the whole file);
// AppShell still wraps the Router in [MaterialUiThemeBridge], and
// flex_color_picker 4.x / cached_network_image 4.x still read the decoupled
// Material library's theme, so the bridge stays.

/// Converts the framework color model back to the independent Material widget
/// library used by a few upgraded packages.
///
/// [material.ColorScheme]'s public constructor intentionally exposes only its
/// compatibility roles. Start with those required roles and use `copyWith` to
/// preserve the complete Material 3 palette instead of regenerating colors from
/// a seed (which would subtly change dynamic and user-selected themes).
material.ColorScheme toMaterialUiColorScheme(flutter.ColorScheme source) {
  return material.ColorScheme(
    brightness: source.brightness,
    primary: source.primary,
    onPrimary: source.onPrimary,
    secondary: source.secondary,
    onSecondary: source.onSecondary,
    error: source.error,
    onError: source.onError,
    surface: source.surface,
    onSurface: source.onSurface,
  ).copyWith(
    primaryContainer: source.primaryContainer,
    onPrimaryContainer: source.onPrimaryContainer,
    primaryFixed: source.primaryFixed,
    primaryFixedDim: source.primaryFixedDim,
    onPrimaryFixed: source.onPrimaryFixed,
    onPrimaryFixedVariant: source.onPrimaryFixedVariant,
    secondaryContainer: source.secondaryContainer,
    onSecondaryContainer: source.onSecondaryContainer,
    secondaryFixed: source.secondaryFixed,
    secondaryFixedDim: source.secondaryFixedDim,
    onSecondaryFixed: source.onSecondaryFixed,
    onSecondaryFixedVariant: source.onSecondaryFixedVariant,
    tertiary: source.tertiary,
    onTertiary: source.onTertiary,
    tertiaryContainer: source.tertiaryContainer,
    onTertiaryContainer: source.onTertiaryContainer,
    tertiaryFixed: source.tertiaryFixed,
    tertiaryFixedDim: source.tertiaryFixedDim,
    onTertiaryFixed: source.onTertiaryFixed,
    onTertiaryFixedVariant: source.onTertiaryFixedVariant,
    errorContainer: source.errorContainer,
    onErrorContainer: source.onErrorContainer,
    surfaceDim: source.surfaceDim,
    surfaceBright: source.surfaceBright,
    surfaceContainerLowest: source.surfaceContainerLowest,
    surfaceContainerLow: source.surfaceContainerLow,
    surfaceContainer: source.surfaceContainer,
    surfaceContainerHigh: source.surfaceContainerHigh,
    surfaceContainerHighest: source.surfaceContainerHighest,
    onSurfaceVariant: source.onSurfaceVariant,
    outline: source.outline,
    outlineVariant: source.outlineVariant,
    shadow: source.shadow,
    scrim: source.scrim,
    inverseSurface: source.inverseSurface,
    onInverseSurface: source.onInverseSurface,
    inversePrimary: source.inversePrimary,
    surfaceTint: source.surfaceTint,
  );
}

material.TextTheme _toMaterialUiTextTheme(flutter.TextTheme source) {
  return material.TextTheme(
    displayLarge: source.displayLarge,
    displayMedium: source.displayMedium,
    displaySmall: source.displaySmall,
    headlineLarge: source.headlineLarge,
    headlineMedium: source.headlineMedium,
    headlineSmall: source.headlineSmall,
    titleLarge: source.titleLarge,
    titleMedium: source.titleMedium,
    titleSmall: source.titleSmall,
    bodyLarge: source.bodyLarge,
    bodyMedium: source.bodyMedium,
    bodySmall: source.bodySmall,
    labelLarge: source.labelLarge,
    labelMedium: source.labelMedium,
    labelSmall: source.labelSmall,
  );
}

/// Mirrors the active Flutter theme into `material_ui`.
///
/// Flutter 3.47 decoupled some Material packages from `flutter/material.dart`.
/// Without this bridge those widgets silently use a light fallback theme, so a
/// color-picker dialog can look unrelated to the application's selected mode.
material.ThemeData toMaterialUiThemeData(flutter.ThemeData source) {
  return material.ThemeData(
    brightness: source.brightness,
    colorScheme: toMaterialUiColorScheme(source.colorScheme),
    platform: source.platform,
    useMaterial3: source.useMaterial3,
    canvasColor: source.canvasColor,
    cardColor: source.cardColor,
    disabledColor: source.disabledColor,
    dividerColor: source.dividerColor,
    focusColor: source.focusColor,
    highlightColor: source.highlightColor,
    hintColor: source.hintColor,
    hoverColor: source.hoverColor,
    scaffoldBackgroundColor: source.scaffoldBackgroundColor,
    shadowColor: source.shadowColor,
    splashColor: source.splashColor,
    textTheme: _toMaterialUiTextTheme(source.textTheme),
    primaryTextTheme: _toMaterialUiTextTheme(source.primaryTextTheme),
  );
}

/// Supplies the matching `material_ui` inherited theme to packages that have
/// migrated ahead of the rest of this application.
class MaterialUiThemeBridge extends flutter.StatelessWidget {
  const MaterialUiThemeBridge({super.key, required this.child});

  final flutter.Widget child;

  @override
  flutter.Widget build(flutter.BuildContext context) {
    return material.Theme(data: toMaterialUiThemeData(flutter.Theme.of(context)), child: child);
  }
}
