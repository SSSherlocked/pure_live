import 'dart:async';
import 'dart:io';

import 'package:media_core/media_core.dart';
import 'package:pure_live/core/logging/app_log.dart';

/// Whether [uri]'s host answers on the address a native engine connects to
/// first, within [timeout].
typedef LineProbe = Future<bool> Function(Uri uri, Duration timeout);

/// Orders a room's lines by reachability before the kernel sweeps them.
///
/// The kernel verifies lines one after another, each with a 10 s window. A
/// line whose host cannot be reached on the first address getaddrinfo
/// returns (an IPv6 address on a network where IPv6 to that CDN is
/// black-holed, or a node that accepts no connection) burns the whole window
/// before the next line gets its turn: a cold start on such a network sat
/// black and silent for 40 s while the one working line waited at the end of
/// the list. The probe connects to that same first address from Dart with a
/// short timeout, in parallel for every line, and moves the lines that fail
/// behind the ones that answer. No line is dropped: the engine still tries
/// them all, just in a better order.
class LinePreflight {
  LinePreflight({LineProbe? probe, this.timeout = const Duration(milliseconds: 1500)})
    : _probe = probe ?? connectProbe;

  final LineProbe _probe;

  /// Per-line budget; the whole preflight takes at most this plus a little.
  final Duration timeout;

  /// A host's answer is kept for a while: the same room asks again on every
  /// line refresh, and a black-holed address does not heal in minutes.
  static const Duration memoTtl = Duration(minutes: 5);
  final Map<String, ({bool reachable, DateTime at})> _memo = <String, ({bool reachable, DateTime at})>{};

  /// [sources] with the unreachable http(s) lines moved last, relative order
  /// kept on both sides. Fewer than two probeable lines, or no difference
  /// between them, returns [sources] as given.
  Future<List<PlayerSource>> order(List<PlayerSource> sources) async {
    final probed = <int>[
      for (var index = 0; index < sources.length; index++)
        if (_isProbeable(sources[index].uri)) index,
    ];
    if (probed.length < 2) return sources;

    final clock = Stopwatch()..start();
    final results = await Future.wait<bool>([for (final index in probed) _reachable(sources[index].uri)]);
    final unreachable = <int>{
      for (var position = 0; position < probed.length; position++)
        if (!results[position]) probed[position],
    };
    final hosts = unreachable.map((index) => sources[index].uri.host).join(', ');
    if (unreachable.isEmpty || unreachable.length == probed.length) {
      Log.i(
        'line preflight: ${probed.length} line(s), ${unreachable.length} unreachable, order kept '
        '(${clock.elapsedMilliseconds} ms)${hosts.isEmpty ? '' : ': $hosts'}',
      );
      return sources;
    }
    Log.i(
      'line preflight: ${unreachable.length} of ${probed.length} line(s) moved last '
      '(${clock.elapsedMilliseconds} ms): $hosts',
    );
    return <PlayerSource>[
      for (var index = 0; index < sources.length; index++)
        if (!unreachable.contains(index)) sources[index],
      for (var index = 0; index < sources.length; index++)
        if (unreachable.contains(index)) sources[index],
    ];
  }

  static bool _isProbeable(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;
    final host = uri.host;
    if (host.isEmpty || host == 'localhost') return false;
    final literal = InternetAddress.tryParse(host);
    return literal == null || !literal.isLoopback;
  }

  Future<bool> _reachable(Uri uri) async {
    final key = '${uri.host}:${uri.port}';
    final now = DateTime.now();
    final memo = _memo[key];
    if (memo != null && now.difference(memo.at) < memoTtl) return memo.reachable;
    bool reachable;
    try {
      reachable = await _probe(uri, timeout).timeout(timeout + const Duration(milliseconds: 500));
    } catch (_) {
      reachable = false;
    }
    _memo[key] = (reachable: reachable, at: now);
    return reachable;
  }

  /// The default probe: resolves the host and opens a TCP connection to the
  /// first address, which is the one ffmpeg and ijkplayer connect to first.
  static Future<bool> connectProbe(Uri uri, Duration timeout) async {
    final addresses = await InternetAddress.lookup(uri.host).timeout(timeout);
    if (addresses.isEmpty) return false;
    final socket = await Socket.connect(addresses.first, uri.port, timeout: timeout);
    socket.destroy();
    return true;
  }
}
