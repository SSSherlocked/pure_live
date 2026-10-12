import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/features/settings/pages/video_settings_page.dart';
import 'package:pure_live/features/settings/pages/local_config_preview_page.dart';
import 'package:pure_live/features/settings/pages/general_settings_page.dart';
import 'package:pure_live/features/settings/pages/platform_settings_page.dart';
import 'package:pure_live/features/settings/pages/cache_data_settings_page.dart';
import 'package:pure_live/features/settings/pages/network_proxy_settings_page.dart';

class SettingsPage extends GetView<SettingsService> {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final scaledActionFontSize = mediaQuery.textScaler.scale(14);
    final useCompactConfigAction = screenWidth < 520 || scaledActionFontSize > 18;
    final configPreviewLabel = i18n('config_preview');
    void openConfigPreview() => Get.to(() => LocalConfigPreviewPage());

    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: screenWidth > 640 ? 0 : null,
        title: Text(i18n('settings_title'), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (useCompactConfigAction)
            IconButton(
              key: const ValueKey('settings-config-preview-action'),
              tooltip: configPreviewLabel,
              onPressed: openConfigPreview,
              icon: const Icon(Remix.file_text_line, size: 20),
            )
          else
            TextButton.icon(
              key: const ValueKey('settings-config-preview-action'),
              onPressed: openConfigPreview,
              icon: const Icon(Remix.file_text_line, size: 18),
              label: Text(configPreviewLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SettingsContentWidth(child: ListView(
        physics: const PureLiveScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // One flat list: no group headings. Theme, background, navigation
          // and refresh live inside 通用; 播放器内核 inside 视频; 备份与恢复
          // inside 数据管理与备份.
          context.buildModernCard([
            context.buildTile(
              icon: Remix.settings_4_line,
              title: i18n("general"),
              subtitle: i18n("general_desc"),
              onTap: () => Get.to(() => const GeneralSettingsPage()),
            ),
            context.buildTile(
              icon: Remix.film_line,
              title: i18n("video"),
              subtitle: i18n("video_desc"),
              onTap: () => Get.to(() => const VideoSettingsPage()),
            ),
            context.buildTile(
              icon: Remix.tv_line,
              title: i18n("platform_settings"),
              subtitle: i18n("platform_settings_desc"),
              onTap: () => Get.to(() => const PlatformSettingsPage()),
            ),
            context.buildTile(
              icon: Remix.global_line,
              title: i18n("custom_network_proxy"),
              subtitle: i18n("custom_network_proxy_desc"),
              onTap: () => Get.to(() => const NetworkProxySettingsPage()),
            ),
            context.buildTile(
              icon: Remix.database_2_line,
              title: i18n("data_and_backup"),
              subtitle: i18n("data_and_backup_desc"),
              onTap: () => Get.to(() => const CacheDataSettingsPage()),
            ),
          ]),
          const SizedBox(height: 32),
        ],
      )),
    );
  }
}
