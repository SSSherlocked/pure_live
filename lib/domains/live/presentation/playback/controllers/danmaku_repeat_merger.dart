import 'dart:collection';

import 'package:pure_live/core/models/live_message.dart';

/// Folds a burst of identical chat lines into the first one.
///
/// "合并相同弹幕" used to drop every copy after the first, so a room-wide
/// "666" left one line and no trace of how many sent it. This remembers the
/// line that was shown for each text and hands it back for every repeat, so
/// the chat list can count the repeats on that line (×N) instead.
///
/// A burst lasts while copies keep arriving: each repeat extends it by
/// [window], so a chant that goes on for a minute stays one line. Whitespace
/// and case are ignored for comparison only. Local messages (your own sends)
/// and non-chat messages are never folded.
class DanmakuRepeatMerger {
  DanmakuRepeatMerger({this.maxEntries = 1024}) : assert(maxEntries > 0);

  /// Upper bound on remembered texts, so a busy room cannot grow it unbounded.
  final int maxEntries;

  /// Ordered by last arrival, so the stalest burst is evicted first.
  final LinkedHashMap<String, _Burst> _bursts = LinkedHashMap<String, _Burst>();

  /// The line already shown that [message] repeats, or null when [message] is
  /// to be shown itself (and becomes the line later repeats fold into).
  ///
  /// [now] exists for deterministic tests; production callers omit it.
  LiveMessage? repeatOf(LiveMessage message, {required Duration window, DateTime? now}) {
    if (message.type != LiveMessageType.chat || message.isLocal) return null;
    final key = normalize(message.message);
    if (key.isEmpty) return null;

    final at = now ?? DateTime.now();
    _evict(at, window);
    final burst = _bursts.remove(key);
    if (burst != null && at.difference(burst.lastSeen) <= window) {
      _bursts[key] = _Burst(burst.shown, at);
      return burst.shown;
    }
    _bursts[key] = _Burst(message, at);
    while (_bursts.length > maxEntries) {
      _bursts.remove(_bursts.keys.first);
    }
    return null;
  }

  /// Forgets every burst (a new room or session).
  void clear() => _bursts.clear();

  /// Number of remembered texts. Exposed for tests.
  int get size => _bursts.length;

  static String normalize(String text) => text.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  void _evict(DateTime now, Duration window) {
    while (_bursts.isNotEmpty && now.difference(_bursts.values.first.lastSeen) > window) {
      _bursts.remove(_bursts.keys.first);
    }
  }
}

class _Burst {
  const _Burst(this.shown, this.lastSeen);

  final LiveMessage shown;
  final DateTime lastSeen;
}
