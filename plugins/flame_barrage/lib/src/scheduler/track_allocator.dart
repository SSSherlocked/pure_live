import '../core/barrage_config.dart';
import '../model/barrage/barrage_track.dart';
import '../model/barrage/barrage_entry.dart';

/// Picks the lane for a new scroll message.
///
/// Pure Live change: lanes fill from the top. A message takes the topmost lane
/// whose previous message has fully entered the screen (plus the safe gap)
/// and that the new message, at the configured speed, will not catch before
/// the previous one leaves - so a quiet room keeps its danmaku in the first
/// few lines and only a busy room spreads down the area, the way Simple Live
/// lays them out. Upstream jumped to the first *empty* lane, which spread even
/// a handful of messages over the whole area.
///
/// The catch-up check is what keeps every message at the configured speed: a
/// lane that would need the new message slowed is skipped instead. Slowing it
/// (upstream's [SpeedStrategy] did 95 % of the one ahead) compounded in a
/// lane that never empties, until a busy room's top lanes crawled at the
/// right edge and left the rest of the screen empty.
class TrackAllocator {
  const TrackAllocator();

  int allocate({
    required List<BarrageTrack> tracks,
    required BarrageEntry current,
    required double screenWidth,
    required BarrageConfig config,
  }) {
    final int len = tracks.length;
    for (int i = 0; i < len; i++) {
      final track = tracks[i];
      if (track.locked) continue;
      if (track.activeCount == 0) return i;

      final last = track.lastEntry;
      if (last == null) return i;
      final lastRight = last.x + last.width;
      // The previous message has not fully entered yet.
      if (lastRight + config.overlapSafeGap > screenWidth) continue;
      if (_wouldCatchUp(last, lastRight, screenWidth, config)) continue;
      return i;
    }
    return -1;
  }

  /// Whether a new message entering at the right edge at the configured
  /// speed would close the gap to [last] before [last] leaves the screen.
  static bool _wouldCatchUp(BarrageEntry last, double lastRight, double screenWidth, BarrageConfig config) {
    final closingSpeed = config.baseSpeed - last.speed;
    if (closingSpeed <= 0 || last.speed <= 0) return false;
    final gap = screenWidth - lastRight - config.overlapSafeGap;
    final lastLeavesIn = lastRight / last.speed;
    return closingSpeed * lastLeavesIn > gap;
  }
}
