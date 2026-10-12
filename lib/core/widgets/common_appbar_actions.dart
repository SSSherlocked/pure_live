import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/consts/app_consts.dart';

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
                  Text(i18n("search_live"), style: AppTextStyles.t14),
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
                  Text(i18n("open_link"), style: AppTextStyles.t14),
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
                    Text(i18n("multiview_title"), style: AppTextStyles.t14),
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
                    Text(i18n("record_center"), style: AppTextStyles.t14),
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
}
