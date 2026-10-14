import 'package:pure_live/gen/env.g.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pure_live/core/release/github_mirror.dart';

class VersionUtil {
  static PackageInfo? _packageInfo;

  static final String updateOwner = AppConfig.pureliveUpdateOwner;
  static final String updateRepository = AppConfig.pureliveUpdateRepository;

  static final String projectUrl = 'https://github.com/$updateOwner/$updateRepository';

  static final GitHubMirror mirror = GitHubMirror(owner: updateOwner, repo: updateRepository, branch: 'master');

  /// Runs at startup; a failure leaves [version] at 0.0.0 rather than
  /// stopping the app.
  static Future<void> initPackageInfo() async {
    try {
      _packageInfo = await PackageInfo.fromPlatform();
    } catch (_) {
      // Keep the 0.0.0 fallback.
    }
  }

  static String get version {
    if (_packageInfo == null) return '0.0.0';
    return _packageInfo!.version;
  }

  /// The installed build number, 0 when unknown.
  static int get buildNumber => int.tryParse(_packageInfo?.buildNumber ?? '') ?? 0;
}
