/// Sections of the live room side panel, in the order users can rearrange.
enum LivePanelTab {
  danmakuList('danmaku_list'),
  superChat('super_chat'),
  follow('follow'),
  danmakuSettings('danmaku_settings');

  const LivePanelTab(this.id);

  /// Stable id stored in preferences; also the section's i18n key.
  final String id;

  String get labelKey => id;

  /// Short label for the room panel's tab bar (弹幕 / 留言 / 关注 / 设置).
  String get shortLabelKey => switch (this) {
    LivePanelTab.danmakuList => 'panel_tab_danmaku',
    LivePanelTab.superChat => 'panel_tab_super_chat',
    LivePanelTab.follow => 'follow',
    LivePanelTab.danmakuSettings => 'panel_tab_settings',
  };

  /// Default order: 关注 sits right after 醒目留言. 屏蔽管理 is the last
  /// section of 弹幕设置 rather than a tab of its own.
  static const List<LivePanelTab> defaultOrder = [danmakuList, superChat, follow, danmakuSettings];

  static String encode(List<LivePanelTab> order) => order.map((tab) => tab.id).join(',');

  static final String defaultOrderValue = encode(defaultOrder);

  /// Parses a stored order. Unknown or repeated ids are dropped and sections
  /// missing from the value are appended in their default position order, so
  /// every section always appears exactly once.
  static List<LivePanelTab> decode(String? raw) {
    final result = <LivePanelTab>[];
    for (final id in (raw ?? '').split(',')) {
      final match = LivePanelTab.values.where((tab) => tab.id == id.trim());
      if (match.isNotEmpty && !result.contains(match.first)) result.add(match.first);
    }
    for (final tab in defaultOrder) {
      if (!result.contains(tab)) result.add(tab);
    }
    return result;
  }
}

/// Width of the live room side panel in the desktop/landscape split. Set in
/// 主题 settings or by dragging the panel's edge in the room.
abstract final class LivePanelWidth {
  static const double min = 220;
  static const double max = 720;
  static const double defaultValue = 300;

  /// Never let the panel take more than this share of the window, so the video
  /// keeps most of it.
  static const double maxShare = 0.6;

  static double normalize(double value) => value.isFinite ? value.clamp(min, max).toDouble() : defaultValue;

  /// The width used for a window [availableWidth] wide.
  static double resolve(double preferred, double availableWidth) {
    final width = normalize(preferred);
    final cap = availableWidth * maxShare;
    return cap < min ? width.clamp(0, cap).toDouble() : width.clamp(min, cap).toDouble();
  }
}
