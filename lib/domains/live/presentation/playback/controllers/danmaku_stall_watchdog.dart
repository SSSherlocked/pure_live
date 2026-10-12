/// Notices a danmaku session that has gone quiet without closing.
///
/// Engines reconnect on their own when a socket errors or closes, and the
/// shared socket layer when nothing at all arrives for a while. Neither catches
/// a server that keeps answering heartbeats but has stopped pushing the room —
/// an expired room registration, a dropped subscription. The video plays on
/// and the danmaku simply stops.
///
/// This learns the room's own pace from what actually arrives (chat, gifts,
/// audience counts) and calls a silence far beyond that pace a stall. A room
/// too quiet to have a pace is never judged, so a calm room is not
/// reconnected over and over.
class DanmakuStallWatchdog {
  DanmakuStallWatchdog({
    this.minSamples = 8,
    this.window = 20,
    this.gapMultiplier = 6,
    this.minThreshold = const Duration(seconds: 45),
    this.maxThreshold = const Duration(minutes: 5),
    this.cooldown = const Duration(minutes: 2),
  });

  /// Arrivals needed before the room has a pace at all.
  final int minSamples;

  /// How many recent arrivals the pace is measured over.
  final int window;

  /// Silence, in multiples of the room's average gap, that counts as a stall.
  final int gapMultiplier;
  final Duration minThreshold;
  final Duration maxThreshold;

  /// Least time between two recoveries, so a room that really went quiet is
  /// not reconnected in a loop.
  final Duration cooldown;

  final List<DateTime> _arrivals = <DateTime>[];
  DateTime? _lastRecovery;

  /// Something arrived from the room.
  void record(DateTime at) {
    _arrivals.add(at);
    if (_arrivals.length > window) _arrivals.removeAt(0);
  }

  /// A new session starts with no pace (recoveries keep their cooldown).
  void reset() => _arrivals.clear();

  /// The silence that counts as a stall, or null while the room has no pace.
  Duration? get threshold {
    if (_arrivals.length < minSamples) return null;
    final span = _arrivals.last.difference(_arrivals.first);
    final averageGap = span ~/ (_arrivals.length - 1);
    final scaled = averageGap * gapMultiplier;
    if (scaled < minThreshold) return minThreshold;
    if (scaled > maxThreshold) return maxThreshold;
    return scaled;
  }

  /// Whether the session should be reconnected at [now].
  bool shouldRecover(DateTime now) {
    final limit = threshold;
    if (limit == null) return false;
    if (now.difference(_arrivals.last) < limit) return false;
    final last = _lastRecovery;
    return last == null || now.difference(last) >= cooldown;
  }

  /// A recovery was started at [now].
  void markRecovered(DateTime now) {
    _lastRecovery = now;
    _arrivals.clear();
  }
}
