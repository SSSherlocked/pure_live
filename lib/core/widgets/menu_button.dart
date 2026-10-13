import 'dart:io';

import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/platform/windows_multi_instance_launcher.dart';

/// One entry of the home page's two menus: a primary-coloured icon and its
/// name, shared by [MenuButton] and [CommonAppBarActions].
PopupMenuItem<String> homeMenuItem(BuildContext context, String value, IconData icon, String text) {
  return PopupMenuItem<String>(
    value: value,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Text(text, style: AppText.of(context).listPrimary),
      ],
    ),
  );
}

/// The home page's top-left menu: 链接访问, 多画面, 录制中心, 新建独立播放窗口
/// (Windows) and, last, 设置. Searching and browsing are in the top-right
/// menu ([CommonAppBarActions]).
class MenuButton extends StatelessWidget {
  const MenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: const ValueKey('home-menu'),
      tooltip: i18n('menu'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      offset: const Offset(0, 10),
      position: PopupMenuPosition.under,
      onSelected: (String action) async {
        switch (action) {
          case 'toolbox':
            Get.toNamed(RoutePath.kToolbox);
          case 'multiview':
            await AppNavigator.toMultiview();
          case 'record':
            Get.toNamed(RoutePath.kRecordPage);
          case 'new_window':
            try {
              await WindowsMultiInstanceLauncher.launch();
            } catch (_) {
              ToastUtil.show(i18n('open_new_window_failed'));
            }
          case 'settings':
            Get.toNamed(RoutePath.kSettings);
        }
      },
      itemBuilder: (context) => [
        homeMenuItem(context, 'toolbox', Remix.link, i18n('open_link')),
        if (SettingsService.to.app.enableMultiView.v)
          homeMenuItem(context, 'multiview', Remix.layout_grid_line, i18n('multiview_title')),
        homeMenuItem(context, 'record', Remix.download_2_line, i18n('record_center')),
        if (Platform.isWindows && SettingsService.to.app.enableNewWindowPlay.v)
          homeMenuItem(context, 'new_window', Icons.add_to_photos_outlined, i18n('open_new_window')),
        const PopupMenuDivider(),
        homeMenuItem(context, 'settings', Remix.settings_5_line, i18n('settings_title')),
      ],
      child: const SizedBox.square(dimension: kMinInteractiveDimension, child: Icon(Icons.menu_rounded, size: 24)),
    );
  }
}

class MenuListTile extends StatelessWidget {
  final Widget? leading;
  final String text;
  final Widget? trailing;

  const MenuListTile({super.key, required this.leading, required this.text, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 12)],
        Text(text, style: Theme.of(context).textTheme.labelMedium),
        if (trailing != null) ...[const SizedBox(width: 24), trailing!],
      ],
    );
  }
}
