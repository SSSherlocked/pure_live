import 'dart:async';
import 'dart:ffi' show Abi;

import 'package:pure_live/core/index.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pure_live/core/release/release_asset_urls.dart';

typedef VersionUpdateChecker = Future<bool> Function();
typedef VersionPackageInfoLoader = Future<PackageInfo> Function();

class VersionController extends GetxController {
  VersionController({this.updateChecker, this.packageInfoLoader});

  final VersionUpdateChecker? updateChecker;
  final VersionPackageInfoLoader? packageInfoLoader;
  bool _checking = false;

  final hasNewVersion = false.obs;

  final androidArmeabiV7aUrl = ''.obs;
  final androidArm64Url = ''.obs;
  final androidX8664Url = ''.obs;

  final windowsSetupUrl = ''.obs;
  final windowsPortableUrl = ''.obs;

  final macosUrl = ''.obs;

  final linuxDebUrl = ''.obs;
  final linuxZipUrl = ''.obs;
  final linuxTarGzUrl = ''.obs;

  late PackageInfo packageInfo;

  final loading = true.obs;
  final error = false.obs;
  final updateLog = ''.obs;
  final downloadPending = false.obs;

  @override
  void onInit() {
    super.onInit();
    unawaited(checkNewVersion());
  }

  Future<void> getPackageInfo() async {
    packageInfo = await (packageInfoLoader?.call() ?? PackageInfo.fromPlatform());
  }

  Future<void> checkNewVersion() async {
    if (_checking) return;
    _checking = true;
    loading.value = true;
    error.value = false;
    _clearReleaseState();
    try {
      final updateSucceeded = await (updateChecker?.call() ?? VersionUtil().checkUpdate());
      if (!updateSucceeded) throw StateError('Update feed request failed');

      await getPackageInfo();

      final latestVersion = VersionUtil.latestVersion.trim();
      final newVersion = VersionUtil.isNewerVersion(latestVersion, packageInfo.version);

      hasNewVersion.value = newVersion;
      updateLog.value = VersionUtil.latestUpdateLog;

      final assetUrls = _resolveAssetUrls(VersionUtil.latestAssets);
      final androidAbis = VersionUtil.latestAndroidAbis;

      androidArmeabiV7aUrl.value = androidAbis.contains('armeabi-v7a') ? assetUrls['android-armeabi-v7a'] ?? '' : '';
      androidArm64Url.value = androidAbis.contains('arm64-v8a') ? assetUrls['android-arm64-v8a'] ?? '' : '';
      androidX8664Url.value = androidAbis.contains('x86_64') ? assetUrls['android-x86_64'] ?? '' : '';

      windowsSetupUrl.value = assetUrls['windows-x64-setup.exe'] ?? '';
      windowsPortableUrl.value = assetUrls['windows-x64-portable.zip'] ?? '';

      // Apple Silicon and Intel are separate packages; a running app is
      // native to its Mac (an Intel copy under Rosetta asks for Intel again).
      macosUrl.value = macosPackageFor(assetUrls, arm64: Abi.current() == Abi.macosArm64) ?? '';

      linuxDebUrl.value = assetUrls['linux-x64.deb'] ?? '';
      linuxZipUrl.value = assetUrls['linux-x64.zip'] ?? '';
      linuxTarGzUrl.value = assetUrls['linux-x64.tar.gz'] ?? '';
    } catch (_) {
      error.value = true;
      _clearReleaseState();
    } finally {
      loading.value = false;
      _checking = false;
    }
  }

  Map<String, String> _resolveAssetUrls(List<Map<String, dynamic>> assets) {
    final result = <String, String>{};
    for (final asset in assets) {
      final name = asset['name']?.toString().trim() ?? '';
      final url = asset['url']?.toString().trim() ?? '';
      if (name.isEmpty || url.isEmpty) continue;
      result[name] = url;
    }
    return result;
  }

  void _clearReleaseState() {
    hasNewVersion.value = false;
    updateLog.value = '';
    androidArmeabiV7aUrl.value = '';
    androidArm64Url.value = '';
    androidX8664Url.value = '';
    windowsSetupUrl.value = '';
    windowsPortableUrl.value = '';
    macosUrl.value = '';
    linuxDebUrl.value = '';
    linuxZipUrl.value = '';
    linuxTarGzUrl.value = '';
  }
}
