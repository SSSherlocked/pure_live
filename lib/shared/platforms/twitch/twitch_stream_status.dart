import 'package:pure_live/core/models/live_room.dart';

/// The status a Twitch stream's `type` stands for.
///
/// `live` is live. `rerun` is a past broadcast played again: it plays like a
/// live stream but is 录播, in the room and in every list alike. No stream at
/// all is offline. [fallback] is what any other type counts as, and a
/// stream whose query does not return its type: offline where the channel's
/// own metadata always says (`StreamMetadata`), live in a directory that only
/// lists streams.
LiveStatus twitchStreamStatus({required bool hasStream, String? type, LiveStatus fallback = LiveStatus.offline}) {
  if (!hasStream) return LiveStatus.offline;
  return switch (type?.trim().toLowerCase()) {
    'live' => LiveStatus.live,
    'rerun' => LiveStatus.replay,
    _ => fallback,
  };
}
