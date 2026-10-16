/// The line to move to when the line at [current] replays what it sent.
///
/// The replay comes from the CDN edge, so the same host would most likely do
/// it again. Lines after [current] are looked at in order (wrapping), first
/// one of the same kind (stream or manifest) on another host, then one of
/// the other kind on another host, then any other line: a Huya al.flv line
/// moves to tx.flv, not to al.hls. Returns null when there is no other line.
int? lineAfterReplay(List<Uri> lines, int current) {
  if (lines.length < 2 || current < 0 || current >= lines.length) return null;
  final from = lines[current];
  final others = [for (var step = 1; step < lines.length; step++) (current + step) % lines.length];
  bool sameKind(int index) => _isManifest(lines[index]) == _isManifest(from);
  bool otherHost(int index) => lines[index].host.toLowerCase() != from.host.toLowerCase();
  for (final test in <bool Function(int)>[
    (index) => sameKind(index) && otherHost(index),
    otherHost,
    (_) => true,
  ]) {
    for (final index in others) {
      if (test(index)) return index;
    }
  }
  return null;
}

bool _isManifest(Uri uri) => uri.path.toLowerCase().endsWith('.m3u8');
