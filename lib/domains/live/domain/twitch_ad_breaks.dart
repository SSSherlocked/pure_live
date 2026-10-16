import 'dart:async';

/// Twitch ad breaks the HLS relay took out of the stream.
///
/// The relay reports each playlist that had ad segments: `true` while the
/// break is still running (the player waits on purpose, see
/// LivePlayerFacade), `false` once the live stream is back in it.
abstract final class TwitchAdBreaks {
  static final StreamController<bool> _reports = StreamController<bool>.broadcast(sync: true);

  static Stream<bool> get reports => _reports.stream;

  static void report({required bool ongoing}) => _reports.add(ongoing);
}
