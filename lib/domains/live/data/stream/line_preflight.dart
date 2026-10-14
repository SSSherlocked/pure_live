import 'dart:async';
import 'dart:io';

import 'package:media_core/media_core.dart';
import 'package:pure_live/core/logging/app_log.dart';

/// What a line's host answered when probed before the kernel opens it.
enum LineReach {
  /// The first address the resolver returns accepts a connection: a native
  /// engine will get through on its own.
  reachable,

  /// The first address never answered, but another one did (an IPv6
  /// address on a network where IPv6 to that CDN is black-holed, with IPv4
  /// fine). A native engine sits on the first address for its whole
  /// connect timeout; a Dart relay, which tries every address, does not.
  firstAddressDead,

  /// No address answered in time.
  dead,
}

/// Probes [uri]'s host within [timeout].
typedef LineProbe = Future<LineReach> Function(Uri uri, Duration timeout);

/// The lines in the order the kernel should sweep them, plus what the probe
/// found out about each host.
class LinePreflightOutcome {
  const LinePreflightOutcome(this.sources, this._verdicts);

  final List<PlayerSource> sources;
  final Map<String, LineReach> _verdicts;

  /// The verdict for [uri]'s host, when it was probed.
  LineReach? verdictOf(Uri uri) => _verdicts[LinePreflight.hostKey(uri)];
}

/// Orders a room's lines by reachability before the kernel sweeps them.
///
/// The kernel verifies lines one after another, each with a 10 s window. A
/// line whose host cannot be reached on the first address getaddrinfo
/// returns (an IPv6 address on a network where IPv6 to that CDN is
/// black-holed, or a node that accepts no connection) burns the whole window
/// before the next line gets its turn: a cold start on such a network sat
/// black and silent for 40 s while the one working line waited at the end of
/// the list. The probe connects from Dart with a short timeout, in parallel
/// for every line, and moves the lines that fail behind the ones that
/// answer. No line is dropped: the engine still tries them all, just in a
/// better order. A line whose host is only reachable past its first address
/// is reported as such, so the caller can hand it to a Dart relay instead of
/// a native engine.
class LinePreflight {
  LinePreflight({LineProbe? probe, this.timeout = const Duration(milliseconds: 1500)})
    : _probe = probe ?? connectProbe;

  final LineProbe _probe;

  /// Per-line budget; the whole preflight takes at most this plus a little.
  final Duration timeout;

  /// A host's answer is kept for a while: the same room asks again on every
  /// line refresh, and a black-holed address does not heal in minutes.
  static const Duration memoTtl = Duration(minutes: 5);
  final Map<String, ({LineReach reach, DateTime at})> _memo = <String, ({LineReach reach, DateTime at})>{};

  static String hostKey(Uri uri) => '${uri.host.toLowerCase()}:${uri.port}';

  /// Probes the http(s) lines of [sources] and returns them with the ones
  /// that did not answer moved last, relative order kept on both sides.
  Future<LinePreflightOutcome> order(List<PlayerSource> sources) async {
    final probed = <int>[
      for (var index = 0; index < sources.length; index++)
        if (_isProbeable(sources[index].uri)) index,
    ];
    if (probed.isEmpty) return LinePreflightOutcome(sources, const <String, LineReach>{});

    final clock = Stopwatch()..start();
    final results = await Future.wait<LineReach>([for (final index in probed) _reach(sources[index].uri)]);
    final verdicts = <String, LineReach>{
      for (var position = 0; position < probed.length; position++)
        hostKey(sources[probed[position]].uri): results[position],
    };
    final unreachable = <int>{
      for (var position = 0; position < probed.length; position++)
        if (results[position] != LineReach.reachable) probed[position],
    };
    final hosts = unreachable
        .map((index) => '${sources[index].uri.host} (${verdicts[hostKey(sources[index].uri)]!.name})')
        .join(', ');
    if (unreachable.isEmpty || unreachable.length == probed.length) {
      Log.i(
        'line preflight: ${probed.length} line(s), ${unreachable.length} unreachable, order kept '
        '(${clock.elapsedMilliseconds} ms)${hosts.isEmpty ? '' : ': $hosts'}',
      );
      return LinePreflightOutcome(sources, verdicts);
    }
    Log.i(
      'line preflight: ${unreachable.length} of ${probed.length} line(s) moved last '
      '(${clock.elapsedMilliseconds} ms): $hosts',
    );
    return LinePreflightOutcome(<PlayerSource>[
      for (var index = 0; index < sources.length; index++)
        if (!unreachable.contains(index)) sources[index],
      for (var index = 0; index < sources.length; index++)
        if (unreachable.contains(index)) sources[index],
    ], verdicts);
  }

  static bool _isProbeable(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;
    final host = uri.host;
    if (host.isEmpty || host == 'localhost') return false;
    final literal = InternetAddress.tryParse(host);
    return literal == null || !literal.isLoopback;
  }

  Future<LineReach> _reach(Uri uri) async {
    final key = hostKey(uri);
    final now = DateTime.now();
    final memo = _memo[key];
    if (memo != null && now.difference(memo.at) < memoTtl) return memo.reach;
    LineReach reach;
    try {
      reach = await _probe(uri, timeout).timeout(timeout + const Duration(milliseconds: 500));
    } catch (_) {
      reach = LineReach.dead;
    }
    _memo[key] = (reach: reach, at: now);
    return reach;
  }

  /// The default probe. It resolves the host and, at the same time, opens a
  /// TCP connection to the first address (the one ffmpeg and ijkplayer try
  /// first) and one by host name (Dart tries every address, so this is what
  /// a relay would get).
  static Future<LineReach> connectProbe(Uri uri, Duration timeout) async {
    final addresses = await InternetAddress.lookup(uri.host).timeout(timeout);
    if (addresses.isEmpty) return LineReach.dead;
    final first = _connects(() => Socket.connect(addresses.first, uri.port, timeout: timeout));
    final any = addresses.length == 1 ? first : _connects(() => Socket.connect(uri.host, uri.port, timeout: timeout));
    if (await first) {
      unawaited(any);
      return LineReach.reachable;
    }
    return await any ? LineReach.firstAddressDead : LineReach.dead;
  }

  static Future<bool> _connects(Future<Socket> Function() connect) async {
    try {
      final socket = await connect();
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}
