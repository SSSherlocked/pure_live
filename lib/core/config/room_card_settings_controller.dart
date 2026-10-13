import 'dart:convert';

import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/storage/hive_pref_util.dart';
import 'package:pure_live/core/config/profiled_settings.dart';

enum RoomCardPlatformBadgeMode { automatic, always, hidden }

enum RoomCardLayout { cover, compact }

enum RoomCardPreset {
  compact('compact'),
  standard('normal'),
  detailed('rich'),
  custom('custom');

  const RoomCardPreset(this.storageKey);

  final String storageKey;
}

@immutable
class RoomCardAppearance {
  const RoomCardAppearance({
    required this.layout,
    required this.showAvatar,
    required this.showAnchorName,
    required this.showPlatformBadge,
    required this.automaticPlatformBadge,
    required this.showAudience,
    required this.showReplayBadge,
    required this.cornerRadius,
  });

  static const double defaultCornerRadius = 20;
  static const double minCornerRadius = 0;
  static const double maxCornerRadius = 32;

  // The compact row follows the 关注 panel: platform tag and heat on the right.
  static const compact = RoomCardAppearance(
    layout: RoomCardLayout.compact,
    showAvatar: true,
    showAnchorName: true,
    showPlatformBadge: true,
    automaticPlatformBadge: false,
    showAudience: true,
    showReplayBadge: true,
    cornerRadius: 12,
  );

  static const standard = RoomCardAppearance(
    layout: RoomCardLayout.cover,
    showAvatar: true,
    showAnchorName: true,
    showPlatformBadge: false,
    automaticPlatformBadge: true,
    showAudience: true,
    showReplayBadge: true,
    cornerRadius: defaultCornerRadius,
  );

  static const detailed = RoomCardAppearance(
    layout: RoomCardLayout.cover,
    showAvatar: true,
    showAnchorName: true,
    showPlatformBadge: true,
    automaticPlatformBadge: false,
    showAudience: true,
    showReplayBadge: true,
    cornerRadius: defaultCornerRadius,
  );

  final RoomCardLayout layout;
  final bool showAvatar;
  final bool showAnchorName;
  final bool showPlatformBadge;
  final bool automaticPlatformBadge;
  final bool showAudience;
  final bool showReplayBadge;
  final double cornerRadius;

  RoomCardPlatformBadgeMode get platformBadgeMode {
    if (automaticPlatformBadge) return RoomCardPlatformBadgeMode.automatic;
    return showPlatformBadge ? RoomCardPlatformBadgeMode.always : RoomCardPlatformBadgeMode.hidden;
  }

  static RoomCardAppearance fromPreset(RoomCardPreset preset) {
    return switch (preset) {
      RoomCardPreset.compact => compact,
      RoomCardPreset.detailed => detailed,
      RoomCardPreset.standard || RoomCardPreset.custom => standard,
    };
  }

  static double normalizeCornerRadius(num value) {
    final converted = value.toDouble();
    if (!converted.isFinite) return defaultCornerRadius;
    return converted.clamp(minCornerRadius, maxCornerRadius).toDouble();
  }

  static RoomCardAppearance fromJson(
    Map<String, dynamic> json, {
    RoomCardAppearance fallback = standard,
    bool strict = false,
  }) {
    bool readBool(String currentKey, String legacyKey, bool defaultValue) {
      final value = json.containsKey(currentKey) ? json[currentKey] : json[legacyKey];
      if (value == null) return defaultValue;
      if (strict && value is! bool) throw FormatException('$currentKey must be a boolean');
      return value is bool ? value : defaultValue;
    }

    double readRadius() {
      final value = json['cornerRadius'] ?? json['cardBorderRadius'];
      if (value == null) return fallback.cornerRadius;
      if (strict && value is! num) throw const FormatException('cornerRadius must be numeric');
      if (value is! num) return fallback.cornerRadius;
      if (strict && !value.toDouble().isFinite) throw const FormatException('cornerRadius must be finite');
      return normalizeCornerRadius(value);
    }

    RoomCardLayout readLayout() {
      final value = json['layout'];
      if (value != null) {
        if (strict && value is! String) throw const FormatException('layout must be a string');
        if (value is String) {
          final normalized = value.trim().toLowerCase();
          if (normalized == RoomCardLayout.cover.name) return RoomCardLayout.cover;
          if (normalized == RoomCardLayout.compact.name || normalized == 'list' || normalized == 'listtile') {
            return RoomCardLayout.compact;
          }
          if (strict) throw const FormatException('layout must be cover or compact');
        }
        return fallback.layout;
      }

      final legacy = json['showAsListTile'];
      if (legacy == null) return fallback.layout;
      if (strict && legacy is! bool) throw const FormatException('showAsListTile must be a boolean');
      if (legacy is! bool) return fallback.layout;
      return legacy ? RoomCardLayout.compact : RoomCardLayout.cover;
    }

    final hasExplicitPlatformValue = json.containsKey('showPlatformBadge') || json.containsKey('showPlatform');
    final showPlatformBadge = readBool('showPlatformBadge', 'showPlatform', fallback.showPlatformBadge);
    final automaticPlatformBadge = json.containsKey('automaticPlatformBadge')
        ? readBool('automaticPlatformBadge', 'automaticPlatformBadge', fallback.automaticPlatformBadge)
        : hasExplicitPlatformValue
        ? false
        : fallback.automaticPlatformBadge;

    // 3.1.4 persisted the compact preset as visibility flags only. The preset
    // key still proves that this exact snapshot was not a user-custom layout,
    // so upgrade it to the restored compact topology and identity fields.
    final isBrokenCompactPresetSnapshot =
        fallback.layout == RoomCardLayout.compact &&
        !json.containsKey('layout') &&
        !json.containsKey('showAsListTile') &&
        readBool('showAvatar', 'showAvatar', fallback.showAvatar) == false &&
        readBool('showAnchorName', 'showSubtitle', fallback.showAnchorName) == false &&
        showPlatformBadge == false &&
        automaticPlatformBadge == false &&
        readBool('showAudience', 'showAudience', fallback.showAudience) == true &&
        readBool('showReplayBadge', 'showRecordBadge', fallback.showReplayBadge) == true &&
        readRadius() == compact.cornerRadius;
    if (isBrokenCompactPresetSnapshot) return compact;

    return RoomCardAppearance(
      layout: readLayout(),
      showAvatar: readBool('showAvatar', 'showAvatar', fallback.showAvatar),
      showAnchorName: readBool('showAnchorName', 'showSubtitle', fallback.showAnchorName),
      showPlatformBadge: showPlatformBadge,
      automaticPlatformBadge: showPlatformBadge ? false : automaticPlatformBadge,
      showAudience: readBool('showAudience', 'showAudience', fallback.showAudience),
      showReplayBadge: readBool('showReplayBadge', 'showRecordBadge', fallback.showReplayBadge),
      cornerRadius: readRadius(),
    );
  }

  RoomCardAppearance copyWith({
    RoomCardLayout? layout,
    bool? showAvatar,
    bool? showAnchorName,
    bool? showPlatformBadge,
    bool? automaticPlatformBadge,
    bool? showAudience,
    bool? showReplayBadge,
    double? cornerRadius,
  }) {
    return RoomCardAppearance(
      layout: layout ?? this.layout,
      showAvatar: showAvatar ?? this.showAvatar,
      showAnchorName: showAnchorName ?? this.showAnchorName,
      showPlatformBadge: showPlatformBadge ?? this.showPlatformBadge,
      automaticPlatformBadge: automaticPlatformBadge ?? this.automaticPlatformBadge,
      showAudience: showAudience ?? this.showAudience,
      showReplayBadge: showReplayBadge ?? this.showReplayBadge,
      cornerRadius: normalizeCornerRadius(cornerRadius ?? this.cornerRadius),
    );
  }

  RoomCardAppearance withPlatformBadgeMode(RoomCardPlatformBadgeMode mode) {
    return copyWith(
      showPlatformBadge: mode == RoomCardPlatformBadgeMode.always,
      automaticPlatformBadge: mode == RoomCardPlatformBadgeMode.automatic,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'layout': layout.name,
      'showAvatar': showAvatar,
      'showAnchorName': showAnchorName,
      'showPlatformBadge': showPlatformBadge,
      'automaticPlatformBadge': automaticPlatformBadge,
      'showAudience': showAudience,
      'showReplayBadge': showReplayBadge,
      'cornerRadius': normalizeCornerRadius(cornerRadius),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is RoomCardAppearance &&
        other.layout == layout &&
        other.showAvatar == showAvatar &&
        other.showAnchorName == showAnchorName &&
        other.showPlatformBadge == showPlatformBadge &&
        other.automaticPlatformBadge == automaticPlatformBadge &&
        other.showAudience == showAudience &&
        other.showReplayBadge == showReplayBadge &&
        other.cornerRadius == cornerRadius;
  }

  @override
  int get hashCode => Object.hash(
    layout,
    showAvatar,
    showAnchorName,
    showPlatformBadge,
    automaticPlatformBadge,
    showAudience,
    showReplayBadge,
    cornerRadius,
  );
}

class RoomCardSettingsController extends GetxController {
  static RoomCardSettingsController get to => Get.find<RoomCardSettingsController>();

  /// Hive key prefix and backup key of the per-profile settings.
  static const String profilePrefix = 'roomCardProfile';
  static const String profilesKey = 'roomCardProfiles';

  /// The card look of the active profile.
  final Rx<RoomCardAppearance> config = Rx<RoomCardAppearance>(RoomCardAppearance.standard);

  /// Fixed card width for room grids in the active profile. 0 keeps the
  /// automatic layout (columns by window width, cards stretch to fill); a
  /// width keeps every card that size and fits as many columns as the window
  /// allows.
  final RxDouble cardWidth = RxDouble(autoCardWidth);

  /// Columns per row when the card width is not fixed, in the active profile.
  /// 0 keeps the automatic count (by window width); a count keeps that many
  /// columns and the cards stretch to fill the row.
  final RxInt columns = RxInt(autoColumns);

  static const double autoCardWidth = 0;
  static const double minCardWidth = 140;
  static const double maxCardWidth = 600;
  static const double defaultFixedCardWidth = 320;

  static double normalizeCardWidth(double value) {
    if (!value.isFinite || value <= 0) return autoCardWidth;
    return value.clamp(minCardWidth, maxCardWidth).toDouble();
  }

  static const int autoColumns = 0;
  static const int maxColumns = 20;

  static int normalizeColumns(num value) =>
      value.isFinite ? value.round().clamp(autoColumns, maxColumns).toInt() : autoColumns;

  static final _configSpec = ProfiledSpec<RoomCardAppearance>(
    'config',
    fallback: RoomCardAppearance.standard,
    read: (raw) {
      if (raw is! Map) return null;
      try {
        return _normalizeConfig(RoomCardAppearance.fromJson(Map<String, dynamic>.from(raw)));
      } catch (_) {
        return null;
      }
    },
    write: (value) => value.toJson(),
  );
  static final _cardWidthSpec = ProfiledSpec<double>(
    'cardWidth',
    fallback: autoCardWidth,
    read: (raw) => raw is num ? normalizeCardWidth(raw.toDouble()) : null,
  );
  static final _columnsSpec = ProfiledSpec<int>(
    'columns',
    fallback: autoColumns,
    read: ProfiledSpec.integer(normalizeColumns),
  );

  /// What the phone, the tablet and the desktop profile keep apart: the card
  /// look, the fixed card width and the column count. The 关注 page's
  /// platform tabs and room order stay shared.
  static List<ProfiledSpec> get profiledSpecs => [_configSpec, _cardWidthSpec, _columnsSpec];

  /// The per-profile settings above; [config], [cardWidth] and [columns]
  /// always hold the active profile's values (see [ProfiledSettings]).
  late final ProfiledSettings profiles = ProfiledSettings(profilePrefix, [
    _configSpec.bind(config),
    _cardWidthSpec.bind(cardWidth),
    _columnsSpec.bind(columns),
  ]);

  /// The profile [config], [cardWidth] and [columns] hold.
  Rx<DisplayProfile> get profile => profiles.profile;

  void useProfile(DisplayProfile profile) => profiles.use(profile);

  /// The fixed card width for the current profile, or 0 for automatic.
  double get currentCardWidth => normalizeCardWidth(cardWidth.v);

  /// The chosen column count for the current profile, or 0 for automatic.
  int get currentColumns => normalizeColumns(columns.v);

  /// Whether the home 关注 page shows its platform tab bar; without it the
  /// page lists every platform's rooms.
  final RxBool showFavoritePlatformTabs = hiveBool('favorite_show_platform_tabs', true);

  /// How the home 关注 page orders its rooms; a [FavoriteSortMode] name.
  final RxString favoriteSortModeName = hiveString('favorite_sort_mode', FavoriteSortMode.name.name);

  FavoriteSortMode get favoriteSortMode => FavoriteSortMode.fromName(favoriteSortModeName.v);

  static RoomCardPreset normalizePreset(String? value) {
    final key = value?.trim().toLowerCase();
    return RoomCardPreset.values.firstWhere(
      (candidate) => candidate.storageKey == key,
      orElse: () => RoomCardPreset.standard,
    );
  }

  /// The phone profile defaults to the compact rows; tablet and desktop to
  /// cover cards.
  static RoomCardPreset defaultPresetFor(DisplayProfile profile) =>
      profile == DisplayProfile.phone ? RoomCardPreset.compact : RoomCardPreset.standard;

  /// Hive keys of the settings kept once for the narrow and once for the wide
  /// layout before the profiles. Read once as the profiles' seed: the narrow
  /// set becomes the phone profile, the wide set the tablet and desktop ones.
  static String _legacyKey(DisplayProfile profile, String name) =>
      'room_card_${profile == DisplayProfile.phone ? 'mobile' : 'desktop'}_$name';

  static Map<String, dynamic> _legacySeed(DisplayProfile profile) {
    final storedPreset = HivePrefUtil.getString(_legacyKey(profile, 'preset'));
    final presetFallback = RoomCardAppearance.fromPreset(
      storedPreset == null || storedPreset.trim().isEmpty ? defaultPresetFor(profile) : normalizePreset(storedPreset),
    );
    var appearance = presetFallback;
    final storedConfig = HivePrefUtil.getString(_legacyKey(profile, 'config'));
    if (storedConfig != null && storedConfig.isNotEmpty) {
      try {
        final decoded = jsonDecode(storedConfig);
        if (decoded is Map) {
          appearance = RoomCardAppearance.fromJson(Map<String, dynamic>.from(decoded), fallback: presetFallback);
        }
      } catch (_) {}
    }
    return {
      'config': _normalizeConfig(appearance).toJson(),
      'cardWidth': HivePrefUtil.getDouble(_legacyKey(profile, 'width')) ?? autoCardWidth,
      'columns': HivePrefUtil.getInt(_legacyKey(profile, 'columns')) ?? autoColumns,
    };
  }

  @override
  void onInit() {
    super.onInit();
    profiles.init(seed: _legacySeed);
  }

  @override
  void onClose() {
    profiles.dispose();
    super.onClose();
  }

  RoomCardAppearance resolve() => config.value;

  void updateConfig(RoomCardAppearance value) => config.value = _normalizeConfig(value);

  /// Puts the current profile back to its default preset.
  void reset() => config.value = RoomCardAppearance.fromPreset(defaultPresetFor(profile.value));

  static RoomCardAppearance _normalizeConfig(RoomCardAppearance value) {
    var normalized = value.copyWith(cornerRadius: value.cornerRadius);
    if (normalized.showPlatformBadge && normalized.automaticPlatformBadge) {
      normalized = normalized.copyWith(automaticPlatformBadge: false);
    }
    return normalized;
  }

  static RoomCardPreset _matchingPreset(RoomCardAppearance config) {
    if (config == RoomCardAppearance.compact) return RoomCardPreset.compact;
    if (config == RoomCardAppearance.standard) return RoomCardPreset.standard;
    if (config == RoomCardAppearance.detailed) return RoomCardPreset.detailed;
    return RoomCardPreset.custom;
  }

  Map<String, dynamic> toJson() {
    // The mobile/desktop keys are what an older build restores (its narrow
    // and wide layout): the phone profile, and the tablet profile when that
    // is the one in use, else the desktop one.
    final mobile = profiles.mapFor(DisplayProfile.phone);
    final desktop = profiles.mapFor(
      profile.value == DisplayProfile.tablet ? DisplayProfile.tablet : DisplayProfile.desktop,
    );
    final mobileConfig = _configSpec.decode(mobile['config']);
    final desktopConfig = _configSpec.decode(desktop['config']);
    return {
      'mobilePreset': _matchingPreset(mobileConfig).storageKey,
      'desktopPreset': _matchingPreset(desktopConfig).storageKey,
      'mobileConfig': mobileConfig.toJson(),
      'desktopConfig': desktopConfig.toJson(),
      'mobileCardWidth': mobile['cardWidth'],
      'desktopCardWidth': desktop['cardWidth'],
      'mobileColumns': mobile['columns'],
      'desktopColumns': desktop['columns'],
      'showFavoritePlatformTabs': showFavoritePlatformTabs.v,
      'favoriteSortMode': favoriteSortMode.name,
      profilesKey: profiles.export(),
    };
  }

  static Map<String, dynamic> parseConfig(Map<String, dynamic> json) {
    final source = json['roomCard'] is Map ? Map<String, dynamic>.from(json['roomCard'] as Map) : json;
    final narrowPreset = normalizePreset(_readString(source, 'mobilePreset', legacyKey: 'room_card_mobile_preset'));
    final widePreset = normalizePreset(_readString(source, 'desktopPreset', legacyKey: 'room_card_desktop_preset'));
    final narrowJson = _readConfigMap(source, 'mobileConfig', legacyKey: 'room_card_mobile_config');
    final wideJson = _readConfigMap(source, 'desktopConfig', legacyKey: 'room_card_desktop_config');
    final narrow = narrowJson == null
        ? RoomCardAppearance.fromPreset(narrowPreset)
        : RoomCardAppearance.fromJson(narrowJson, fallback: RoomCardAppearance.fromPreset(narrowPreset), strict: true);
    final wide = wideJson == null
        ? RoomCardAppearance.fromPreset(widePreset)
        : RoomCardAppearance.fromJson(
            wideJson,
            fallback: RoomCardAppearance.fromPreset(widePreset),
            strict: true,
          );
    final parsed = <String, dynamic>{
      'mobilePreset': _matchingPreset(narrow).storageKey,
      'desktopPreset': _matchingPreset(wide).storageKey,
      'mobileConfig': narrow,
      'desktopConfig': wide,
      'mobileCardWidth': _readCardWidth(source, 'mobileCardWidth'),
      'desktopCardWidth': _readCardWidth(source, 'desktopCardWidth'),
      'mobileColumns': _readColumns(source, 'mobileColumns'),
      'desktopColumns': _readColumns(source, 'desktopColumns'),
      'showFavoritePlatformTabs': source['showFavoritePlatformTabs'] is bool
          ? source['showFavoritePlatformTabs'] as bool
          : true,
      'favoriteSortMode': FavoriteSortMode.fromName(source['favoriteSortMode']).name,
    };
    // A backup from before the profiles keeps a narrow (mobile) and a wide
    // (desktop) set: the phone profile takes the first, tablet and desktop
    // the second.
    final legacyMobile = <String, dynamic>{
      'config': narrow.toJson(),
      'cardWidth': parsed['mobileCardWidth'],
      'columns': parsed['mobileColumns'],
    };
    final legacyDesktop = <String, dynamic>{
      'config': wide.toJson(),
      'cardWidth': parsed['desktopCardWidth'],
      'columns': parsed['desktopColumns'],
    };
    parsed[profilesKey] = ProfiledSettings.parse(
      profiledSpecs,
      source[profilesKey],
      legacy: (profile) => profile == DisplayProfile.phone ? legacyMobile : legacyDesktop,
    );
    return parsed;
  }

  static int _readColumns(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return autoColumns;
    if (value is! num) throw FormatException('$key must be a number');
    return normalizeColumns(value);
  }

  static double _readCardWidth(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return autoCardWidth;
    if (value is! num) throw FormatException('$key must be a number');
    return normalizeCardWidth(value.toDouble());
  }

  static String? _readString(Map<String, dynamic> json, String key, {required String legacyKey}) {
    final value = json.containsKey(key) ? json[key] : json[legacyKey];
    if (value == null) return null;
    if (value is! String) throw FormatException('$key must be a string');
    return value;
  }

  static Map<String, dynamic>? _readConfigMap(Map<String, dynamic> json, String key, {required String legacyKey}) {
    final value = json.containsKey(key) ? json[key] : json[legacyKey];
    if (value == null) return null;
    if (value is String) {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      throw FormatException('$key must be an object');
    }
    if (value is Map) return Map<String, dynamic>.from(value);
    throw FormatException('$key must be an object');
  }

  void fromJson(Map<String, dynamic> json) {
    final parsed = parseConfig(json);
    showFavoritePlatformTabs.v = parsed['showFavoritePlatformTabs'] as bool;
    favoriteSortModeName.v = parsed['favoriteSortMode'] as String;
    profiles.restore(parsed[profilesKey] as Map<String, dynamic>);
  }

  static Map<String, dynamic> extractConfig(Map<String, dynamic>? rootConfig) {
    final parsed = parseConfig(rootConfig ?? const {});
    return {
      'mobilePreset': parsed['mobilePreset'],
      'desktopPreset': parsed['desktopPreset'],
      'mobileConfig': (parsed['mobileConfig'] as RoomCardAppearance).toJson(),
      'desktopConfig': (parsed['desktopConfig'] as RoomCardAppearance).toJson(),
      'mobileCardWidth': parsed['mobileCardWidth'],
      'desktopCardWidth': parsed['desktopCardWidth'],
      'mobileColumns': parsed['mobileColumns'],
      'desktopColumns': parsed['desktopColumns'],
      'showFavoritePlatformTabs': parsed['showFavoritePlatformTabs'],
      'favoriteSortMode': parsed['favoriteSortMode'],
      profilesKey: parsed[profilesKey],
    };
  }
}

/// How the home 关注 page orders its rooms.
enum FavoriteSortMode {
  /// By streamer name.
  name,

  /// By platform (in the configured platform order), then streamer name.
  platform,

  /// By audience, largest first.
  audience;

  static FavoriteSortMode fromName(Object? value) =>
      values.firstWhere((mode) => mode.name == value, orElse: () => FavoriteSortMode.name);
}
