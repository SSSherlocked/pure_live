import 'dart:async';
import 'dart:io';

import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/platform/windows_multi_instance_launcher.dart';
import 'package:pure_live/core/player/presentation/left_submenu_button.dart';

/// The panel style of the home page's two menus.
const MenuStyle homeMenuStyle = MenuStyle(
  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: kFloatingMenuVerticalPadding)),
);

/// Entries of the home and room-page menus: body-size text with room on
/// either side and 36 px rows, so they do not read as crowded.
const ButtonStyle homeMenuItemStyle = ButtonStyle(
  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
  // 4 px taller than the player's menus.
  minimumSize: WidgetStatePropertyAll(Size(64, kFloatingMenuItemHeight + 4)),
);

/// The label style of a home menu entry.
TextStyle homeMenuTextStyle(BuildContext context) => AppText.of(context).body.copyWith(fontWeight: FontWeight.w600);

/// The icon of a home menu entry.
Widget homeMenuIcon(BuildContext context, IconData icon, {Color? color}) =>
    Icon(icon, size: 18, color: color ?? Theme.of(context).colorScheme.primary);

/// One entry of the home page's two menus: a primary-coloured icon and its
/// name, shared by [MenuButton], [CommonAppBarActions] and the room page's
/// menu. A submenu entry's arrow hangs in the left padding, so plain entries
/// need no slot for it.
Widget homeMenuItem(
  BuildContext context, {
  Key? key,
  required IconData icon,
  required String text,
  required VoidCallback onPressed,
  Color? iconColor,
}) {
  final leading = homeMenuIcon(context, icon, color: iconColor);
  return MenuItemButton(
    key: key,
    style: homeMenuItemStyle,
    leadingIcon: leading,
    onPressed: onPressed,
    child: Text(text, style: homeMenuTextStyle(context)),
  );
}

/// The button that opens a home menu: the size of an app-bar action
/// ([kMinInteractiveDimension] square, 24 px icon).
Widget homeMenuToggle(MenuController menu, {required IconData icon, required String tooltip, Key? key}) {
  return IconButton(
    key: key,
    tooltip: tooltip,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: kMinInteractiveDimension, height: kMinInteractiveDimension),
    icon: Icon(icon, size: 24),
    onPressed: () => menu.isOpen ? menu.close() : menu.open(),
  );
}

/// The home page's top-left menu: 链接访问, 多画面, 录制中心, 新建独立播放窗口
/// (Windows) and, last, 设置. Searching and browsing are in the top-right
/// menu ([CommonAppBarActions]).
class MenuButton extends StatelessWidget {
  const MenuButton({super.key});

  Future<void> _openNewWindow() async {
    try {
      await WindowsMultiInstanceLauncher.launch();
    } catch (_) {
      ToastUtil.show(i18n('open_new_window_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      style: homeMenuStyle,
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        homeMenuItem(
          context,
          icon: Remix.link,
          text: i18n('open_link'),
          onPressed: () => Get.toNamed(RoutePath.kToolbox),
        ),
        if (SettingsService.to.app.enableMultiView.v)
          homeMenuItem(
            context,
            icon: Remix.layout_grid_line,
            text: i18n('multiview_title'),
            onPressed: () => unawaited(AppNavigator.toMultiview()),
          ),
        homeMenuItem(
          context,
          icon: Remix.download_2_line,
          text: i18n('record_center'),
          onPressed: () => Get.toNamed(RoutePath.kRecordPage),
        ),
        if (Platform.isWindows && SettingsService.to.app.enableNewWindowPlay.v)
          homeMenuItem(
            context,
            icon: Icons.add_to_photos_outlined,
            text: i18n('open_new_window'),
            onPressed: () => unawaited(_openNewWindow()),
          ),
        const Divider(height: 16),
        homeMenuItem(
          context,
          icon: Remix.settings_5_line,
          text: i18n('settings_title'),
          onPressed: () => Get.toNamed(RoutePath.kSettings),
        ),
      ],
      builder: (context, menu, _) =>
          homeMenuToggle(menu, key: const ValueKey('home-menu'), icon: Icons.menu_rounded, tooltip: i18n('menu')),
    );
  }
}
