import 'dart:async';
import 'dart:convert';

import 'package:pure_live/get/get.dart';
import 'package:pure_live/core/storage/hive_rx.dart';
import 'package:pure_live/core/layout/app_layout.dart';
import 'package:pure_live/core/storage/hive_pref_util.dart';
import 'package:pure_live/core/config/profiled_settings.dart';
import 'package:pure_live/core/config/display_mode_service.dart';
import 'package:pure_live/core/models/app_refresh_rate_mode.dart';

class DanmakuSettingsController extends GetxController {
  static const double defaultDanmakuTopArea = 0.0;
  static const double defaultDanmakuArea = 1.0;
  static const double defaultDanmakuBottomArea = 0.5;
  static const double defaultDanmakuSpeed = 120.0;
  static const double defaultDanmakuFontSize = 16.0;
  static const int defaultDanmakuFontWeight = 500;
  static const double defaultDanmakuFontBorder = 1.5;

  /// 弹幕间距: the gap between two floating-danmaku tracks, as a share of the
  /// font size. 0.55 is the 1.55 x font size track the app always used.
  static const double defaultDanmakuLineSpacing = 0.55;
  static const double minDanmakuLineSpacing = 0;
  static const double maxDanmakuLineSpacing = 1.5;
  static const double defaultDanmakuOpacity = 1.0;
  static const int defaultDanmakuFps = 60;
  static const bool defaultDanmakuAutoFps = true;
  static const bool defaultPipDanmakuAutoScale = true;
  static const bool defaultPipDanmakuUseOriginalColor = true;
  static const int defaultPipDanmakuColor = 0xFFFFFFFF;
  static const double defaultPipDanmakuFontSize = 12.0;
  static const int defaultPipDanmakuFontWeight = 500;
  static const double defaultPipDanmakuSpeed = 90.0;
  static const double defaultPipDanmakuOpacity = 0.9;
  static const double defaultPipDanmakuArea = 0.5;
  static const int defaultPipDanmakuMaxVisibleCount = 6;
  static const double defaultPipDanmakuEmitInterval = 0.35;
  static const int defaultPipDanmakuFps = 30;
  static const bool defaultPipDanmakuAutoFps = true;
  static const bool defaultNoEmojiMode = false;
  static const bool defaultPipDanmakuNoEmojiMode = false;
  static const double defaultChatListFontSize = 14.0;
  // The chat list's name boldest and its message thinnest by default.
  static const int defaultChatListFontWeight = 100;
  static const int defaultChatListNameFontWeight = 900;
  static const double defaultChatListItemSpacing = 4.0;
  static const int defaultDanmakuMaxVisibleCount = 48;

  /// Bounds of 最大同屏弹幕数. Lanes already cap how many messages fit; this
  /// is a density and low-end-device limit, so it reaches well past a full
  /// screen.
  static const int minDanmakuMaxVisibleCount = 10;
  static const int maxDanmakuMaxVisibleCount = 500;

  static const double pipDanmakuScaleMin = 0.4;
  static const double pipDanmakuScaleMax = 1.0;
  static const double defaultPipDanmakuScaleValue = 0.4;
  // Completeness is the safe default: `dms` and `if` are optional decoration
  // markers rather than a protocol-level visibility contract. Users can still
  // opt into the heuristic when they prefer a quieter room feed.
  static const bool defaultFilterDouyuSuspectedAutomatedMessages = false;
  // Preserve the complete platform feed unless the user explicitly chooses
  // fuzzy suppression. Enabling this by default can hide a large share of
  // short messages in busy rooms even though the transport received them.
  static const bool defaultEnableDanmakuSimilarityFilter = false;

  static int normalizeFontWeight(Object? value, {int fallback = 500}) {
    final raw = value is num ? value.toInt() : fallback;
    return ((raw.clamp(100, 900) / 100).round() * 100).clamp(100, 900).toInt();
  }

  static double _boundedDouble(Object? value, {required double fallback, required double min, required double max}) {
    final raw = value == null ? fallback : (value as num).toDouble();
    if (!raw.isFinite) return fallback;
    return raw.clamp(min, max).toDouble();
  }

  static int _boundedInt(Object? value, {required int fallback, required int min, required int max}) {
    final rawNumber = value == null ? fallback.toDouble() : (value as num).toDouble();
    if (!rawNumber.isFinite) return fallback;
    return rawNumber.toInt().clamp(min, max).toInt();
  }

  final RxBool hideDanmaku = hiveBool('hideDanmaku', false);

  /// 在播放器中显示留言: whether active super chats sit as cards on the live
  /// room's picture. Independent of the danmaku overlay toggle.
  final RxBool showSuperChatOnPlayer = hiveBool('showSuperChatOnPlayer', true);

  /// 留言板常驻: the room's 留言 list keeps every super chat until the room
  /// closes. Off (正常倒计时, the default) a super chat leaves the list when
  /// its countdown ends. After Simple Live.
  final RxBool superChatPinned = hiveBool('superChatPinned', false);

  /// 留言透明度: opacity of the super chat cards on the picture, 30%-100% in
  /// 5% steps.
  final RxDouble superChatOpacity = hiveDouble('superChatOpacity', defaultSuperChatOpacity);

  /// 留言字号: scale of the super chat cards' text roles on the picture,
  /// 80%-160% in 10% steps.
  final RxDouble superChatFontScale = hiveDouble('superChatFontScale', defaultSuperChatFontScale);

  /// Simple Live draws its player super chats at 65% opacity.
  static const double defaultSuperChatOpacity = 0.65;
  static const double minSuperChatOpacity = 0.3;
  static const double defaultSuperChatFontScale = 1.0;
  static const double minSuperChatFontScale = 0.8;
  static const double maxSuperChatFontScale = 1.6;

  static double normalizeSuperChatOpacity(Object? raw) {
    final value = _boundedDouble(raw, fallback: defaultSuperChatOpacity, min: minSuperChatOpacity, max: 1);
    return ((value * 20).round() / 20).clamp(minSuperChatOpacity, 1.0).toDouble();
  }

  static double normalizeSuperChatFontScale(Object? raw) {
    final value = _boundedDouble(
      raw,
      fallback: defaultSuperChatFontScale,
      min: minSuperChatFontScale,
      max: maxSuperChatFontScale,
    );
    return ((value * 10).round() / 10).clamp(minSuperChatFontScale, maxSuperChatFontScale).toDouble();
  }

  /// Text size of the chat list in the room side panel; independent of the
  /// scrolling danmaku on the video.
  final RxDouble chatListFontSize = hiveDouble('chatListFontSize', defaultChatListFontSize);

  /// Text weight of the chat list, 100-900; independent of the danmaku on the
  /// video.
  final RxInt chatListFontWeight = hiveInt('chatListFontWeight', defaultChatListFontWeight);

  /// Weight of the sender's name in the chat list, set apart from the message.
  final RxInt chatListNameFontWeight = hiveInt('chatListNameFontWeight', defaultChatListNameFontWeight);

  /// Vertical gap between chat list messages in the room side panel.
  final RxDouble chatListItemSpacing = hiveDouble('chatListItemSpacing', defaultChatListItemSpacing);

  /// Whether chat list messages sit in rounded bubbles.
  final RxBool chatListBubble = hiveBool('chatListBubble', true);

  /// The bubble outline's opacity, 0-1.
  final RxDouble chatListBubbleBorderOpacity = hiveDouble('chatListBubbleBorderOpacity', 1.0);

  /// A filled bubble background (off: outline only) and its opacity, 0-1.
  final RxBool chatListBubbleFill = hiveBool('chatListBubbleFill', false);
  final RxDouble chatListBubbleFillOpacity = hiveDouble('chatListBubbleFillOpacity', defaultChatListBubbleFillOpacity);

  static const double defaultChatListBubbleFillOpacity = 0.15;

  /// Clamps a bubble opacity to 0-1 in 5 % steps; anything unreadable is [fallback].
  static double normalizeBubbleOpacity(Object? value, {required double fallback}) {
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    if (number == null || !number.isFinite) return fallback;
    return ((number.clamp(0.0, 1.0)) * 20).round() / 20;
  }

  /// How a message's danmaku colour shows in the chat list; a [ChatListColorMode] name.
  final RxString chatListColorMode = hiveString('chatListColorMode', ChatListColorMode.none.name);

  /// Whether chat list messages show the sender's avatar (only Bilibili sends one).
  final RxBool chatListShowAvatar = hiveBool('chatListShowAvatar', true);

  /// Whether chat list messages show the sender's fan badge (Bilibili, Missevan, LOOK, KuGou).
  final RxBool chatListShowFansBadge = hiveBool('chatListShowFansBadge', true);

  ChatListColorMode get resolvedChatListColorMode => ChatListColorMode.fromName(chatListColorMode.v);
  final RxBool noEmojiMode = hiveBool('noEmojiMode', defaultNoEmojiMode);
  final RxDouble danmakuTopArea = hiveDouble('danmakuTopArea', defaultDanmakuTopArea);
  /// Share of the picture's height the scrolling danmaku may use: 10% to 100%
  /// in 5% steps.
  final RxDouble danmakuArea = hiveDouble('danmakuArea', defaultDanmakuArea);

  static const double minDanmakuArea = 0.1;
  static const double danmakuAreaStep = 0.05;

  /// Clamps [raw] to 10%-100% and snaps it to the 5% grid; anything that is not
  /// a finite number falls back to the full area.
  static double normalizeDanmakuArea(Object? raw) {
    final value = _boundedDouble(raw, fallback: defaultDanmakuArea, min: minDanmakuArea, max: 1);
    final snapped = (value / danmakuAreaStep).round() * danmakuAreaStep;
    return double.parse(snapped.clamp(minDanmakuArea, 1.0).toStringAsFixed(2));
  }
  final RxDouble danmakuBottomArea = hiveDouble('danmakuBottomArea', defaultDanmakuBottomArea);
  final RxDouble danmakuSpeed = hiveDouble('danmakuSpeed', defaultDanmakuSpeed);
  final RxDouble danmakuFontSize = hiveDouble('danmakuFontSize', defaultDanmakuFontSize);
  final RxInt danmakuFontWeight = hiveInt('danmakuFontWeight', defaultDanmakuFontWeight);
  final RxDouble danmakuFontBorder = hiveDouble('danmakuFontBorder', defaultDanmakuFontBorder);
  final RxDouble danmakuLineSpacing = hiveDouble('danmakuLineSpacing', defaultDanmakuLineSpacing);

  /// [value] bounded to the 弹幕间距 range in 5 % steps.
  static double normalizeLineSpacing(Object? value) {
    final bounded = _boundedDouble(
      value,
      fallback: defaultDanmakuLineSpacing,
      min: minDanmakuLineSpacing,
      max: maxDanmakuLineSpacing,
    );
    return ((bounded * 20).round() / 20).clamp(minDanmakuLineSpacing, maxDanmakuLineSpacing).toDouble();
  }

  /// Height of one floating-danmaku track: the text plus the 弹幕间距 gap.
  /// Every barrage surface (the room, the multi-view tiles) takes it from
  /// here, so they all space their tracks alike. No floor above the font
  /// size: one made every gap below it look the same (with 16 px text, any
  /// 弹幕间距 under 50 %).
  static double trackHeightFor(double fontSize, double lineSpacing) {
    final height = fontSize * (1 + normalizeLineSpacing(lineSpacing));
    return height.clamp(fontSize, 120.0).toDouble();
  }
  final RxDouble danmakuOpacity = hiveDouble('danmakuOpacity', defaultDanmakuOpacity);

  /// Same-screen cap forwarded to FlameBarrageWidget.maxVisibleCount.
  final RxInt danmakuMaxVisibleCount = hiveInt('danmakuMaxVisibleCount', defaultDanmakuMaxVisibleCount);
  final RxBool enableDanmakuStroke = hiveBool('enableDanmakuStroke', true);

  final RxBool danmakuMassMode = hiveBool('danmakuRealtimeMode', false);

  static const int massModeMaxVisibleCount = 1000;

  /// 同屏数量自动: no count limit of its own; the lanes (display area, font
  /// size, screen width) decide how many fit. Off, [danmakuMaxVisibleCount]
  /// applies - a density or low-end-device limit.
  final RxBool danmakuAutoMaxVisible = hiveBool('danmakuAutoMaxVisible', true);

  int get effectiveMaxVisibleCount =>
      danmakuMassMode.v || danmakuAutoMaxVisible.v ? massModeMaxVisibleCount : danmakuMaxVisibleCount.v;

  final RxInt danmakuFps = hiveInt('danmakuFps', defaultDanmakuFps);
  final RxBool danmakuAutoFps = hiveBool('danmakuAutoFps', defaultDanmakuAutoFps);
  final RxBool enableDanmakuTapInteraction = hiveBool('enableDanmakuTapInteraction', true);
  final RxBool enableDanmakuLongPressInteraction = hiveBool('enableDanmakuLongPressInteraction', true);
  final RxBool collapseRepeatedDanmaku = hiveBool('collapseRepeatedDanmaku', false);
  final RxInt repeatedDanmakuWindowSeconds = hiveInt('repeatedDanmakuWindowSeconds', 5);
  final RxInt danmakuInteractionMigration = hiveInt('danmakuInteractionMigration', 0);
  final RxString savedDanmakuTemplate = hiveString('savedDanmakuTemplate', '');
  final RxString danmakuFontFamilyName = hiveString('danmakuFontFamilyName', 'Default');

  /// Hive key prefix and backup key of the per-profile settings.
  static const String profilePrefix = 'danmakuProfile';
  static const String profilesKey = 'danmakuProfiles';

  static final _topAreaSpec = ProfiledSpec<double>(
    'danmakuTopArea',
    fallback: defaultDanmakuTopArea,
    read: ProfiledSpec.number(min: 0, max: 300),
  );
  static final _areaSpec = ProfiledSpec<double>(
    'danmakuArea',
    fallback: defaultDanmakuArea,
    read: ProfiledSpec.number(min: minDanmakuArea, max: 1, normalize: normalizeDanmakuArea),
  );
  static final _bottomAreaSpec = ProfiledSpec<double>(
    'danmakuBottomArea',
    fallback: defaultDanmakuBottomArea,
    read: ProfiledSpec.number(min: 0, max: 300),
  );
  static final _speedSpec = ProfiledSpec<double>(
    'danmakuSpeed',
    fallback: defaultDanmakuSpeed,
    read: ProfiledSpec.number(min: 20, max: 400),
  );
  static final _fontSizeSpec = ProfiledSpec<double>(
    'danmakuFontSize',
    fallback: defaultDanmakuFontSize,
    read: ProfiledSpec.number(min: 10, max: 30),
  );
  static final _fontWeightSpec = ProfiledSpec<int>(
    'danmakuFontWeight',
    fallback: defaultDanmakuFontWeight,
    read: ProfiledSpec.integer(normalizeFontWeight),
  );
  static final _fontBorderSpec = ProfiledSpec<double>(
    'danmakuFontBorder',
    fallback: defaultDanmakuFontBorder,
    read: ProfiledSpec.number(min: 0, max: 4),
  );
  static final _lineSpacingSpec = ProfiledSpec<double>(
    'danmakuLineSpacing',
    fallback: defaultDanmakuLineSpacing,
    read: ProfiledSpec.number(
      min: minDanmakuLineSpacing,
      max: maxDanmakuLineSpacing,
      normalize: normalizeLineSpacing,
    ),
  );
  static final _opacitySpec = ProfiledSpec<double>(
    'danmakuOpacity',
    fallback: defaultDanmakuOpacity,
    read: ProfiledSpec.number(min: 0, max: 1),
  );
  static final _strokeSpec = ProfiledSpec<bool>('enableDanmakuStroke', fallback: true, read: ProfiledSpec.flag);
  static final _chatFontSizeSpec = ProfiledSpec<double>(
    'chatListFontSize',
    fallback: defaultChatListFontSize,
    read: ProfiledSpec.number(min: 10, max: 28),
  );
  static final _chatFontWeightSpec = ProfiledSpec<int>(
    'chatListFontWeight',
    fallback: defaultChatListFontWeight,
    read: ProfiledSpec.integer((value) => normalizeFontWeight(value, fallback: defaultChatListFontWeight)),
  );
  static final _chatNameFontWeightSpec = ProfiledSpec<int>(
    'chatListNameFontWeight',
    fallback: defaultChatListNameFontWeight,
    read: ProfiledSpec.integer((value) => normalizeFontWeight(value, fallback: defaultChatListNameFontWeight)),
  );
  static final _chatSpacingSpec = ProfiledSpec<double>(
    'chatListItemSpacing',
    fallback: defaultChatListItemSpacing,
    read: ProfiledSpec.number(min: 0, max: 16),
  );
  static final _chatBubbleSpec = ProfiledSpec<bool>('chatListBubble', fallback: true, read: ProfiledSpec.flag);
  static final _chatBubbleBorderOpacitySpec = ProfiledSpec<double>(
    'chatListBubbleBorderOpacity',
    fallback: 1.0,
    read: ProfiledSpec.number(min: 0, max: 1),
  );
  static final _chatBubbleFillSpec = ProfiledSpec<bool>('chatListBubbleFill', fallback: false, read: ProfiledSpec.flag);
  static final _chatBubbleFillOpacitySpec = ProfiledSpec<double>(
    'chatListBubbleFillOpacity',
    fallback: defaultChatListBubbleFillOpacity,
    read: ProfiledSpec.number(min: 0, max: 1),
  );
  static final _chatColorModeSpec = ProfiledSpec<String>(
    'chatListColorMode',
    fallback: ChatListColorMode.none.name,
    read: ProfiledSpec.text((value) => ChatListColorMode.fromName(value).name),
  );
  static final _chatAvatarSpec = ProfiledSpec<bool>('chatListShowAvatar', fallback: true, read: ProfiledSpec.flag);
  static final _chatFansBadgeSpec = ProfiledSpec<bool>(
    'chatListShowFansBadge',
    fallback: true,
    read: ProfiledSpec.flag,
  );
  static final _superChatOpacitySpec = ProfiledSpec<double>(
    'superChatOpacity',
    fallback: defaultSuperChatOpacity,
    read: ProfiledSpec.number(min: minSuperChatOpacity, max: 1, normalize: normalizeSuperChatOpacity),
  );
  static final _superChatFontScaleSpec = ProfiledSpec<double>(
    'superChatFontScale',
    fallback: defaultSuperChatFontScale,
    read: ProfiledSpec.number(
      min: minSuperChatFontScale,
      max: maxSuperChatFontScale,
      normalize: normalizeSuperChatFontScale,
    ),
  );

  /// What the phone, the tablet and the desktop profile keep apart: the
  /// floating-danmaku style (area, margins, speed, font size and weight,
  /// stroke, opacity), the chat list's look, the room text brightness and
  /// the super chat cards on the picture. Their keys are the single settings'
  /// keys, so a backup's single values read straight into a profile.
  static List<ProfiledSpec> get profiledSpecs => [
    _topAreaSpec,
    _areaSpec,
    _bottomAreaSpec,
    _speedSpec,
    _fontSizeSpec,
    _fontWeightSpec,
    _fontBorderSpec,
    _lineSpacingSpec,
    _opacitySpec,
    _strokeSpec,
    _chatFontSizeSpec,
    _chatFontWeightSpec,
    _chatNameFontWeightSpec,
    _chatSpacingSpec,
    _chatBubbleSpec,
    _chatBubbleBorderOpacitySpec,
    _chatBubbleFillSpec,
    _chatBubbleFillOpacitySpec,
    _chatColorModeSpec,
    _chatAvatarSpec,
    _chatFansBadgeSpec,
    _superChatOpacitySpec,
    _superChatFontScaleSpec,
  ];

  /// The per-profile settings above. Their fields ([danmakuSpeed],
  /// [chatListFontSize], ...) always hold the active profile's values: every
  /// reader keeps reading them and every edit lands in that profile. Their
  /// own Hive keys keep being written and so mirror the last active profile,
  /// which an older build reads unchanged.
  late final ProfiledSettings profiles = ProfiledSettings(profilePrefix, [
    _topAreaSpec.bind(danmakuTopArea),
    _areaSpec.bind(danmakuArea),
    _bottomAreaSpec.bind(danmakuBottomArea),
    _speedSpec.bind(danmakuSpeed),
    _fontSizeSpec.bind(danmakuFontSize),
    _fontWeightSpec.bind(danmakuFontWeight),
    _fontBorderSpec.bind(danmakuFontBorder),
    _lineSpacingSpec.bind(danmakuLineSpacing),
    _opacitySpec.bind(danmakuOpacity),
    _strokeSpec.bind(enableDanmakuStroke),
    _chatFontSizeSpec.bind(chatListFontSize),
    _chatFontWeightSpec.bind(chatListFontWeight),
    _chatNameFontWeightSpec.bind(chatListNameFontWeight),
    _chatSpacingSpec.bind(chatListItemSpacing),
    _chatBubbleSpec.bind(chatListBubble),
    _chatBubbleBorderOpacitySpec.bind(chatListBubbleBorderOpacity),
    _chatBubbleFillSpec.bind(chatListBubbleFill),
    _chatBubbleFillOpacitySpec.bind(chatListBubbleFillOpacity),
    _chatColorModeSpec.bind(chatListColorMode),
    _chatAvatarSpec.bind(chatListShowAvatar),
    _chatFansBadgeSpec.bind(chatListShowFansBadge),
    _superChatOpacitySpec.bind(superChatOpacity),
    _superChatFontScaleSpec.bind(superChatFontScale),
  ]);

  /// The profile the per-profile fields hold.
  Rx<DisplayProfile> get profile => profiles.profile;

  void useProfile(DisplayProfile profile) => profiles.use(profile);

  /// Hive keys of an earlier development build that kept the floating style
  /// once for the narrow and once for the wide layout, with the field names
  /// in [_layoutStyleFields]. Read once as the profiles' seed, then removed.
  static const String _narrowStyleKey = 'danmakuStyleNarrow';
  static const String _wideStyleKey = 'danmakuStyleWide';
  static const Map<String, String> _layoutStyleFields = {
    'topArea': 'danmakuTopArea',
    'area': 'danmakuArea',
    'bottomArea': 'danmakuBottomArea',
    'speed': 'danmakuSpeed',
    'fontSize': 'danmakuFontSize',
    'fontWeight': 'danmakuFontWeight',
    'fontBorder': 'danmakuFontBorder',
    'opacity': 'danmakuOpacity',
    'stroke': 'enableDanmakuStroke',
  };

  static Map<String, dynamic>? _layoutStyleSeed(DisplayProfile profile) {
    final stored = HivePrefUtil.getString(profile == DisplayProfile.phone ? _narrowStyleKey : _wideStyleKey);
    if (stored == null || stored.isEmpty) return null;
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map) return null;
      return {
        for (final entry in _layoutStyleFields.entries)
          if (decoded[entry.key] != null) entry.value: decoded[entry.key],
      };
    } catch (_) {
      return null;
    }
  }

  /// Scale factor applied on top of the main danmaku config when rendering
  /// the compact (picture-in-picture / small-window) surface. `null` means
  /// auto: the factor follows the compact window's width against the 350px
  /// reference. A number pins the factor explicitly.
  /// The old per-pip config cohort (font size, speed, opacity, ...) was
  /// folded into the main danmaku settings; these Hive keys are legacy.
  final RxBool pipDanmakuScaleAuto = hiveBool('pipDanmakuAutoScale', true);
  final RxDouble pipDanmakuScaleValue = hiveDouble('pipDanmakuScaleValue', defaultPipDanmakuScaleValue);

  // Douyu sometimes emits legitimate room-local chat packets without either
  // decoration/fan marker. Preserve them unless the user explicitly enables
  // the heuristic filter.
  final RxBool filterDouyuSuspectedAutomatedMessages = hiveBool(
    'filterDouyuSuspectedAutomatedMessages',
    defaultFilterDouyuSuspectedAutomatedMessages,
  );

  //   Enable danmaku Similarity Filter
  final RxBool enableDanmakuSimilarityFilter = hiveBool(
    'enableDanmakuSimilarityFilter',
    defaultEnableDanmakuSimilarityFilter,
  );
  final RxInt danmakuSimilarityThreshold = hiveInt('danmakuSimilarityThreshold', 85);
  final RxInt danmakuSimilarityCacheDuration = hiveInt('danmakuSimilarityCacheDuration', 3);
  final RxInt danmakuSimilarityMaxCacheSize = hiveInt('danmakuSimilarityMaxCacheSize', 100);
  @override
  void onInit() {
    super.onInit();
    danmakuTopArea.v = _boundedDouble(danmakuTopArea.v, fallback: defaultDanmakuTopArea, min: 0, max: 300);
    danmakuArea.v = normalizeDanmakuArea(danmakuArea.v);
    superChatOpacity.v = normalizeSuperChatOpacity(superChatOpacity.v);
    superChatFontScale.v = normalizeSuperChatFontScale(superChatFontScale.v);
    danmakuBottomArea.v = _boundedDouble(danmakuBottomArea.v, fallback: defaultDanmakuBottomArea, min: 0, max: 300);
    danmakuSpeed.v = _boundedDouble(danmakuSpeed.v, fallback: defaultDanmakuSpeed, min: 20, max: 400);
    danmakuFontSize.v = _boundedDouble(danmakuFontSize.v, fallback: defaultDanmakuFontSize, min: 10, max: 30);
    danmakuFontWeight.v = normalizeFontWeight(danmakuFontWeight.v);
    chatListFontWeight.v = normalizeFontWeight(chatListFontWeight.v, fallback: defaultChatListFontWeight);
    chatListNameFontWeight.v = normalizeFontWeight(
      chatListNameFontWeight.v,
      fallback: defaultChatListNameFontWeight,
    );
    danmakuFontBorder.v = _boundedDouble(danmakuFontBorder.v, fallback: defaultDanmakuFontBorder, min: 0, max: 4);
    danmakuLineSpacing.v = normalizeLineSpacing(danmakuLineSpacing.v);
    danmakuOpacity.v = _boundedDouble(danmakuOpacity.v, fallback: defaultDanmakuOpacity, min: 0, max: 1);
    danmakuFps.v = _boundedInt(danmakuFps.v, fallback: defaultDanmakuFps, min: 30, max: 240);
    danmakuSimilarityThreshold.v = danmakuSimilarityThreshold.v.clamp(50, 100).toInt();
    danmakuSimilarityCacheDuration.v = danmakuSimilarityCacheDuration.v.clamp(1, 60).toInt();
    danmakuSimilarityMaxCacheSize.v = danmakuSimilarityMaxCacheSize.v.clamp(20, 1000).toInt();
    if (danmakuInteractionMigration.v < 1) {
      enableDanmakuTapInteraction.v = true;
      enableDanmakuLongPressInteraction.v = true;
      danmakuInteractionMigration.v = 1;
    }
    // Load the three profiles (seeded on first run from the single values
    // used so far) and the one this device used last; AppShell switches to
    // the resolved one once the layout is known.
    profiles.init(seed: _layoutStyleSeed);
    for (final key in const [_narrowStyleKey, _wideStyleKey]) {
      if (HivePrefUtil.containsKey(key)) unawaited(HivePrefUtil.remove(key));
    }
  }

  @override
  void onClose() {
    profiles.dispose();
    super.onClose();
  }

  int resolvedDanmakuFps({bool pip = false, AppRefreshRateMode refreshRateMode = AppRefreshRateMode.powerSaving}) {
    // The compact surface shares the main danmaku FPS policy.
    final auto = danmakuAutoFps.v;
    final configured = danmakuFps.v;
    if (!auto) return configured.clamp(30, 240).toInt();
    return resolveAdaptiveDanmakuFps(DisplayModeService.info.value, pip: pip, refreshRateMode: refreshRateMode);
  }

  /// Resolves both room and PiP renderers from the single interface policy.
  ///
  /// Power saving keeps the existing 60/30 caps, balanced gives both surfaces
  /// a stable 60 FPS budget while touch-driven UI can temporarily use the
  /// display maximum, and Highest follows the detected device maximum for all
  /// UI/danmaku surfaces. A local manual value remains an explicit override.
  static int resolveAdaptiveDanmakuFps(
    DisplayModeInfo? display, {
    bool pip = false,
    AppRefreshRateMode refreshRateMode = AppRefreshRateMode.powerSaving,
  }) {
    final current = display?.currentRefreshRate ?? 0;
    final maximum = display?.maxRefreshRate ?? 0;
    final detected = maximum > 0 ? maximum : (current > 0 ? current : 60);
    final deviceMaximum = detected.round().clamp(pip ? 15 : 30, 240).toInt();
    return switch (refreshRateMode) {
      AppRefreshRateMode.powerSaving => deviceMaximum.clamp(pip ? 15 : 30, pip ? 30 : 60).toInt(),
      AppRefreshRateMode.balanced => deviceMaximum.clamp(pip ? 15 : 30, 60).toInt(),
      AppRefreshRateMode.performance => deviceMaximum,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'hideDanmaku': hideDanmaku.v,
      'showSuperChatOnPlayer': showSuperChatOnPlayer.v,
      'superChatPinned': superChatPinned.v,
      'superChatOpacity': normalizeSuperChatOpacity(superChatOpacity.v),
      'superChatFontScale': normalizeSuperChatFontScale(superChatFontScale.v),
      'chatListFontSize': chatListFontSize.v,
      'chatListFontWeight': chatListFontWeight.v,
      'chatListNameFontWeight': chatListNameFontWeight.v,
      'chatListItemSpacing': chatListItemSpacing.v,
      'chatListBubble': chatListBubble.v,
      'chatListBubbleBorderOpacity': normalizeBubbleOpacity(chatListBubbleBorderOpacity.v, fallback: 1.0),
      'chatListBubbleFill': chatListBubbleFill.v,
      'chatListBubbleFillOpacity': normalizeBubbleOpacity(
        chatListBubbleFillOpacity.v,
        fallback: defaultChatListBubbleFillOpacity,
      ),
      'chatListColorMode': chatListColorMode.v,
      'chatListShowAvatar': chatListShowAvatar.v,
      'chatListShowFansBadge': chatListShowFansBadge.v,
      'noEmojiMode': noEmojiMode.v,
      'danmakuTopArea': danmakuTopArea.v,
      'danmakuArea': danmakuArea.v,
      'danmakuMaxVisibleCount': danmakuMaxVisibleCount.v,
      'danmakuBottomArea': danmakuBottomArea.v,
      'danmakuSpeed': danmakuSpeed.v,
      'danmakuFontSize': danmakuFontSize.v,
      'danmakuFontWeight': danmakuFontWeight.v,
      'danmakuFontBorder': danmakuFontBorder.v,
      'danmakuLineSpacing': normalizeLineSpacing(danmakuLineSpacing.v),
      'danmakuRealtimeMode': danmakuMassMode.v,
      'danmakuAutoMaxVisible': danmakuAutoMaxVisible.v,
      'danmakuOpacity': danmakuOpacity.v,
      'danmakuFontFamilyName': danmakuFontFamilyName.v,
      'enableDanmakuStroke': enableDanmakuStroke.v,
      'danmakuFps': danmakuFps.v,
      'danmakuAutoFps': danmakuAutoFps.v,
      'enableDanmakuTapInteraction': enableDanmakuTapInteraction.v,
      'enableDanmakuLongPressInteraction': enableDanmakuLongPressInteraction.v,
      'collapseRepeatedDanmaku': collapseRepeatedDanmaku.v,
      'repeatedDanmakuWindowSeconds': repeatedDanmakuWindowSeconds.v,
      'savedDanmakuTemplate': savedDanmakuTemplate.v,
      'pipDanmakuAutoScale': pipDanmakuScaleAuto.v,
      'pipDanmakuScaleValue': pipDanmakuScaleValue.v,
      'filterDouyuSuspectedAutomatedMessages': filterDouyuSuspectedAutomatedMessages.v,
      'enableDanmakuSimilarityFilter': enableDanmakuSimilarityFilter.v,
      'danmakuSimilarityThreshold': danmakuSimilarityThreshold.v,
      'danmakuSimilarityCacheDuration': danmakuSimilarityCacheDuration.v,
      'danmakuSimilarityMaxCacheSize': danmakuSimilarityMaxCacheSize.v,
      // The single keys above carry the active profile's values (what an
      // older build restores); this carries all three profiles.
      profilesKey: profiles.export(),
    };
  }

  /// Parse the complete section without notifying observers or persisting values.
  static Map<String, dynamic> parseConfig(Map<String, dynamic> json) {
    T typed<T>(dynamic value) => value as T;
    final parsed = <String, dynamic>{
      'hideDanmaku': typed<bool>(json['hideDanmaku'] ?? false),
      'showSuperChatOnPlayer': typed<bool>(json['showSuperChatOnPlayer'] ?? true),
      'superChatPinned': typed<bool>(json['superChatPinned'] ?? false),
      'superChatOpacity': typed<double>(normalizeSuperChatOpacity(json['superChatOpacity'])),
      'superChatFontScale': typed<double>(normalizeSuperChatFontScale(json['superChatFontScale'])),
      'chatListFontSize': typed<double>(
        _boundedDouble(json['chatListFontSize'], fallback: defaultChatListFontSize, min: 10, max: 28),
      ),
      'chatListFontWeight': typed<int>(
        normalizeFontWeight(json['chatListFontWeight'], fallback: defaultChatListFontWeight),
      ),
      'chatListNameFontWeight': typed<int>(
        normalizeFontWeight(json['chatListNameFontWeight'], fallback: defaultChatListNameFontWeight),
      ),
      'chatListItemSpacing': typed<double>(
        _boundedDouble(json['chatListItemSpacing'], fallback: defaultChatListItemSpacing, min: 0, max: 16),
      ),
      'danmakuMaxVisibleCount': typed<int>(
        _boundedInt(
          json['danmakuMaxVisibleCount'],
          fallback: defaultDanmakuMaxVisibleCount,
          min: minDanmakuMaxVisibleCount,
          max: maxDanmakuMaxVisibleCount,
        ),
      ),
      'chatListBubble': typed<bool>(json['chatListBubble'] ?? true),
      'chatListBubbleBorderOpacity': typed<double>(
        normalizeBubbleOpacity(json['chatListBubbleBorderOpacity'] ?? 1.0, fallback: 1.0),
      ),
      'chatListBubbleFill': typed<bool>(json['chatListBubbleFill'] ?? false),
      'chatListBubbleFillOpacity': typed<double>(
        normalizeBubbleOpacity(
          json['chatListBubbleFillOpacity'] ?? defaultChatListBubbleFillOpacity,
          fallback: defaultChatListBubbleFillOpacity,
        ),
      ),
      'chatListColorMode': ChatListColorMode.fromName(json['chatListColorMode']).name,
      'chatListShowAvatar': typed<bool>(json['chatListShowAvatar'] ?? true),
      'chatListShowFansBadge': typed<bool>(json['chatListShowFansBadge'] ?? true),
      'noEmojiMode': typed<bool>(json['noEmojiMode'] ?? defaultNoEmojiMode),
      'danmakuTopArea': typed<double>(
        _boundedDouble(json['danmakuTopArea'], fallback: defaultDanmakuTopArea, min: 0, max: 300),
      ),
      'danmakuArea': typed<double>(normalizeDanmakuArea(json['danmakuArea'])),
      'danmakuBottomArea': typed<double>(
        _boundedDouble(json['danmakuBottomArea'], fallback: defaultDanmakuBottomArea, min: 0, max: 300),
      ),
      'danmakuSpeed': typed<double>(
        _boundedDouble(json['danmakuSpeed'], fallback: defaultDanmakuSpeed, min: 20, max: 400),
      ),
      'danmakuFontSize': typed<double>(
        _boundedDouble(json['danmakuFontSize'], fallback: defaultDanmakuFontSize, min: 10, max: 30),
      ),
      'danmakuFontWeight': typed<int>(normalizeFontWeight(json['danmakuFontWeight'])),
      'danmakuFontBorder': typed<double>(
        _boundedDouble(json['danmakuFontBorder'], fallback: defaultDanmakuFontBorder, min: 0, max: 4),
      ),
      'danmakuLineSpacing': typed<double>(normalizeLineSpacing(json['danmakuLineSpacing'])),
      'danmakuRealtimeMode': typed<bool>(json['danmakuRealtimeMode'] ?? false),
      'danmakuAutoMaxVisible': typed<bool>(json['danmakuAutoMaxVisible'] ?? true),
      'danmakuOpacity': typed<double>(
        _boundedDouble(json['danmakuOpacity'], fallback: defaultDanmakuOpacity, min: 0, max: 1),
      ),
      'danmakuFontFamilyName': typed<String>(json['danmakuFontFamilyName'] ?? 'Default'),
      'enableDanmakuStroke': typed<bool>(json['enableDanmakuStroke'] ?? true),
      'danmakuFps': typed<int>(_boundedInt(json['danmakuFps'], fallback: defaultDanmakuFps, min: 30, max: 240)),
      'danmakuAutoFps': typed<bool>(json['danmakuAutoFps'] ?? defaultDanmakuAutoFps),
      'enableDanmakuTapInteraction': typed<bool>(json['enableDanmakuTapInteraction'] ?? true),
      'enableDanmakuLongPressInteraction': typed<bool>(json['enableDanmakuLongPressInteraction'] ?? true),
      'collapseRepeatedDanmaku': typed<bool>(json['collapseRepeatedDanmaku'] ?? false),
      'repeatedDanmakuWindowSeconds': typed<int>(
        (json['repeatedDanmakuWindowSeconds'] ?? 5).toInt().clamp(1, 30).toInt(),
      ),
      'savedDanmakuTemplate': typed<String>(json['savedDanmakuTemplate']?.toString() ?? ''),
      'pipDanmakuAutoScale': typed<bool>(json['pipDanmakuAutoScale'] ?? true),
      'pipDanmakuScaleValue': typed<double>(
        (json['pipDanmakuScaleValue'] ?? defaultPipDanmakuScaleValue)
            .toDouble()
            .clamp(pipDanmakuScaleMin, pipDanmakuScaleMax)
            .toDouble(),
      ),
      'filterDouyuSuspectedAutomatedMessages': typed<bool>(
        json['filterDouyuSuspectedAutomatedMessages'] ?? defaultFilterDouyuSuspectedAutomatedMessages,
      ),
      'enableDanmakuSimilarityFilter': typed<bool>(
        json['enableDanmakuSimilarityFilter'] ?? defaultEnableDanmakuSimilarityFilter,
      ),
      'danmakuSimilarityThreshold': typed<int>(
        (json['danmakuSimilarityThreshold'] ?? 85).toInt().clamp(50, 100).toInt(),
      ),
      'danmakuSimilarityCacheDuration': typed<int>(
        (json['danmakuSimilarityCacheDuration'] ?? 3).toInt().clamp(1, 60).toInt(),
      ),
      'danmakuSimilarityMaxCacheSize': typed<int>(
        (json['danmakuSimilarityMaxCacheSize'] ?? 100).toInt().clamp(20, 1000).toInt(),
      ),
    };
    // A backup from before the profiles has only the single values: every
    // profile takes them.
    parsed[profilesKey] = ProfiledSettings.parse(profiledSpecs, json[profilesKey], legacy: (_) => parsed);
    return parsed;
  }

  void fromJson(Map<String, dynamic> json) {
    final parsed = parseConfig(json);
    hideDanmaku.v = parsed['hideDanmaku'];
    showSuperChatOnPlayer.v = parsed['showSuperChatOnPlayer'];
    superChatPinned.v = parsed['superChatPinned'];
    danmakuMaxVisibleCount.v = parsed['danmakuMaxVisibleCount'];
    noEmojiMode.v = parsed['noEmojiMode'];
    // The per-profile fields come from the restored active profile below.
    danmakuMassMode.v = parsed['danmakuRealtimeMode'];
    danmakuAutoMaxVisible.v = parsed['danmakuAutoMaxVisible'];
    danmakuFontFamilyName.v = parsed['danmakuFontFamilyName'];
    danmakuFps.v = parsed['danmakuFps'];
    danmakuAutoFps.v = parsed['danmakuAutoFps'];
    enableDanmakuTapInteraction.v = parsed['enableDanmakuTapInteraction'];
    enableDanmakuLongPressInteraction.v = parsed['enableDanmakuLongPressInteraction'];
    collapseRepeatedDanmaku.v = parsed['collapseRepeatedDanmaku'];
    repeatedDanmakuWindowSeconds.v = parsed['repeatedDanmakuWindowSeconds'];
    savedDanmakuTemplate.v = parsed['savedDanmakuTemplate'];
    pipDanmakuScaleAuto.v = parsed['pipDanmakuAutoScale'];
    pipDanmakuScaleValue.v = parsed['pipDanmakuScaleValue'];
    filterDouyuSuspectedAutomatedMessages.v = parsed['filterDouyuSuspectedAutomatedMessages'];
    enableDanmakuSimilarityFilter.v = parsed['enableDanmakuSimilarityFilter'];
    danmakuSimilarityThreshold.v = parsed['danmakuSimilarityThreshold'];
    danmakuSimilarityCacheDuration.v = parsed['danmakuSimilarityCacheDuration'];
    danmakuSimilarityMaxCacheSize.v = parsed['danmakuSimilarityMaxCacheSize'];
    profiles.restore(parsed[profilesKey] as Map<String, dynamic>);
  }

  static Map<String, dynamic> extractConfig(Map<String, dynamic>? rootConfig) {
    final danmaku = rootConfig?['danmaku'] as Map<String, dynamic>? ?? {};
    final extracted = <String, dynamic>{
      'hideDanmaku': danmaku['hideDanmaku'] ?? false,
      'showSuperChatOnPlayer': danmaku['showSuperChatOnPlayer'] ?? true,
      'superChatPinned': danmaku['superChatPinned'] ?? false,
      'superChatOpacity': normalizeSuperChatOpacity(danmaku['superChatOpacity']),
      'superChatFontScale': normalizeSuperChatFontScale(danmaku['superChatFontScale']),
      'chatListFontSize': _boundedDouble(
        danmaku['chatListFontSize'],
        fallback: defaultChatListFontSize,
        min: 10,
        max: 28,
      ),
      'chatListFontWeight': normalizeFontWeight(danmaku['chatListFontWeight'], fallback: defaultChatListFontWeight),
      'chatListNameFontWeight': normalizeFontWeight(
        danmaku['chatListNameFontWeight'],
        fallback: defaultChatListNameFontWeight,
      ),
      'chatListItemSpacing': _boundedDouble(
        danmaku['chatListItemSpacing'],
        fallback: defaultChatListItemSpacing,
        min: 0,
        max: 16,
      ),
      'chatListBubble': danmaku['chatListBubble'] ?? true,
      'chatListBubbleBorderOpacity': normalizeBubbleOpacity(
        danmaku['chatListBubbleBorderOpacity'] ?? 1.0,
        fallback: 1.0,
      ),
      'chatListBubbleFill': danmaku['chatListBubbleFill'] ?? false,
      'chatListBubbleFillOpacity': normalizeBubbleOpacity(
        danmaku['chatListBubbleFillOpacity'] ?? defaultChatListBubbleFillOpacity,
        fallback: defaultChatListBubbleFillOpacity,
      ),
      'chatListColorMode': ChatListColorMode.fromName(danmaku['chatListColorMode']).name,
      'chatListShowAvatar': danmaku['chatListShowAvatar'] ?? true,
      'chatListShowFansBadge': danmaku['chatListShowFansBadge'] ?? true,
      'danmakuMaxVisibleCount': _boundedInt(
        danmaku['danmakuMaxVisibleCount'],
        fallback: defaultDanmakuMaxVisibleCount,
        min: minDanmakuMaxVisibleCount,
        max: maxDanmakuMaxVisibleCount,
      ),
      'noEmojiMode': danmaku['noEmojiMode'] ?? defaultNoEmojiMode,
      'danmakuTopArea': _boundedDouble(danmaku['danmakuTopArea'], fallback: defaultDanmakuTopArea, min: 0, max: 300),
      'danmakuArea': normalizeDanmakuArea(danmaku['danmakuArea']),
      'danmakuBottomArea': _boundedDouble(
        danmaku['danmakuBottomArea'],
        fallback: defaultDanmakuBottomArea,
        min: 0,
        max: 300,
      ),
      'danmakuSpeed': _boundedDouble(danmaku['danmakuSpeed'], fallback: defaultDanmakuSpeed, min: 20, max: 400),
      'danmakuFontSize': _boundedDouble(danmaku['danmakuFontSize'], fallback: defaultDanmakuFontSize, min: 10, max: 30),
      'danmakuFontWeight': normalizeFontWeight(danmaku['danmakuFontWeight']),
      'danmakuFontBorder': _boundedDouble(
        danmaku['danmakuFontBorder'],
        fallback: defaultDanmakuFontBorder,
        min: 0,
        max: 4,
      ),
      'danmakuLineSpacing': normalizeLineSpacing(danmaku['danmakuLineSpacing']),
      'danmakuOpacity': _boundedDouble(danmaku['danmakuOpacity'], fallback: defaultDanmakuOpacity, min: 0, max: 1),
      'danmakuRealtimeMode': danmaku['danmakuRealtimeMode'] ?? false,
      'danmakuAutoMaxVisible': danmaku['danmakuAutoMaxVisible'] ?? true,
      'danmakuFontFamilyName': danmaku['danmakuFontFamilyName'] ?? 'Default',
      'enableDanmakuStroke': danmaku['enableDanmakuStroke'] ?? true,
      'danmakuFps': _boundedInt(danmaku['danmakuFps'], fallback: defaultDanmakuFps, min: 30, max: 240),
      'danmakuAutoFps': danmaku['danmakuAutoFps'] ?? defaultDanmakuAutoFps,
      'enableDanmakuTapInteraction': danmaku['enableDanmakuTapInteraction'] ?? true,
      'enableDanmakuLongPressInteraction': danmaku['enableDanmakuLongPressInteraction'] ?? true,
      'collapseRepeatedDanmaku': danmaku['collapseRepeatedDanmaku'] ?? false,
      'repeatedDanmakuWindowSeconds': (danmaku['repeatedDanmakuWindowSeconds'] ?? 5).toInt().clamp(1, 30).toInt(),
      'savedDanmakuTemplate': danmaku['savedDanmakuTemplate']?.toString() ?? '',
      'pipDanmakuAutoScale': danmaku['pipDanmakuAutoScale'] ?? defaultPipDanmakuAutoScale,
      'pipDanmakuScaleValue': (danmaku['pipDanmakuScaleValue'] ?? defaultPipDanmakuScaleValue)
          .toDouble()
          .clamp(pipDanmakuScaleMin, pipDanmakuScaleMax)
          .toDouble(),
      'pipDanmakuNoEmojiMode':
          danmaku['pipDanmakuNoEmojiMode'] ?? danmaku['pipDanmaNoEmojiMode'] ?? defaultPipDanmakuNoEmojiMode,
      'pipDanmakuUseOriginalColor': danmaku['pipDanmakuUseOriginalColor'] ?? defaultPipDanmakuUseOriginalColor,
      'pipDanmakuColor': (danmaku['pipDanmakuColor'] ?? defaultPipDanmakuColor).toInt(),
      'pipDanmakuFontSize': (danmaku['pipDanmakuFontSize'] ?? defaultPipDanmakuFontSize)
          .toDouble()
          .clamp(8.0, 24.0)
          .toDouble(),
      'pipDanmakuFontWeight': normalizeFontWeight(
        danmaku['pipDanmakuFontWeight'],
        fallback: defaultPipDanmakuFontWeight,
      ),
      'pipDanmakuSpeed': (danmaku['pipDanmakuSpeed'] ?? defaultPipDanmakuSpeed)
          .toDouble()
          .clamp(20.0, 400.0)
          .toDouble(),
      'pipDanmakuOpacity': (danmaku['pipDanmakuOpacity'] ?? defaultPipDanmakuOpacity)
          .toDouble()
          .clamp(0.1, 1.0)
          .toDouble(),
      'pipDanmakuArea': (danmaku['pipDanmakuArea'] ?? defaultPipDanmakuArea).toDouble().clamp(0.1, 1.0).toDouble(),
      'pipDanmakuMaxVisibleCount': (danmaku['pipDanmakuMaxVisibleCount'] ?? defaultPipDanmakuMaxVisibleCount)
          .toInt()
          .clamp(1, 20)
          .toInt(),
      'pipDanmakuEmitInterval': (danmaku['pipDanmakuEmitInterval'] ?? defaultPipDanmakuEmitInterval)
          .toDouble()
          .clamp(0.05, 2.0)
          .toDouble(),
      'pipDanmakuFps': (danmaku['pipDanmakuFps'] ?? defaultPipDanmakuFps).toInt().clamp(15, 240).toInt(),
      'pipDanmakuAutoFps': danmaku['pipDanmakuAutoFps'] ?? defaultPipDanmakuAutoFps,
      'filterDouyuSuspectedAutomatedMessages':
          danmaku['filterDouyuSuspectedAutomatedMessages'] ?? defaultFilterDouyuSuspectedAutomatedMessages,
      'enableDanmakuSimilarityFilter': danmaku['enableDanmakuSimilarityFilter'] ?? defaultEnableDanmakuSimilarityFilter,
      'danmakuSimilarityThreshold': (danmaku['danmakuSimilarityThreshold'] ?? 85).toInt().clamp(50, 100).toInt(),
      'danmakuSimilarityCacheDuration': (danmaku['danmakuSimilarityCacheDuration'] ?? 3).toInt().clamp(1, 60).toInt(),
      'danmakuSimilarityMaxCacheSize': (danmaku['danmakuSimilarityMaxCacheSize'] ?? 100)
          .toInt()
          .clamp(20, 1000)
          .toInt(),
    };
    extracted[profilesKey] = ProfiledSettings.parse(profiledSpecs, danmaku[profilesKey], legacy: (_) => extracted);
    return extracted;
  }

  static Map<String, dynamic> mergeConfig(Map<String, dynamic> rootConfig, Map<String, dynamic> updateFields) {
    final danmaku = Map<String, dynamic>.from(rootConfig['danmaku'] ?? {});
    updateFields.forEach((k, v) => danmaku[k] = v);
    rootConfig['danmaku'] = danmaku;
    return rootConfig;
  }
}

/// How the chat list shows each message's danmaku colour.
enum ChatListColorMode {
  /// No colour mark.
  none,

  /// A coloured dot before the message.
  dot,

  /// The message text itself in that colour.
  text;

  static ChatListColorMode fromName(Object? name) =>
      values.firstWhere((mode) => mode.name == name, orElse: () => ChatListColorMode.none);
}
