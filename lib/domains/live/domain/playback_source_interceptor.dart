import 'package:flutter/foundation.dart' show immutable;
import 'package:media_core/media_core.dart';
import 'package:pure_live/core/stream/hls_source_query_policy.dart';
import 'package:pure_live/shared/platforms/live_site.dart';

@immutable
class PlaybackSourceInterception {
  const PlaybackSourceInterception({
    required this.sources,
    this.streamFacts = const <String, LiveStreamFacts>{},
    this.sourceQueryPolicies = const <String, HlsSourceQueryPolicy>{},
    this.blockTwitchAds = false,
    this.relayFirstLine = false,
  });

  final List<PlayerSource> sources;

  final Map<String, LiveStreamFacts> streamFacts;

  final Map<String, HlsSourceQueryPolicy> sourceQueryPolicies;

  /// Whether a Twitch line goes through the Dart relay with its ad segments
  /// taken out (see TwitchAdBreaks).
  final bool blockTwitchAds;

  /// Whether the first line goes through a Dart relay even when the native
  /// engine could read it (an FLV header that hides the video, see
  /// LivePlayerFacade's no-picture reopen).
  final bool relayFirstLine;
}

abstract interface class PlaybackSourceInterceptor {
  Future<List<PlayerSource>> intercept(PlaybackSourceInterception request);

  Future<void> release();

  Future<void> close();
}
