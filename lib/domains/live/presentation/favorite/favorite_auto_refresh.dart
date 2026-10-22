/// How often the followed rooms refresh by themselves, in the background as
/// well: the shorter of 刷新设置's 关注自动刷新 interval ([homeMinutes], when
/// [homeEnabled]) and 直播间信息页 › 关注刷新间隔 ([roomPanelMinutes], 0 is
/// off). Null when neither is on.
///
/// Every followed-room list (the home 关注 page, the room's 关注 tab and the
/// fullscreen 关注 panel) shows the same rooms, so one timer keeps them all
/// fresh, whichever is on screen.
Duration? favoriteAutoRefreshInterval({
  required bool homeEnabled,
  required int homeMinutes,
  required int roomPanelMinutes,
}) {
  final minutes = [if (homeEnabled && homeMinutes > 0) homeMinutes, if (roomPanelMinutes > 0) roomPanelMinutes];
  if (minutes.isEmpty) return null;
  return Duration(minutes: minutes.reduce((a, b) => a < b ? a : b));
}

/// The wait before the next automatic refresh: [interval] counted from the
/// last full refresh ([lastRefreshAt], whatever ran it: startup, a resume, the
/// room's 关注 list, the timer), zero once that has passed. With no full
/// refresh yet (startup is still verifying) a whole interval.
Duration favoriteAutoRefreshDelay({required Duration interval, required DateTime? lastRefreshAt, required DateTime now}) {
  if (lastRefreshAt == null) return interval;
  final remaining = interval - now.difference(lastRefreshAt);
  return remaining > Duration.zero ? remaining : Duration.zero;
}
