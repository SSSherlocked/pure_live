import 'dart:async';
import 'dart:io';

import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/consts/app_consts.dart';
import 'package:pure_live/core/platform/windows_multi_instance_launcher.dart';

class CommonAppBarActions extends StatelessWidget {
  const CommonAppBarActions({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<int>(
          tooltip: i18n("more"),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          offset: const Offset(0, 10),
          position: PopupMenuPosition.under,
          onSelected: (index) {
            switch (index) {
              case 0:
                Get.toNamed(RoutePath.kSearch);
                break;
              case 1:
                Get.toNamed(RoutePath.kToolbox);
                break;
              case 2:
                AppNavigator.toMultiview();
                break;
              case 3:
                Get.toNamed(RoutePath.kRecordPage);
                break;
              case 4:
                unawaited(_openNewWindow());
                break;
              case 5:
                Get.toNamed(RoutePath.kHistory);
                break;
            }
          },

          itemBuilder: (context) => [
            PopupMenuItem(
              value: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(Remix.search_line, size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(i18n("search_live"), style: AppText.of(context).listPrimary),
                ],
              ),
            ),

            PopupMenuItem(
              value: 1,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(Remix.link, size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(i18n("open_link"), style: AppText.of(context).listPrimary),
                ],
              ),
            ),
            if (SettingsService.to.app.enableMultiView.v)
              PopupMenuItem(
                value: 2,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Icon(Remix.layout_grid_line, size: 20, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    Text(i18n("multiview_title"), style: AppText.of(context).listPrimary),
                  ],
                ),
              ),
            // 录制中心 is never a bottom tab; while the navigation settings show
            // it, it is the last entry here (the desktop rail menu does the same).
            if (SettingsService.to.app.savedMenuIds.v.contains(HomeMenu.record.id))
              PopupMenuItem(
                value: 3,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Icon(Remix.download_2_line, size: 20, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    Text(i18n("record_center"), style: AppText.of(context).listPrimary),
                  ],
                ),
              ),
            if (Platform.isWindows && SettingsService.to.app.enableNewWindowPlay.v)
              PopupMenuItem(
                value: 4,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Icon(Icons.add_to_photos_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    Text(i18n("open_new_window"), style: AppText.of(context).listPrimary),
                  ],
                ),
              ),
            // Always last; the top-left gear no longer has a menu for it.
            PopupMenuItem(
              value: 5,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(Remix.history_line, size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(i18n("history"), style: AppText.of(context).listPrimary),
                ],
              ),
            ),
          ],
          child: const SizedBox.square(
            dimension: kMinInteractiveDimension,
            child: Icon(Remix.menu_search_line, size: 24),
          ),
        ),

        const SizedBox(width: 4),
      ],
    );
  }

  Future<void> _openNewWindow() async {
    try {
      await WindowsMultiInstanceLauncher.launch();
    } catch (_) {
      ToastUtil.show(i18n('open_new_window_failed'));
    }
  }
}
