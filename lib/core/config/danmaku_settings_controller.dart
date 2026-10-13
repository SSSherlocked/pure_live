import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;
import 'package:pure_live/get/get.dart';
import 'package:pure_live/core/storage/hive_rx.dart';
import 'package:pure_live/core/layout/app_layout.dart';
import 'package:pure_live/core/storage/hive_pref_util.dart';
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
  static const int defaultChatListFontWeight = 500;
  static const int defaultChatListNameFontWeight = 700;
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

  /// How a message's danmaku colour shows in the chat list; a [ChatListColorMode] name.
  final RxString chatListColorMode = hiveString('chatListColorMode', ChatListColorMode.none.name);

  /// Whether the sender's name also takes the danmaku colour; independent of the mode.
  final RxBool chatListColorName = hiveBool('chatListColorName', false);

  /// Whether chat list messages show the sender's avatar (only Bilibili sends one).
  final RxBool chatListShowAvatar = hiveBool('chatListShowAvatar', true);

  /// Whether chat list messages show the sender's fan badge (Bilibili, Missevan, LOOK, KuGou).
  final RxBool chatListShowFansBadge = hiveBool('chatListShowFansBadge', true);

  /// 直播间文字亮度: how opaque text inside the live room is (50%-100%). Only
  /// the room page applies it; the rest of the app keeps full contrast.
  final RxDouble roomTextOpacity = hiveDouble('roomTextOpacity', 1.0);

  static double normalizeRoomTextOpacity(Object? raw) =>
      _boundedDouble(raw, fallback: 1.0, min: 0.5, max: 1.0);

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

  /// Hive and backup keys of the per-layout floating-danmaku style sets.
  static const String narrowStyleKey = 'danmakuStyleNarrow';
  static const String wideStyleKey = 'danmakuStyleWide';

  /// The floating-danmaku style of the narrow (phone) layout and of the wide
  /// one ([AppLayout.wide]), each kept as one JSON object in Hive.
  ///
  /// The public style fields ([danmakuSpeed], [danmakuFontSize], ...) always
  /// hold the set of the layout in [styleViewportWide]: every reader keeps
  /// reading them, every edit lands in that layout's set, and [useViewport]
  /// loads the other set when the layout changes. Their legacy Hive keys keep
  /// being written and so mirror the last active layout's style, which an
  /// older build reads unchanged. A missing set (first run of this version)
  /// starts from those legacy values, so nothing changes for the viewer.
  late final Rx<DanmakuOverlayStyle> narrowStyle = _styleStore(narrowStyleKey);
  late final Rx<DanmakuOverlayStyle> wideStyle = _styleStore(wideStyleKey);

  /// Whether the public style fields currently hold the wide layout's set.
  final RxBool styleViewportWide = false.obs;

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
    // Seed both per-layout sets (from the legacy values on first run), then
    // load the set of the layout known so far; AppShell switches it once the
    // real layout is resolved.
    _styleStoreFor(false);
    _styleStoreFor(true);
    styleViewportWide.value = AppLayout.current.wide;
    _applyStyle(_styleStoreFor(styleViewportWide.value).value);
    everAll(_styleFields, (_) => _captureActiveStyle());
  }

  List<Rx> get _styleFields => [
    danmakuTopArea,
    danmakuArea,
    danmakuBottomArea,
    danmakuSpeed,
    danmakuFontSize,
    danmakuFontWeight,
    danmakuFontBorder,
    danmakuOpacity,
    enableDanmakuStroke,
  ];

  Rx<DanmakuOverlayStyle> _styleStore(String key) {
    final legacy = _currentStyle();
    final stored = HivePrefUtil.getString(key);
    final store = hiveObject<DanmakuOverlayStyle>(
      key,
      legacy,
      fromJson: (json) => DanmakuOverlayStyle.parse(json, fallback: legacy),
      toJson: (style) => style.toJson(),
    );
    // Persist a seeded set right away: otherwise the next launch would seed
    // it again from legacy keys that by then mirror the other layout.
    if (stored == null || stored.isEmpty) {
      unawaited(HivePrefUtil.setString(key, jsonEncode(store.value.toJson())));
    }
    return store;
  }

  Rx<DanmakuOverlayStyle> _styleStoreFor(bool wide) => wide ? wideStyle : narrowStyle;

  /// The style the public fields hold right now.
  DanmakuOverlayStyle _currentStyle() => DanmakuOverlayStyle(
    topArea: danmakuTopArea.v,
    area: danmakuArea.v,
    bottomArea: danmakuBottomArea.v,
    speed: danmakuSpeed.v,
    fontSize: danmakuFontSize.v,
    fontWeight: danmakuFontWeight.v,
    fontBorder: danmakuFontBorder.v,
    opacity: danmakuOpacity.v,
    stroke: enableDanmakuStroke.v,
  );

  /// Writes the public fields into the active layout's set. Reads the fields
  /// themselves rather than a worker's event value, so a notification that
  /// arrives after a layout switch never carries one set into the other.
  void _captureActiveStyle() {
    _styleStoreFor(styleViewportWide.value).v = _currentStyle();
  }

  void _applyStyle(DanmakuOverlayStyle style) {
    danmakuTopArea.v = style.topArea;
    danmakuArea.v = style.area;
    danmakuBottomArea.v = style.bottomArea;
    danmakuSpeed.v = style.speed;
    danmakuFontSize.v = style.fontSize;
    danmakuFontWeight.v = style.fontWeight;
    danmakuFontBorder.v = style.fontBorder;
    danmakuOpacity.v = style.opacity;
    enableDanmakuStroke.v = style.stroke;
  }

  /// Makes the public style fields hold the narrow or the [wide] layout's
  /// set. Edits still pending for the previous layout are saved into its set
  /// first; the set being left is otherwise untouched.
  void useViewport(bool wide) {
    if (styleViewportWide.value == wide) return;
    _captureActiveStyle();
    styleViewportWide.value = wide;
    _applyStyle(_styleStoreFor(wide).value);
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
      'superChatOpacity': normalizeSuperChatOpacity(superChatOpacity.v),
      'superChatFontScale': normalizeSuperChatFontScale(superChatFontScale.v),
      'chatListFontSize': chatListFontSize.v,
      'chatListFontWeight': chatListFontWeight.v,
      'chatListNameFontWeight': chatListNameFontWeight.v,
      'chatListItemSpacing': chatListItemSpacing.v,
      'chatListBubble': chatListBubble.v,
      'chatListColorMode': chatListColorMode.v,
      'chatListColorName': chatListColorName.v,
      'chatListShowAvatar': chatListShowAvatar.v,
      'chatListShowFansBadge': chatListShowFansBadge.v,
      'roomTextOpacity': normalizeRoomTextOpacity(roomTextOpacity.v),
      'noEmojiMode': noEmojiMode.v,
      'danmakuTopArea': danmakuTopArea.v,
      'danmakuArea': danmakuArea.v,
      'danmakuMaxVisibleCount': danmakuMaxVisibleCount.v,
      'danmakuBottomArea': danmakuBottomArea.v,
      'danmakuSpeed': danmakuSpeed.v,
      'danmakuFontSize': danmakuFontSize.v,
      'danmakuFontWeight': danmakuFontWeight.v,
      'danmakuFontBorder': danmakuFontBorder.v,
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
      // The legacy single style keys above carry the active layout's set (what
      // an older build restores); these carry both sets. The active set is read
      // from the public fields so an edit not yet captured is not missed.
      narrowStyleKey: (styleViewportWide.value ? narrowStyle.value : _currentStyle()).toJson(),
      wideStyleKey: (styleViewportWide.value ? _currentStyle() : wideStyle.value).toJson(),
    };
  }

  /// Parse the complete section without notifying observers or persisting values.
  static Map<String, dynamic> parseConfig(Map<String, dynamic> json) {
    T typed<T>(dynamic value) => value as T;
    final parsed = <String, dynamic>{
      'hideDanmaku': typed<bool>(json['hideDanmaku'] ?? false),
      'showSuperChatOnPlayer': typed<bool>(json['showSuperChatOnPlayer'] ?? true),
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
      'chatListColorMode': ChatListColorMode.fromName(json['chatListColorMode']).name,
      'chatListColorName': typed<bool>(json['chatListColorName'] ?? false),
      'chatListShowAvatar': typed<bool>(json['chatListShowAvatar'] ?? true),
      'chatListShowFansBadge': typed<bool>(json['chatListShowFansBadge'] ?? true),
      'roomTextOpacity': typed<double>(normalizeRoomTextOpacity(json['roomTextOpacity'])),
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
    // A backup from before the per-layout sets has only the single style
    // values: both layouts take them.
    final legacyStyle = DanmakuOverlayStyle.fromConfig(parsed);
    parsed[narrowStyleKey] = DanmakuOverlayStyle.parse(json[narrowStyleKey], fallback: legacyStyle);
    parsed[wideStyleKey] = DanmakuOverlayStyle.parse(json[wideStyleKey], fallback: legacyStyle);
    return parsed;
  }

  void fromJson(Map<String, dynamic> json) {
    final parsed = parseConfig(json);
    hideDanmaku.v = parsed['hideDanmaku'];
    showSuperChatOnPlayer.v = parsed['showSuperChatOnPlayer'];
    superChatOpacity.v = parsed['superChatOpacity'];
    superChatFontScale.v = parsed['superChatFontScale'];
    chatListFontSize.v = parsed['chatListFontSize'];
    chatListFontWeight.v = parsed['chatListFontWeight'];
    chatListNameFontWeight.v = parsed['chatListNameFontWeight'];
    chatListItemSpacing.v = parsed['chatListItemSpacing'];
    chatListBubble.v = parsed['chatListBubble'];
    chatListColorMode.v = parsed['chatListColorMode'];
    chatListColorName.v = parsed['chatListColorName'];
    chatListShowAvatar.v = parsed['chatListShowAvatar'];
    chatListShowFansBadge.v = parsed['chatListShowFansBadge'];
    roomTextOpacity.v = parsed['roomTextOpacity'];
    danmakuMaxVisibleCount.v = parsed['danmakuMaxVisibleCount'];
    noEmojiMode.v = parsed['noEmojiMode'];
    // The style fields come from the restored set of the active layout below.
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
    narrowStyle.v = parsed[narrowStyleKey] as DanmakuOverlayStyle;
    wideStyle.v = parsed[wideStyleKey] as DanmakuOverlayStyle;
    _applyStyle(_styleStoreFor(styleViewportWide.value).value);
  }

  static Map<String, dynamic> extractConfig(Map<String, dynamic>? rootConfig) {
    final danmaku = rootConfig?['danmaku'] as Map<String, dynamic>? ?? {};
    final extracted = <String, dynamic>{
      'hideDanmaku': danmaku['hideDanmaku'] ?? false,
      'showSuperChatOnPlayer': danmaku['showSuperChatOnPlayer'] ?? true,
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
      'chatListColorMode': ChatListColorMode.fromName(danmaku['chatListColorMode']).name,
      'chatListColorName': danmaku['chatListColorName'] ?? false,
      'chatListShowAvatar': danmaku['chatListShowAvatar'] ?? true,
      'chatListShowFansBadge': danmaku['chatListShowFansBadge'] ?? true,
      'roomTextOpacity': normalizeRoomTextOpacity(danmaku['roomTextOpacity']),
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
    final legacyStyle = DanmakuOverlayStyle.fromConfig(extracted);
    extracted[narrowStyleKey] = DanmakuOverlayStyle.parse(danmaku[narrowStyleKey], fallback: legacyStyle).toJson();
    extracted[wideStyleKey] = DanmakuOverlayStyle.parse(danmaku[wideStyleKey], fallback: legacyStyle).toJson();
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

/// One layout's floating-danmaku style: what the narrow and the wide layout
/// keep separately (see [DanmakuSettingsController.narrowStyle]).
@immutable
class DanmakuOverlayStyle {
  const DanmakuOverlayStyle({
    required this.topArea,
    required this.area,
    required this.bottomArea,
    required this.speed,
    required this.fontSize,
    required this.fontWeight,
    required this.fontBorder,
    required this.opacity,
    required this.stroke,
  });

  final double topArea;
  final double area;
  final double bottomArea;
  final double speed;
  final double fontSize;
  final int fontWeight;
  final double fontBorder;
  final double opacity;
  final bool stroke;

  static double _double(Object? raw, double fallback, double min, double max) {
    if (raw is! num || !raw.isFinite) return fallback.clamp(min, max).toDouble();
    return raw.toDouble().clamp(min, max).toDouble();
  }

  static const DanmakuOverlayStyle defaults = DanmakuOverlayStyle(
    topArea: DanmakuSettingsController.defaultDanmakuTopArea,
    area: DanmakuSettingsController.defaultDanmakuArea,
    bottomArea: DanmakuSettingsController.defaultDanmakuBottomArea,
    speed: DanmakuSettingsController.defaultDanmakuSpeed,
    fontSize: DanmakuSettingsController.defaultDanmakuFontSize,
    fontWeight: DanmakuSettingsController.defaultDanmakuFontWeight,
    fontBorder: DanmakuSettingsController.defaultDanmakuFontBorder,
    opacity: DanmakuSettingsController.defaultDanmakuOpacity,
    stroke: true,
  );

  /// Reads a set stored by [toJson]. Each value is bounded like its single
  /// setting; a missing or malformed one (or a [raw] that is not a map at all)
  /// takes [fallback]'s value.
  static DanmakuOverlayStyle parse(Object? raw, {DanmakuOverlayStyle fallback = defaults}) {
    final json = raw is Map ? raw : const <String, dynamic>{};
    final weight = json['fontWeight'];
    final stroke = json['stroke'];
    final area = json['area'];
    return DanmakuOverlayStyle(
      topArea: _double(json['topArea'], fallback.topArea, 0, 300),
      area: DanmakuSettingsController.normalizeDanmakuArea(area is num && area.isFinite ? area : fallback.area),
      bottomArea: _double(json['bottomArea'], fallback.bottomArea, 0, 300),
      speed: _double(json['speed'], fallback.speed, 20, 400),
      fontSize: _double(json['fontSize'], fallback.fontSize, 10, 30),
      fontWeight: DanmakuSettingsController.normalizeFontWeight(
        weight is num && weight.isFinite ? weight : fallback.fontWeight,
      ),
      fontBorder: _double(json['fontBorder'], fallback.fontBorder, 0, 4),
      opacity: _double(json['opacity'], fallback.opacity, 0, 1),
      stroke: stroke is bool ? stroke : fallback.stroke,
    );
  }

  /// The single (legacy) style values of a parsed or extracted danmaku
  /// section, bounded the same way.
  static DanmakuOverlayStyle fromConfig(Map<String, dynamic> config) {
    return parse({
      'topArea': config['danmakuTopArea'],
      'area': config['danmakuArea'],
      'bottomArea': config['danmakuBottomArea'],
      'speed': config['danmakuSpeed'],
      'fontSize': config['danmakuFontSize'],
      'fontWeight': config['danmakuFontWeight'],
      'fontBorder': config['danmakuFontBorder'],
      'opacity': config['danmakuOpacity'],
      'stroke': config['enableDanmakuStroke'],
    });
  }

  Map<String, dynamic> toJson() => {
    'topArea': topArea,
    'area': area,
    'bottomArea': bottomArea,
    'speed': speed,
    'fontSize': fontSize,
    'fontWeight': fontWeight,
    'fontBorder': fontBorder,
    'opacity': opacity,
    'stroke': stroke,
  };

  @override
  bool operator ==(Object other) =>
      other is DanmakuOverlayStyle &&
      other.topArea == topArea &&
      other.area == area &&
      other.bottomArea == bottomArea &&
      other.speed == speed &&
      other.fontSize == fontSize &&
      other.fontWeight == fontWeight &&
      other.fontBorder == fontBorder &&
      other.opacity == opacity &&
      other.stroke == stroke;

  @override
  int get hashCode =>
      Object.hash(topArea, area, bottomArea, speed, fontSize, fontWeight, fontBorder, opacity, stroke);
}
