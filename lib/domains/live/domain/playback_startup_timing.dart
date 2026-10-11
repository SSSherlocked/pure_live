import 'package:pure_live/core/logging/app_log.dart';

/// One timing line per room entry, from opening the room to the first frame.
///
/// `playback-timing site=<id> room=<hash> detail=<ms> urls=<ms> open=<ms>
/// firstFrame=<ms>`, every value measured from the room load start. Uses a
/// monotonic [Stopwatch]: the wall clock can jump while a phone syncs network
/// time. The end mark needs a playing engine *and* a picture (or an
/// audio-only room), because mpv reports "playing" right after load, before
/// any frame is shown.
class PlaybackStartupTiming {
  PlaybackStartupTiming._();

  static final PlaybackStartupTiming instance = PlaybackStartupTiming._();

  final Stopwatch _clock = Stopwatch();
  final Map<String, int> _marks = <String, int>{};
  String _site = '';
  String _room = '';
  bool _active = false;

  /// Starts timing a room load; restarts if one was already running.
  void begin({required String site, required String roomId}) {
    _site = site;
    // A short hash keeps the log line free of the room id itself.
    _room = (roomId.hashCode & 0xffffff).toRadixString(16);
    _marks.clear();
    _clock
      ..reset()
      ..start();
    _active = true;
  }

  /// Records the first time [name] happens in the current load.
  void mark(String name) {
    if (!_active) return;
    _marks.putIfAbsent(name, () => _clock.elapsedMilliseconds);
  }

  /// Ends the measurement once the room shows its first frame.
  void reportPlaybackState({required bool playing, required bool hasPicture, required bool audioOnly}) {
    if (!_active || !playing || !(hasPicture || audioOnly)) return;
    mark('firstFrame');
    _active = false;
    _clock.stop();
    final parts = ['detail', 'urls', 'open', 'firstFrame'].map((name) => '$name=${_marks[name] ?? '-'}').join(' ');
    Log.i('playback-timing site=$_site room=$_room $parts');
  }

  /// Drops an unfinished measurement (room left or failed).
  void cancel() {
    _active = false;
    _clock.stop();
  }
}
