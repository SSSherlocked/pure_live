import 'package:flutter/widgets.dart';

/// The display mode the viewer picked in 设置 › 通用 › 主题.
enum DisplayMode {
  /// Follow the screen: phone layout up to [AppLayout.wideBreakpoint], wide
  /// beyond it; touch interaction on phones, pointer interaction elsewhere.
  auto,

  /// Phone layout with touch interaction.
  phone,

  /// Wide layout with touch interaction.
  tablet,

  /// Wide layout with pointer (mouse) interaction.
  desktop;

  static DisplayMode parse(Object? value) {
    final name = value?.toString().trim();
    return DisplayMode.values.firstWhere((mode) => mode.name == name, orElse: () => DisplayMode.auto);
  }
}

/// How the app lays itself out and expects to be operated — never what the
/// platform can do.
///
/// A display mode changes layout and interaction only. Platform capabilities
/// (window chrome, picture-in-picture, orientation control, file access, the
/// tray) keep following `PlatformUtils`: a phone in desktop mode does not grow
/// window buttons.
@immutable
class AppLayout {
  const AppLayout({required this.wide, required this.pointer});

  /// Beyond this width [DisplayMode.auto] uses the wide layout.
  static const double wideBreakpoint = 680;

  /// The wide layout: navigation rail, side-by-side room page, larger chrome.
  /// False is the phone layout: bottom bar, stacked room page.
  final bool wide;

  /// Pointer (mouse) interaction: hover reveals controls, wheel scrolling,
  /// paged lists. False is touch interaction.
  final bool pointer;

  bool get phone => !wide;
  bool get touch => !pointer;

  /// Lists page with a page bar instead of scrolling endlessly and refreshing
  /// by pulling down.
  bool get pagedLists => wide && pointer;

  /// The layout [mode] gives a screen [width] wide on a [mobilePlatform].
  static AppLayout resolve({required DisplayMode mode, required double width, required bool mobilePlatform}) {
    return switch (mode) {
      DisplayMode.auto => AppLayout(wide: width > wideBreakpoint, pointer: !mobilePlatform),
      DisplayMode.phone => const AppLayout(wide: false, pointer: false),
      DisplayMode.tablet => const AppLayout(wide: true, pointer: false),
      DisplayMode.desktop => const AppLayout(wide: true, pointer: true),
    };
  }

  /// The layout last published by [AppLayoutScope], for code that has no
  /// [BuildContext] (controllers). Widgets use [of], which also rebuilds them
  /// when the layout changes.
  static AppLayout current = const AppLayout(wide: false, pointer: false);

  static AppLayout of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLayoutScope>()?.layout ?? current;

  @override
  bool operator ==(Object other) => other is AppLayout && other.wide == wide && other.pointer == pointer;

  @override
  int get hashCode => Object.hash(wide, pointer);
}

/// Publishes the app's [AppLayout] to everything below it.
class AppLayoutScope extends InheritedWidget {
  const AppLayoutScope({super.key, required this.layout, required super.child});

  final AppLayout layout;

  @override
  bool updateShouldNotify(AppLayoutScope oldWidget) => oldWidget.layout != layout;
}
