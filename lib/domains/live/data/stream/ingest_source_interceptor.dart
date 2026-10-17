
import 'package:media_core/media_core.dart';
import 'package:pure_live/core/player/core/playback_input_lease.dart';
import 'package:pure_live/domains/live/domain/playback_source_interceptor.dart';

import 'line_preflight.dart';
import 'playback_source_transport.dart';
import 'package:pure_live/core/logging/app_log.dart';

class IngestSourceInterceptor implements PlaybackSourceInterceptor {
  IngestSourceInterceptor({PlaybackSourceTransport? transport, LinePreflight? preflight})
    : _transport = transport ?? PlaybackSourceTransport(),
      _preflight = preflight;

  final PlaybackSourceTransport _transport;

  /// Reorders the lines by reachability first, when the host installs one.
  final LinePreflight? _preflight;

  @override
  Future<List<PlayerSource>> intercept(PlaybackSourceInterception request) async {
    List<PlayerSource> sources = request.sources;
    if (sources.isEmpty) return sources;
    final preflight = _preflight;
    LineReach? verdict;
    if (preflight != null) {
      final outcome = await preflight.order(sources);
      sources = outcome.sources;
      verdict = outcome.verdictOf(sources.first.uri);
    }
    final PlayerSource primary = sources.first;
    if (!const <String>{'http', 'https'}.contains(primary.uri.scheme.toLowerCase())) return sources;
    final String url = primary.uri.toString();
    final PlaybackInputLease? lease;
    try {
      lease = await _transport.prepare(
        url: url,
        headers: primary.headers?.values ?? const <String, String>{},
        facts: request.streamFacts[url],
        policy: request.sourceQueryPolicies[url],
        // Only its first address is dead: a Dart relay reaches the others.
        relayPreferred: verdict == LineReach.firstAddressDead || request.relayFirstLine,
        blockTwitchAds: request.blockTwitchAds,
      );
    } catch (error) {
      Log.dev('relay unavailable, playing the upstream directly: $error', name: 'PlaybackIngest');
      return sources;
    }
    if (lease == null || !lease.isUsable) return sources;
    // Host only: a signed live URL carries its token in the query.
    Log.dev('relay ${primary.uri.host} -> ${lease.uri}', name: 'PlaybackIngest');
    return <PlayerSource>[primary.copyWith(uri: lease.uri, headers: SourceHeaders.empty), ...sources.skip(1)];
  }

  @override
  Future<void> release() => _transport.release();

  @override
  Future<void> close() => _transport.close();
}
