import '../core/barrage_config.dart';
import '../model/barrage/barrage_track.dart';

class TrackManager {
  final List<BarrageTrack> _tracks = [];
  List<BarrageTrack> get tracks => _tracks;

  double _lastHeight = -1.0;
  int _lastMaxTracks = -1;

  void initialize(BarrageConfig config, double screenHeight) {
    if (screenHeight <= 0) return;

    // The lane count and the lane positions (BarrageDataSystem) must use the
    // same height: a floor applied here alone froze the count while the
    // positions kept following trackHeight, so a small gap stopped working.
    final double safeTrackHeight = config.trackHeight > 1 ? config.trackHeight : 1;

    final double usableHeight = screenHeight * config.area;
    int calculatedTracks = (usableHeight / safeTrackHeight).floor();

    if (calculatedTracks <= 0) calculatedTracks = 1;

    if (_lastHeight == screenHeight && _lastMaxTracks == calculatedTracks && _tracks.length == calculatedTracks) {
      return;
    }

    _lastHeight = screenHeight;
    _lastMaxTracks = calculatedTracks;

    final Map<int, BarrageTrack> oldTracksMap = {for (var t in _tracks) t.index: t};
    _tracks.clear();

    for (int i = 0; i < calculatedTracks; i++) {
      final oldTrack = oldTracksMap[i];
      if (oldTrack != null) {
        _tracks.add(oldTrack);
      } else {
        _tracks.add(BarrageTrack(index: i));
      }
    }
  }

  void forceRefresh(BarrageConfig config, double screenHeight) {
    _lastHeight = -1.0;
    _lastMaxTracks = -1;
    initialize(config, screenHeight);
  }
}
