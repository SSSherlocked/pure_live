import '../core/barrage_config.dart';
import '../model/barrage/barrage_track.dart';
import '../model/barrage/barrage_entry.dart';

/// Picks the lane for a new scroll message.
///
/// Pure Live change: lanes fill from the top. A message takes the topmost lane
/// whose previous message has fully entered the screen (plus the safe gap), so
/// a quiet room keeps its danmaku in the first few lines and only a busy room
/// spreads down the area - the way Simple Live lays them out. Upstream jumped
/// to the first *empty* lane, which spread even a handful of messages over
/// the whole area. [SpeedStrategy] still slows a message that would otherwise
/// catch up with the one ahead of it in the lane.
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
      if (last != null && last.x + last.width + config.overlapSafeGap > screenWidth) {
        continue;
      }
      return i;
    }
    return -1;
  }
}
