import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/features/settings/pages/video_settings_page.dart';
import 'package:pure_live/features/settings/pages/local_config_preview_page.dart';
import 'package:pure_live/features/settings/pages/general_settings_page.dart';
import 'package:pure_live/features/settings/pages/platform_settings_page.dart';
import 'package:pure_live/features/settings/pages/cache_data_settings_page.dart';

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
          // One flat list: no group headings. Theme, the home menu, refresh and
          // the network proxy live inside 通用; 播放器内核 inside 视频; 备份与恢复
          // inside 数据管理与备份.
          _EntryList([
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
            // The 录制中心 page's own settings page and controller.
            context.buildTile(
              icon: Remix.record_circle_line,
              title: i18n("record_settings"),
              subtitle: i18n("record_settings_desc"),
              onTap: () => Get.toNamed(RoutePath.kRecordSettings),
            ),
            context.buildTile(
              icon: Remix.database_2_line,
              title: i18n("data_and_backup"),
              subtitle: i18n("data_and_backup_desc"),
              onTap: () => Get.to(() => const CacheDataSettingsPage()),
            ),
            context.buildTile(
              icon: Remix.information_line,
              title: i18n("about"),
              subtitle: i18n("about_desc"),
              onTap: () => Get.toNamed(RoutePath.kAbout),
            ),
          ]),
          const SizedBox(height: 32),
        ],
      )),
    );
  }
}

/// The settings entries on the page itself, without a card: rows in the
/// shared settings metrics, a hairline between two rows from the text's
/// start to the side padding.
class _EntryList extends StatelessWidget {
  const _EntryList(this.entries);

  final List<Widget> entries;

  @override
  Widget build(BuildContext context) {
    return ListTileTheme.merge(
      contentPadding: const EdgeInsets.symmetric(horizontal: kSettingsRowSidePadding),
      minVerticalPadding: kSettingsRowVerticalPadding,
      horizontalTitleGap: kSettingsIconGap,
      minLeadingWidth: kSettingsIconSlot,
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 0.5,
                thickness: 0.5,
                indent: kSettingsRowSidePadding + kSettingsIconSlot + kSettingsIconGap,
                endIndent: kSettingsRowSidePadding,
              ),
            entries[i],
          ],
        ],
      ),
    );
  }
}
