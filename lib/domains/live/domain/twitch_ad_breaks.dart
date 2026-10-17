import 'dart:async';

/// Twitch ad breaks the HLS relay took out of the stream.
///
/// The relay reports each playlist that had ad segments: `ongoing` while the
/// break is still running (the player waits on purpose, see
/// LivePlayerFacade), not once the live stream is back in it. `marker` says
/// what marked the first ad segment, for the log. `holding` is a pre-roll:
/// the line waits before the player opens, so nothing plays meanwhile.
typedef TwitchAdReport = ({bool ongoing, String? marker, bool holding});

abstract final class TwitchAdBreaks {
  static final StreamController<TwitchAdReport> _reports = StreamController<TwitchAdReport>.broadcast(sync: true);

  static Stream<TwitchAdReport> get reports => _reports.stream;

  static void report({required bool ongoing, String? marker, bool holding = false}) =>
      _reports.add((ongoing: ongoing, marker: marker, holding: holding));
}
