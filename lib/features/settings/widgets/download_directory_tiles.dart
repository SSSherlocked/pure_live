import 'dart:io';

import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/platform/file_utils.dart';
import 'package:pure_live/core/config/cache_controller.dart';

/// 下载目录, where downloaded font bundles are kept, and its reset entry.
class DownloadDirectoryTiles extends StatelessWidget {
  const DownloadDirectoryTiles({super.key});

  static void _showMessage(String message, {bool failed = false}) {
    Get.snackbar(failed ? i18n('error') : i18n('done'), message, snackPosition: SnackPosition.bottom);
  }

  Future<void> _pick() async {
    try {
      final selected = await FileUtils.pickDirectory();
      if (selected == null || selected.trim().isEmpty) return;

      await SettingsService.to.cache.setDownloadDirectory(selected);

      // An app-sandbox default never needs this; a user-selected public folder
      // may still lack the Android "All files access" grant.
      if (!await CacheController.isCustomDownloadDirectoryUsable()) {
        await FileUtils.requestStoragePermission();
      }
      if (!await CacheController.isCustomDownloadDirectoryUsable()) {
        _showMessage(i18n('download_directory_permission_hint'), failed: true);
        if (Platform.isAndroid) openAppSettings();
        return;
      }

      _showMessage(i18n('download_directory_updated'));
    } catch (_) {
      _showMessage(i18n('download_directory_pick_failed'), failed: true);
    }
  }

  Future<void> _reset() async {
    try {
      await SettingsService.to.cache.useDefaultDownloadDirectory();
      _showMessage(i18n('download_directory_updated'));
    } catch (_) {
      _showMessage(i18n('download_directory_pick_failed'), failed: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final customDirectory = SettingsService.to.cache.downloadDirectory.value.trim();
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          context.buildTile(
            icon: Remix.folder_2_line,
            title: i18n('download_directory'),
            subtitle: customDirectory.isEmpty ? i18n('download_directory_default_label') : customDirectory,
            isLong: true,
            onTap: _pick,
          ),
          if (customDirectory.isNotEmpty)
            context.buildTile(icon: Remix.refresh_line, title: i18n('download_directory_reset'), onTap: _reset),
        ],
      );
    });
  }
}
