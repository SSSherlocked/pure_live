import 'dart:convert';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/platform/file_utils.dart';
import 'package:pure_live/core/network/race_http.dart';
import 'package:pure_live/core/models/release_model.dart';

typedef ReleaseHistoryExternalLauncher = Future<bool> Function(Uri uri);
typedef ReleaseHistoryLoader = Future<List<ReleaseModel>> Function();

class ReleaseHistoryRepository {
  ReleaseHistoryRepository._();

  static final ReleaseHistoryRepository instance = ReleaseHistoryRepository._();

  static const Map<String, String> defaultHeaders = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36',
    'Accept': 'application/json,text/plain,*/*',
  };

  static const String releaseAssetPath = 'assets/releases.json';

  static const Duration _fetchTimeout = Duration(seconds: 15);

  List<ReleaseModel>? _cache;

  Future<List<ReleaseModel>> load({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache != null) {
      return _cache!;
    }

    final releases = await RaceHttp.fetchFreshest<List<ReleaseModel>>(
      _sourceUrls(),
      headers: defaultHeaders,
      timeout: _fetchTimeout,
      parse: (body) {
        try {
          return parse(json.decode(body));
        } catch (_) {
          return null;
        }
      },
      compare: compareReleaseLists,
    );
    if (releases == null) {
      throw StateError('No release history source responded');
    }
    _cache = releases;
    return releases;
  }

  void clearCache() {
    _cache = null;
  }

  List<String> _sourceUrls() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    return [
      for (final source in VersionUtil.mirror.mirrors(releaseAssetPath))
        Uri.parse(source).replace(queryParameters: {...Uri.parse(source).queryParameters, 'ts': timestamp}).toString(),
    ];
  }

  List<ReleaseModel> parse(Object? decoded) {
    final rawReleases = switch (decoded) {
      List values => values,
      Map values when values['releases'] is List => values['releases'] as List,
      _ => null,
    };
    if (rawReleases == null) {
      throw const FormatException('Invalid release history payload');
    }

    final releases = <ReleaseModel>[];
    for (final entry in rawReleases) {
      if (entry is! Map) continue;
      final release = ReleaseModel.fromJson(Map<String, dynamic>.from(entry));
      if (release.version.trim().isEmpty) continue;
      releases.add(release);
    }
    releases.sort((left, right) {
      final byDate = right.date.compareTo(left.date);
      return byDate != 0 ? byDate : compareReleaseVersions(right.version, left.version);
    });
    return List.unmodifiable(releases);
  }

  /// An http(s) link without embedded credentials, or null.
  Uri? webUri(String rawUrl) {
    final uri = FileUtils.parseHttpUrl(rawUrl);
    return uri == null || uri.userInfo.isNotEmpty ? null : uri;
  }
}

/// Numeric comparison of dotted versions, so 3.2.10 sorts after 3.2.9 when two
/// releases share a date. Non-numeric parts fall back to text order.
int compareReleaseVersions(String left, String right) {
  List<String> parts(String value) => value.trim().replaceFirst(RegExp(r'^[vV]'), '').split(RegExp(r'[.+-]'));
  final a = parts(left);
  final b = parts(right);
  for (var i = 0; i < a.length || i < b.length; i++) {
    final x = i < a.length ? a[i] : '0';
    final y = i < b.length ? b[i] : '0';
    final nx = int.tryParse(x);
    final ny = int.tryParse(y);
    final byPart = nx != null && ny != null ? nx.compareTo(ny) : x.compareTo(y);
    if (byPart != 0) return byPart;
  }
  return 0;
}

/// Which of two copies of the release list is newer: the one whose newest
/// release is newer, then the longer one.
int compareReleaseLists(List<ReleaseModel> left, List<ReleaseModel> right) {
  String newest(List<ReleaseModel> releases) =>
      releases.map((release) => release.version).fold('', (a, b) => compareReleaseVersions(a, b) >= 0 ? a : b);
  final byVersion = compareReleaseVersions(newest(left), newest(right));
  return byVersion != 0 ? byVersion : left.length.compareTo(right.length);
}
