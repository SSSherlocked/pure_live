import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/consts/app_consts.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:pure_live/core/config/font_settings_controller.dart';
import 'package:pure_live/core/config/live_panel_layout.dart';
import 'package:pure_live/core/config/profiled_settings.dart';

class ThemeSettingsController extends GetxController {
  static const String defaultThemeModeName = 'System';
  static const String defaultLanguageName = '简体中文';
  static const double defaultSpacing = 6;
  static const double minSpacing = 0;
  static const double maxSpacing = 64;
  static final String defaultThemeColorHex = Colors.blue.hex;

  final List<Worker> _workers = [];
  final RxString themeModeName = hiveString('themeMode', defaultThemeModeName);
  final RxBool enableDynamicTheme = hiveBool('enableDynamicTheme', false);

  /// Dark mode paints page and surface backgrounds pure black (OLED); the
  /// light theme ignores it.
  final RxBool pureBlackDark = hiveBool('pureBlackDark', false);
  final RxString themeColorSwitch = hiveString('themeColorSwitch', defaultThemeColorHex);
  final RxString languageName = hiveString('language', defaultLanguageName);
  final RxDouble crossAxisSpacing = hiveDouble('crossAxisSpacing', defaultSpacing);
  final RxDouble mainAxisSpacing = hiveDouble('mainAxisSpacing', defaultSpacing);

  /// Order of the live room side panel sections (comma-separated ids).
  final RxString livePanelTabOrder = hiveString('livePanelTabOrder', LivePanelTab.defaultOrderValue);

  /// Side panel sections switched off in 侧栏标签 (comma-separated ids).
  final RxString livePanelHiddenTabs = hiveString('livePanelHiddenTabs', '');

  /// Preferred width of the live room side panel in the split layout.
  final RxDouble livePanelWidth = hiveDouble('livePanelWidth', LivePanelWidth.defaultValue);

  /// Width of the fullscreen player's side panels (关注, 弹幕设置), set by
  /// dragging their edge; separate from the room's own side panel.
  final RxDouble fullscreenPanelWidth = hiveDouble('fullscreenPanelWidth', LivePanelWidth.defaultValue);

  /// 显示模式: phone, tablet or desktop layout, or follow the screen (default).
  final RxString displayModeName = hiveString('displayMode', DisplayMode.auto.name);

  DisplayMode get displayMode => DisplayMode.parse(displayModeName.v);

  /// Hive key prefix and backup key of the per-profile settings.
  static const String profilePrefix = 'themeProfile';
  static const String profilesKey = 'themeProfiles';

  static final _crossSpacingSpec = ProfiledSpec<double>(
    'crossAxisSpacing',
    fallback: defaultSpacing,
    read: ProfiledSpec.number(min: minSpacing, max: maxSpacing),
  );
  static final _mainSpacingSpec = ProfiledSpec<double>(
    'mainAxisSpacing',
    fallback: defaultSpacing,
    read: ProfiledSpec.number(min: minSpacing, max: maxSpacing),
  );
  static final _livePanelWidthSpec = ProfiledSpec<double>(
    'livePanelWidth',
    fallback: LivePanelWidth.defaultValue,
    read: ProfiledSpec.number(min: LivePanelWidth.min, max: LivePanelWidth.max),
  );
  static final _fullscreenPanelWidthSpec = ProfiledSpec<double>(
    'fullscreenPanelWidth',
    fallback: LivePanelWidth.defaultValue,
    read: ProfiledSpec.number(min: LivePanelWidth.min, max: LivePanelWidth.max),
  );

  /// What the phone, the tablet and the desktop profile keep apart: the gaps
  /// between room cards and the widths of the room's and the fullscreen
  /// player's side panels. The theme itself, the language, the side panel's
  /// sections and the display mode stay shared.
  static List<ProfiledSpec> get profiledSpecs => [
    _crossSpacingSpec,
    _mainSpacingSpec,
    _livePanelWidthSpec,
    _fullscreenPanelWidthSpec,
  ];

  /// The per-profile settings above; their fields always hold the active
  /// profile's values (see [ProfiledSettings]).
  late final ProfiledSettings profiles = ProfiledSettings(profilePrefix, [
    _crossSpacingSpec.bind(crossAxisSpacing),
    _mainSpacingSpec.bind(mainAxisSpacing),
    _livePanelWidthSpec.bind(livePanelWidth),
    _fullscreenPanelWidthSpec.bind(fullscreenPanelWidth),
  ]);

  /// The profile the per-profile fields hold.
  Rx<DisplayProfile> get profile => profiles.profile;

  void useProfile(DisplayProfile profile) => profiles.use(profile);

  List<LivePanelTab> get resolvedLivePanelTabOrder => LivePanelTab.decode(livePanelTabOrder.v);

  Set<LivePanelTab> get hiddenLivePanelTabs => LivePanelTab.decodeSet(livePanelHiddenTabs.v);

  /// The sections a room's side panel shows, in order.
  List<LivePanelTab> get visibleLivePanelTabs =>
      LivePanelTab.visible(resolvedLivePanelTabOrder, hiddenLivePanelTabs);

  static String normalizeLivePanelHiddenTabs(String value) =>
      LivePanelTab.encode(LivePanelTab.defaultOrder.where(LivePanelTab.decodeSet(value).contains));

  String get resolvedThemeModeName => normalizeThemeMode(themeModeName.v);
  ThemeMode get themeMode => AppConsts.themeModes[resolvedThemeModeName]!;
  String get resolvedThemeColorHex => normalizeThemeColor(themeColorSwitch.v);
  Color get themeColor => HexColor(resolvedThemeColorHex);
  String get resolvedLanguageName => normalizeLanguage(languageName.v);
  Locale get language => AppConsts.languages[resolvedLanguageName]!;
  double get resolvedCrossAxisSpacing => normalizeSpacing(crossAxisSpacing.v);
  double get resolvedMainAxisSpacing => normalizeSpacing(mainAxisSpacing.v);

  final Map<ColorSwatch<Object>, String> colorsNameMap = AppConsts.themeColors.map(
    (k, v) => MapEntry(ColorTools.createPrimarySwatch(v), k),
  );

  @override
  void onInit() {
    super.onInit();
    _normalizeStoredTheme();
    profiles.init();
    _workers.addAll([
      ever<String>(themeModeName, (value) => _repairString(themeModeName, value, normalizeThemeMode)),
      ever<String>(themeColorSwitch, (value) => _repairString(themeColorSwitch, value, normalizeThemeColor)),
      ever<String>(languageName, (value) => _repairString(languageName, value, normalizeLanguage)),
      everAll([crossAxisSpacing, mainAxisSpacing], (_) => _repairSpacingAndRefreshTheme()),
    ]);
  }

  @override
  void onClose() {
    for (final worker in _workers) {
      worker.dispose();
    }
    _workers.clear();
    profiles.dispose();
    super.onClose();
  }

  static String normalizeThemeMode(String value) {
    final normalized = value.trim().toLowerCase();
    return AppConsts.themeModes.keys.firstWhere(
      (candidate) => candidate.toLowerCase() == normalized,
      orElse: () => defaultThemeModeName,
    );
  }

  static String normalizeLanguage(String value) {
    final normalized = value.trim().toLowerCase();
    return AppConsts.languages.keys.firstWhere(
      (candidate) => candidate.toLowerCase() == normalized,
      orElse: () => defaultLanguageName,
    );
  }

  static String? _canonicalHex(String value) {
    var normalized = value.trim().toUpperCase();
    if (normalized.startsWith('#')) {
      normalized = normalized.substring(1);
    } else if (normalized.startsWith('0X')) {
      normalized = normalized.substring(2);
    }
    return RegExp(r'^(?:[0-9A-F]{6}|[0-9A-F]{8})$').hasMatch(normalized) ? normalized : null;
  }

  static String normalizeThemeColor(String value) => _canonicalHex(value) ?? defaultThemeColorHex;

  static double normalizeSpacing(num value) {
    final converted = value.toDouble();
    if (!converted.isFinite) return defaultSpacing;
    return converted.clamp(minSpacing, maxSpacing).toDouble();
  }

  static String normalizeLivePanelTabOrder(String value) => LivePanelTab.encode(LivePanelTab.decode(value));

  static double _parseLivePanelWidth(Object? value) {
    final parsed = ((value ?? LivePanelWidth.defaultValue) as num).toDouble();
    if (!parsed.isFinite) throw const FormatException('Live panel width must be finite');
    return LivePanelWidth.normalize(parsed);
  }

  static double _parseSpacing(Object? value) {
    final parsed = ((value ?? defaultSpacing) as num).toDouble();
    if (!parsed.isFinite) throw const FormatException('Theme spacing must be finite');
    return normalizeSpacing(parsed);
  }

  void _normalizeStoredTheme() {
    themeModeName.v = resolvedThemeModeName;
    themeColorSwitch.v = resolvedThemeColorHex;
    languageName.v = resolvedLanguageName;
    crossAxisSpacing.v = resolvedCrossAxisSpacing;
    mainAxisSpacing.v = resolvedMainAxisSpacing;
  }

  void _repairString(RxString setting, String value, String Function(String) normalize) {
    final normalized = normalize(value);
    if (normalized != value) setting.v = normalized;
  }

  void _repairSpacingAndRefreshTheme() {
    final cross = resolvedCrossAxisSpacing;
    final main = resolvedMainAxisSpacing;
    if (cross != crossAxisSpacing.v || main != mainAxisSpacing.v) {
      if (cross != crossAxisSpacing.v) crossAxisSpacing.v = cross;
      if (main != mainAxisSpacing.v) mainAxisSpacing.v = main;
      return;
    }
    Get.find<FontSettingsController>().refreshSystemTheme();
  }

  void changeThemeMode(String mode) {
    themeModeName.v = normalizeThemeMode(mode);
    Get.changeThemeMode(themeMode);
  }

  void changeThemeColorSwitch(String hex) {
    themeColorSwitch.v = normalizeThemeColor(hex);
    final color = themeColor;
    final t = MyTheme(primaryColor: color);
    Get.changeTheme(t.lightThemeData);
    Get.changeTheme(t.darkThemeData);
  }

  Future<void> changeLanguage(String v, BuildContext context) async {
    languageName.value = normalizeLanguage(v);
    final locale = language;
    await context.setLocale(locale);
    Get.updateLocale(locale);
  }

  Map<String, dynamic> toJson() {
    return {
      'themeMode': resolvedThemeModeName,
      'enableDynamicTheme': enableDynamicTheme.v,
      'pureBlackDark': pureBlackDark.v,
      'themeColorSwitch': resolvedThemeColorHex,
      'language': resolvedLanguageName,
      'crossAxisSpacing': resolvedCrossAxisSpacing,
      'mainAxisSpacing': resolvedMainAxisSpacing,
      'livePanelTabOrder': normalizeLivePanelTabOrder(livePanelTabOrder.v),
      'livePanelHiddenTabs': normalizeLivePanelHiddenTabs(livePanelHiddenTabs.v),
      'livePanelWidth': LivePanelWidth.normalize(livePanelWidth.v),
      'fullscreenPanelWidth': LivePanelWidth.normalize(fullscreenPanelWidth.v),
      'displayMode': displayMode.name,
      // The single keys above carry the active profile's values (what an
      // older build restores); this carries all three profiles.
      profilesKey: profiles.export(),
    };
  }

  /// Parse the complete section without notifying observers or persisting values.
  static Map<String, dynamic> parseConfig(Map<String, dynamic> json) {
    final parsed = <String, dynamic>{
      'themeModeName': normalizeThemeMode((json['themeMode'] ?? defaultThemeModeName) as String),
      'enableDynamicTheme': (json['enableDynamicTheme'] ?? false) as bool,
      'pureBlackDark': (json['pureBlackDark'] ?? false) as bool,
      'themeColorSwitch': normalizeThemeColor((json['themeColorSwitch'] ?? defaultThemeColorHex) as String),
      'languageName': normalizeLanguage((json['language'] ?? json['languageName'] ?? defaultLanguageName) as String),
      'crossAxisSpacing': _parseSpacing(json['crossAxisSpacing']),
      'mainAxisSpacing': _parseSpacing(json['mainAxisSpacing']),
      'livePanelTabOrder': normalizeLivePanelTabOrder(
        (json['livePanelTabOrder'] ?? LivePanelTab.defaultOrderValue) as String,
      ),
      'livePanelHiddenTabs': normalizeLivePanelHiddenTabs((json['livePanelHiddenTabs'] ?? '') as String),
      'livePanelWidth': _parseLivePanelWidth(json['livePanelWidth']),
      'fullscreenPanelWidth': _parseLivePanelWidth(json['fullscreenPanelWidth']),
      'displayMode': DisplayMode.parse(json['displayMode']).name,
    };
    // A backup from before the profiles has only the single values: every
    // profile takes them.
    parsed[profilesKey] = ProfiledSettings.parse(profiledSpecs, json[profilesKey], legacy: (_) => parsed);
    return parsed;
  }

  void fromJson(Map<String, dynamic> json) {
    final parsed = parseConfig(json);
    themeModeName.v = parsed['themeModeName'];
    enableDynamicTheme.v = parsed['enableDynamicTheme'];
    pureBlackDark.v = parsed['pureBlackDark'];
    themeColorSwitch.v = parsed['themeColorSwitch'];
    languageName.v = parsed['languageName'];
    livePanelTabOrder.v = parsed['livePanelTabOrder'];
    livePanelHiddenTabs.v = parsed['livePanelHiddenTabs'];
    displayModeName.v = parsed['displayMode'];
    // The spacing and panel widths come from the restored active profile.
    profiles.restore(parsed[profilesKey] as Map<String, dynamic>);
  }

  static Map<String, dynamic> extractConfig(Map<String, dynamic>? rootConfig) {
    final theme = rootConfig?['theme'] as Map<String, dynamic>? ?? {};
    final parsed = parseConfig(theme);
    return {
      'themeMode': parsed['themeModeName'],
      'enableDynamicTheme': parsed['enableDynamicTheme'],
      'pureBlackDark': parsed['pureBlackDark'],
      'themeColorSwitch': parsed['themeColorSwitch'],
      'language': parsed['languageName'],
      'crossAxisSpacing': parsed['crossAxisSpacing'],
      'mainAxisSpacing': parsed['mainAxisSpacing'],
      'livePanelTabOrder': parsed['livePanelTabOrder'],
      'livePanelHiddenTabs': parsed['livePanelHiddenTabs'],
      'livePanelWidth': parsed['livePanelWidth'],
      'fullscreenPanelWidth': parsed['fullscreenPanelWidth'],
      'displayMode': parsed['displayMode'],
      profilesKey: parsed[profilesKey],
    };
  }

  static Map<String, dynamic> mergeConfig(Map<String, dynamic> rootConfig, Map<String, dynamic> updateFields) {
    final theme = Map<String, dynamic>.from(rootConfig['theme'] ?? {});
    updateFields.forEach((k, v) => theme[k] = v);
    rootConfig['theme'] = theme;
    return rootConfig;
  }
}
