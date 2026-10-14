import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:markdown_widget/widget/all.dart';
import 'package:markdown_widget/config/configs.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/network/race_http.dart';
import 'package:pure_live/core/models/release_model.dart';
import 'package:pure_live/core/platform/file_utils.dart';
import 'package:pure_live/features/about/widgets/release_history_repository.dart';

/// A newer release for this platform, from master's assets/version.json and
/// its files from assets/releases.json.
class AppUpdateInfo {
  const AppUpdateInfo({required this.version, required this.notes, required this.releasePage, this.asset});

  final String version;
  final String notes;

  /// The release's GitHub page, for a platform the app cannot install itself.
  final String releasePage;

  /// The file this device downloads; null when the release has none for it.
  final ReleaseFileModel? asset;
}

/// In-app update: one check at startup and 关于 › 检查更新, then a dialog
/// with the release notes and one download button with its progress.
abstract final class AppUpdate {
  static bool _startupChecked = false;
  static bool _dialogOpen = false;

  /// Once per launch, quietly: no toast when there is nothing new or the
  /// check fails.
  static Future<void> checkOnStartup() async {
    if (_startupChecked) return;
    _startupChecked = true;
    try {
      final info = await check();
      if (info != null) await _show(info);
    } catch (_) {
      // Offline or blocked: the user can still check from 关于.
    }
  }

  /// From 关于 › 检查更新: says when the app is current or the check failed.
  static Future<void> checkByUser() async {
    ToastUtil.show(i18n('update_checking'));
    final AppUpdateInfo? info;
    try {
      info = await check();
    } catch (_) {
      ToastUtil.show(i18n('update_check_failed'));
      return;
    }
    if (info == null) {
      ToastUtil.show(i18n('update_latest'));
      return;
    }
    await _show(info);
  }

  /// The newer release for this platform, or null when the app is current.
  /// Throws when the feed cannot be read.
  static Future<AppUpdateInfo?> check() async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final feed = await RaceHttp.fetchJson(
      [for (final url in VersionUtil.mirror.mirrors('assets/version.json')) '$url?ts=$stamp'],
      timeout: const Duration(seconds: 10),
    );
    if (feed == null) throw StateError('update feed unavailable');
    final entry = _platformEntry(feed);
    final version = _normalize(entry['version']?.toString() ?? '');
    final build = int.tryParse('${entry['build_number'] ?? ''}');
    if (version.isEmpty || !_isNewer(version, build)) return null;

    ReleaseFileModel? asset;
    try {
      final releases = await ReleaseHistoryRepository.instance.load(forceRefresh: true);
      final release = releases.where((r) => _normalize(r.version) == version).firstOrNull;
      if (release != null) asset = pickAsset(release.files);
    } catch (_) {
      // Without the file list the dialog offers the release page instead.
    }
    return AppUpdateInfo(
      version: version,
      notes: entry['version_desc']?.toString() ?? '',
      releasePage: entry['download_url']?.toString() ?? '${VersionUtil.projectUrl}/releases',
      asset: asset,
    );
  }

  static String get _platformKey {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    return 'linux';
  }

  /// A platform left out of the latest release keeps its own entry under
  /// `platforms`; every other platform reads the top level.
  static Map<String, dynamic> _platformEntry(Map<String, dynamic> feed) {
    final platforms = feed['platforms'];
    if (platforms is Map && platforms[_platformKey] is Map) {
      return Map<String, dynamic>.from(platforms[_platformKey] as Map);
    }
    return feed;
  }

  static String _normalize(String value) => value.trim().replaceFirst(RegExp(r'^[vV]'), '');

  static bool _isNewer(String version, int? build) {
    final installedBuild = VersionUtil.buildNumber;
    if (build != null && installedBuild > 0) return build > installedBuild;
    List<int> parts(String value) => value.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final latest = parts(version);
    final installed = parts(_normalize(VersionUtil.version));
    for (var i = 0; i < 3; i++) {
      final a = i < latest.length ? latest[i] : 0;
      final b = i < installed.length ? installed[i] : 0;
      if (a != b) return a > b;
    }
    return false;
  }

  /// This device's file among a release's: the APK on Android, the portable
  /// zip on Windows, the zip for this Mac's chip, the DEB on Linux. Names
  /// are matched loosely so older releases' names are found too.
  @visibleForTesting
  static ReleaseFileModel? pickAsset(List<ReleaseFileModel> files, {String? platform, bool? appleSilicon}) {
    bool has(ReleaseFileModel file, String key) => file.name.toLowerCase().contains(key);
    bool endsWith(ReleaseFileModel file, String extension) =>
        file.url.toLowerCase().endsWith(extension) || file.name.toLowerCase().endsWith(extension);
    ReleaseFileModel? first(bool Function(ReleaseFileModel file) test) =>
        files.where((file) => file.url.startsWith('https://') && test(file)).firstOrNull;

    switch (platform ?? _platformKey) {
      case 'android':
        return first((file) => has(file, 'android') && endsWith(file, '.apk'));
      case 'windows':
        return first((file) => has(file, 'windows') && endsWith(file, '.zip'));
      case 'macos':
        final arm = appleSilicon ?? Abi.current() == Abi.macosArm64;
        return first(
          (file) =>
              has(file, 'macos') &&
              endsWith(file, '.zip') &&
              (arm ? has(file, 'applesilicon') || has(file, 'arm64') : has(file, 'intel') || has(file, 'x64')),
        );
      case 'linux':
        return first((file) => has(file, 'linux') && endsWith(file, '.deb'));
      default:
        return null;
    }
  }

  static Future<void> _show(AppUpdateInfo info) async {
    final context = Get.context;
    if (context == null || _dialogOpen) return;
    _dialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _AppUpdateDialog(info: info),
      );
    } finally {
      _dialogOpen = false;
    }
  }
}

enum _UpdateStage { idle, downloading, done, failed }

class _AppUpdateDialog extends StatefulWidget {
  const _AppUpdateDialog({required this.info});

  final AppUpdateInfo info;

  @override
  State<_AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<_AppUpdateDialog> {
  _UpdateStage _stage = _UpdateStage.idle;
  int _received = 0;
  int _total = 0;
  CancelToken? _cancel;
  File? _file;

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  Future<Directory> _targetDirectory() async {
    final base = Platform.isAndroid ? await getTemporaryDirectory() : await getDownloadsDirectory();
    final dir = Directory('${(base ?? await getTemporaryDirectory()).path}${Platform.pathSeparator}PureLive');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Downloads from GitHub, falling through the proxies when a source fails;
  /// the user sees one progress bar either way.
  Future<void> _download() async {
    final asset = widget.info.asset;
    if (asset == null) return;
    setState(() {
      _stage = _UpdateStage.downloading;
      _received = 0;
      _total = 0;
    });
    final dir = await _targetDirectory();
    final name = Uri.parse(asset.url).pathSegments.last;
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    final partial = File('${file.path}.part');
    final cancel = _cancel = CancelToken();
    final dio = Dio(
      BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 30)),
    );
    try {
      for (final url in VersionUtil.mirror.downloadMirrors(asset.url)) {
        if (cancel.isCancelled || !mounted) return;
        try {
          await dio.download(
            url,
            partial.path,
            cancelToken: cancel,
            deleteOnError: true,
            onReceiveProgress: (received, total) {
              if (!mounted) return;
              setState(() {
                _received = received;
                _total = total;
              });
            },
          );
          if (await file.exists()) await file.delete();
          await partial.rename(file.path);
          if (!mounted) return;
          setState(() {
            _stage = _UpdateStage.done;
            _file = file;
          });
          await _openDownloaded();
          return;
        } on DioException catch (error) {
          if (CancelToken.isCancel(error)) return;
        } catch (_) {
          // Try the next source.
        }
      }
      if (mounted) setState(() => _stage = _UpdateStage.failed);
    } finally {
      dio.close();
    }
  }

  /// Android installs the APK; desktop shows the file in its folder.
  Future<void> _openDownloaded() async {
    final file = _file;
    if (file == null) return;
    if (Platform.isAndroid) {
      final result = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
      if (result.type != ResultType.done) ToastUtil.show(i18n('update_install_failed'));
      return;
    }
    await FileUtils.openFolder(file.parent.path);
  }

  Future<void> _openReleasePage() async {
    final opened = await launchUrl(Uri.parse(widget.info.releasePage), mode: LaunchMode.externalApplication);
    if (!opened) ToastUtil.show(i18n('external_browser_not_opened'));
  }

  String _megabytes(int bytes) => (bytes / 1024 / 1024).toStringAsFixed(1);

  String get _progressText {
    if (_total <= 0) return i18n('update_progress_unknown', args: {'received': _megabytes(_received)});
    return i18n(
      'update_progress',
      args: {
        'received': _megabytes(_received),
        'total': _megabytes(_total),
        'percent': '${(_received * 100 / _total).floor().clamp(0, 100)}',
      },
    );
  }

  List<Widget> _actions() {
    final close = TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('update_later')));
    switch (_stage) {
      case _UpdateStage.idle:
        final asset = widget.info.asset;
        return [
          close,
          FilledButton(
            key: const ValueKey('update-download'),
            onPressed: asset == null ? _openReleasePage : _download,
            child: Text(i18n(asset == null ? 'update_open_release' : 'update_download')),
          ),
        ];
      case _UpdateStage.downloading:
        return [
          TextButton(
            onPressed: () {
              _cancel?.cancel();
              Navigator.of(context).pop();
            },
            child: Text(i18n('cancel')),
          ),
        ];
      case _UpdateStage.done:
        return [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('close'))),
          FilledButton(
            onPressed: _openDownloaded,
            child: Text(i18n(Platform.isAndroid ? 'update_install' : 'update_open_folder')),
          ),
        ];
      case _UpdateStage.failed:
        return [close, FilledButton(onPressed: _download, child: Text(i18n('retry')))];
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);
    final markdown = theme.brightness == Brightness.dark ? MarkdownConfig.darkConfig : MarkdownConfig.defaultConfig;
    final status = switch (_stage) {
      _UpdateStage.idle => null,
      _UpdateStage.downloading => _progressText,
      _UpdateStage.done => i18n('update_downloaded'),
      _UpdateStage.failed => i18n('update_download_failed'),
    };
    return PopScope(
      // A download is cancelled with its own button, not by a stray back.
      canPop: _stage != _UpdateStage.downloading,
      child: AlertDialog(
        title: Text(i18n('update_available_title', args: {'version': widget.info.version})),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: MarkdownBlock(
                    data: widget.info.notes,
                    config: markdown.copy(
                      configs: [
                        PConfig(textStyle: text.body.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.5)),
                      ],
                    ),
                  ),
                ),
              ),
              if (_stage != _UpdateStage.idle) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  key: const ValueKey('update-progress'),
                  value: switch (_stage) {
                    _UpdateStage.downloading => _total > 0 ? _received / _total : null,
                    _UpdateStage.done => 1.0,
                    _ => 0.0,
                  },
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 8),
                Text(
                  status ?? '',
                  style: text.secondary.copyWith(
                    color: _stage == _UpdateStage.failed ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: _actions(),
      ),
    );
  }
}
