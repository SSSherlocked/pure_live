import 'dart:async';

/// A live stream whose timestamps went back by [seconds]: the line sent
/// again what it had already sent.
class StreamReplay {
  const StreamReplay({required this.from, required this.to});

  /// The audio timestamp before the jump, in seconds.
  final double from;

  /// The audio timestamp it jumped back to, in seconds.
  final double to;

  double get seconds => from - to;
}

/// Spots a live line that replays what it already sent, from mpv's log.
///
/// A CDN edge that loses its origin can send its cached last seconds again
/// and close the connection a few seconds later (Huya al.flv on macOS:
/// `Invalid audio PTS: 669.65 -> 662.52`, then mpv resets playback and plays
/// those 7 s again, smoothly, before the connection ends). Nothing fails,
/// so nothing else notices: the viewer just sees the same seconds twice.
/// mpv reports the jump as a warning from its audio decoder.
abstract final class StreamReplayDetector {
  /// A jump back shorter than this is timestamp jitter, not a replay.
  static const double minSeconds = 2;

  /// A jump back longer than this is a stream that restarted its clock
  /// (an encoder restart), which plays on as it is.
  static const double maxSeconds = 60;

  static final RegExp _audioPts = RegExp(r'^Invalid audio PTS: (\d+(?:\.\d+)?) -> (\d+(?:\.\d+)?)');

  static final StreamController<StreamReplay> _replays = StreamController<StreamReplay>.broadcast(sync: true);

  /// Every replay seen in any mpv player's log.
  static Stream<StreamReplay> get replays => _replays.stream;

  /// The replay one mpv log line reports, if it reports one.
  static StreamReplay? parse({required String prefix, required String level, required String text}) {
    if (prefix != 'ad' || level != 'warn') return null;
    final match = _audioPts.firstMatch(text.trim());
    if (match == null) return null;
    final from = double.tryParse(match.group(1)!);
    final to = double.tryParse(match.group(2)!);
    if (from == null || to == null) return null;
    final replay = StreamReplay(from: from, to: to);
    if (replay.seconds < minSeconds || replay.seconds > maxSeconds) return null;
    return replay;
  }

  /// Passes one mpv log line; a replay it reports goes to [replays].
  static void observe({required String prefix, required String level, required String text}) {
    final replay = parse(prefix: prefix, level: level, text: text);
    if (replay != null) _replays.add(replay);
  }
}
