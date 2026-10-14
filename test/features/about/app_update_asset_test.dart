import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/models/release_model.dart';
import 'package:pure_live/features/about/app_update.dart';

ReleaseFileModel _file(String name, String fileName) => ReleaseFileModel(
  name: name,
  size: '',
  downloads: 0,
  url: 'https://github.com/SSSherlocked/pure_live/releases/download/v3.3.3/$fileName',
);

void main() {
  // releases.json drops ".apk" from an APK's name; the URL keeps it.
  final current = [
    _file('PureLive-3.3.3-Android-arm64-v8a', 'PureLive-3.3.3-Android-arm64-v8a.apk'),
    _file('PureLive-3.3.3-Windows-x64.zip', 'PureLive-3.3.3-Windows-x64.zip'),
    _file('PureLive-3.3.3-Linux-x64.deb', 'PureLive-3.3.3-Linux-x64.deb'),
    _file('PureLive-3.3.3-Linux-x64.tar.gz', 'PureLive-3.3.3-Linux-x64.tar.gz'),
    _file('PureLive-3.3.3-MacOS-AppleSilicon.zip', 'PureLive-3.3.3-MacOS-AppleSilicon.zip'),
    _file('PureLive-3.3.3-MacOS-Intel.zip', 'PureLive-3.3.3-MacOS-Intel.zip'),
    _file('PureLive-3.3.3-iOS-TrollStore.ipa', 'PureLive-3.3.3-iOS-TrollStore.ipa'),
  ];

  String? pick(List<ReleaseFileModel> files, String platform, {bool appleSilicon = true}) =>
      AppUpdate.pickAsset(files, platform: platform, appleSilicon: appleSilicon)?.name;

  test('each platform gets its own file', () {
    expect(pick(current, 'android'), 'PureLive-3.3.3-Android-arm64-v8a');
    expect(pick(current, 'windows'), 'PureLive-3.3.3-Windows-x64.zip');
    expect(pick(current, 'linux'), 'PureLive-3.3.3-Linux-x64.deb');
    expect(pick(current, 'macos'), 'PureLive-3.3.3-MacOS-AppleSilicon.zip');
    expect(pick(current, 'macos', appleSilicon: false), 'PureLive-3.3.3-MacOS-Intel.zip');
  });

  test('iOS has no in-app download', () {
    expect(pick(current, 'ios'), isNull);
  });

  test('older release names are found too', () {
    final older = [
      _file('PureLive-3.3.1-4116-android-arm64-v8a', 'PureLive-3.3.1-4116-android-arm64-v8a-release.apk'),
      _file('PureLive-3.3.1-4116-windows-x64-setup.exe', 'PureLive-3.3.1-4116-windows-x64-setup.exe'),
      _file('PureLive-3.3.1-4116-windows-x64-portable.zip', 'PureLive-3.3.1-4116-windows-x64-portable.zip'),
      _file('PureLive-3.3.1-4116-macos-arm64.zip', 'PureLive-3.3.1-4116-macos-arm64.zip'),
      _file('PureLive-3.3.1-4116-macos-x64.zip', 'PureLive-3.3.1-4116-macos-x64.zip'),
    ];
    expect(pick(older, 'android'), 'PureLive-3.3.1-4116-android-arm64-v8a');
    expect(pick(older, 'windows'), 'PureLive-3.3.1-4116-windows-x64-portable.zip');
    expect(pick(older, 'macos'), 'PureLive-3.3.1-4116-macos-arm64.zip');
    expect(pick(older, 'macos', appleSilicon: false), 'PureLive-3.3.1-4116-macos-x64.zip');
  });

  test('a release without a file for the platform offers none', () {
    expect(pick(current.where((file) => !file.name.contains('Android')).toList(), 'android'), isNull);
  });
}
