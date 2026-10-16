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
    this.relayCleanManifests = true,
  });

  final List<PlayerSource> sources;

  final Map<String, LiveStreamFacts> streamFacts;

  final Map<String, HlsSourceQueryPolicy> sourceQueryPolicies;

  /// Whether an HLS line whose manifest needs no rewrite still goes through
  /// the Dart relay (for mpv and ijkplayer). A system player reads it
  /// directly.
  final bool relayCleanManifests;
}

/// Whether [url] is an HLS line: as the platform declared it, else by its
/// path.
bool isHlsLine(String url, LiveStreamFacts? facts) {
  if (facts != null) return facts.format == LiveStreamFormat.hls;
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
  return path.endsWith('.m3u8') || _playlistPath.hasMatch(path);
}

final RegExp _playlistPath = RegExp(r'/(master_)?playlist$');

abstract interface class PlaybackSourceInterceptor {
  Future<List<PlayerSource>> intercept(PlaybackSourceInterception request);

  Future<void> release();

  Future<void> close();
}
