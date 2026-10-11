import 'dart:io';

import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/platform/windows_multi_instance_launcher.dart';

class MenuButton extends StatelessWidget {
  const MenuButton({super.key, this.railActions = false, this.showRecord = true});

  /// Wide-layout navigation rail mode: the menu also holds 多画面 / 链接解析 /
  /// 全平台搜索 / 录制中心, and leaves out 设置, which the rail shows at its
  /// bottom edge.
  final bool railActions;

  /// Whether 录制中心 is offered in [railActions] mode.
  final bool showRecord;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: i18n('menu'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      offset: const Offset(12, 0),
      position: PopupMenuPosition.under,
      child: const SizedBox.square(dimension: kMinInteractiveDimension, child: Icon(Icons.menu_rounded)),
      onSelected: (String action) async {
        switch (action) {
          case 'multiview':
            await AppNavigator.toMultiview();
          case 'toolbox':
            Get.toNamed(RoutePath.kToolbox);
          case 'search':
            Get.toNamed(RoutePath.kSearch);
          case 'record':
            Get.toNamed(RoutePath.kRecordPage);
          case 'settings':
            Get.toNamed(RoutePath.kSettings);
          case 'about':
            Get.toNamed(RoutePath.kAbout);
          case 'history':
            Get.toNamed(RoutePath.kHistory);
          case 'backup':
            Get.toNamed(RoutePath.kBackup);
          case 'new_window':
            try {
              await WindowsMultiInstanceLauncher.launch();
            } catch (_) {
              ToastUtil.show(i18n('open_new_window_failed'));
            }
        }
      },
      itemBuilder: (context) {
        PopupMenuItem<String> item(String value, IconData icon, String text) => PopupMenuItem<String>(
          value: value,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: MenuListTile(leading: Icon(icon), text: text),
        );
        return [
          if (railActions) ...[
            if (SettingsService.to.app.enableMultiView.v)
              item('multiview', Remix.layout_grid_line, i18n('multiview_title')),
            item('toolbox', Remix.link, i18n('toolbox_title')),
            item('search', CustomIcons.search, i18n('search_all_platforms')),
            if (showRecord) item('record', Remix.download_2_line, i18n('record_center')),
            const PopupMenuDivider(),
          ] else
            item('settings', Remix.settings_5_line, i18n('settings_title')),
          item('about', Remix.information_line, i18n('about')),
          item('history', Remix.history_line, i18n('history')),
          item('backup', Remix.database_2_line, i18n('data_and_backup')),
          if (Platform.isWindows && SettingsService.to.app.enableNewWindowPlay.v)
            item('new_window', Icons.add_to_photos_outlined, i18n('open_new_window')),
        ];
      },
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
