import 'dart:async';

import 'package:media_core_ingest/media_core_ingest.dart';
import 'package:pure_live/core/logging/app_log.dart';
import 'package:pure_live/domains/live/domain/twitch_ad_breaks.dart';

import 'playback_manifest_probe.dart';

/// Reads one playlist; null when it cannot be read.
typedef PlaylistReader = Future<String?> Function(String url, Map<String, String> headers);

Future<String?> _readPlaylist(String url, Map<String, String> headers) async =>
    (await probePlaybackManifest(url, headers: headers))?.body;

/// Holds a Twitch line back while a pre-roll ad runs.
///
/// Twitch starts a new viewer on an ad: the playlist lists only ad segments
/// and nothing of the broadcast. The relay can take ads out only by serving
/// the live run around them, and here there is none, so it had to hand the
/// ad to the player. Instead the line waits here, before the player opens,
/// reading the playlist every [interval] until the broadcast follows the ad
/// (see [withoutTwitchAds]), for at most [limit]; past it the line opens
/// anyway and the ad plays. The room shows its notice meanwhile
/// ([TwitchAdBreaks], reported as holding).
///
/// [url] is the line's master or media playlist; a master's first variant is
/// read, since every variant carries the same ads. Returns as soon as
/// [current] turns false (the room was left or the line replaced).
Future<void> waitOutTwitchPreroll(
  String url, {
  required Map<String, String> headers,
  required bool Function() current,
  PlaylistReader read = _readPlaylist,
  Duration interval = const Duration(seconds: 2),
  Duration limit = const Duration(seconds: 90),
}) async {
  final String? first = await read(url, headers);
  if (first == null || !current()) return;
  String mediaUrl = url;
  String? media = first;
  final String? variant = _firstVariant(first, Uri.parse(url));
  if (variant != null) {
    mediaUrl = variant;
    media = await read(mediaUrl, headers);
  }
  final Stopwatch waited = Stopwatch()..start();
  bool held = false;
  while (media != null && current()) {
    final TwitchAdFilterResult result = withoutTwitchAds(media);
    if (result.dropped == 0 || result.body != null) break;
    if (waited.elapsed >= limit) {
      Log.w('twitch: pre-roll still running after ${waited.elapsed.inSeconds} s; opening it');
      break;
    }
    if (!held) {
      held = true;
      Log.i('twitch: pre-roll (${result.marker}); the line waits for the broadcast');
    }
    TwitchAdBreaks.report(ongoing: true, marker: result.marker, holding: true);
    await Future<void>.delayed(interval);
    if (!current()) return;
    media = await read(mediaUrl, headers);
  }
  if (held && current()) {
    Log.i('twitch: pre-roll over after ${waited.elapsed.inSeconds} s');
    TwitchAdBreaks.report(ongoing: false);
  }
}

/// The first variant playlist of a master playlist, resolved against
/// [master]; null for a media playlist.
String? _firstVariant(String body, Uri master) {
  bool next = false;
  for (final String raw in body.split('\n')) {
    final String line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXT-X-STREAM-INF')) {
      next = true;
    } else if (next && !line.startsWith('#')) {
      return master.resolve(line).toString();
    }
  }
  return null;
}
