import 'dart:async';

import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/domains/account/presentation/account/account_controller.dart';
import 'package:pure_live/domains/account/presentation/account/account_status.dart';
import 'package:pure_live/domains/account/data/bilibili_account_service.dart';

class AccountPage extends GetView<AccountController> {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cookie = controller.cookie;

    return Scaffold(
      appBar: AppBar(title: Text(i18n('third_party_auth'))),
      body: ListView(
        physics: const PureLiveScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          context.buildGroupTitle(i18n('third_party_auth')),
          context.buildModernCard([
            for (final platform in AccountPlatform.values)
              Obx(() {
                final status = AccountStatus.of(platform, douyinNickName: controller.douyinNickName.value);
                return _buildAccountTile(
                  context,
                  logo: platform.logo,
                  title: platform.title,
                  subtitle: status.detail,
                  isLogined: status.isSignedIn,
                  onTap: () => status.isSignedIn
                      ? _showLogoutDialog(context, accountName: platform.title, onConfirm: () => _signOut(platform))
                      : _signIn(platform),
                );
              }),
          ]),
          const SizedBox(height: 12),
          Obx(() {
            final enabled = cookie.hasAnyCredential;
            final theme = Theme.of(context);
            return context.buildModernCard([
              ListTile(
                enabled: enabled,
                leading: Icon(
                  Remix.delete_bin_2_line,
                  size: 20,
                  color: enabled ? theme.colorScheme.error.withValues(alpha: 0.85) : theme.disabledColor,
                ),
                title: Text(
                  i18n('clear_all_accounts'),
                  style: AppTextStyles.t15.copyWith(
                    fontWeight: FontWeight.w600,
                    color: enabled ? theme.colorScheme.error : theme.disabledColor,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    i18n('clear_all_accounts_desc'),
                    style: AppTextStyles.t12.copyWith(color: theme.hintColor.withValues(alpha: 0.75)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                onTap: enabled ? () => _showClearAllDialog(context) : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              ),
            ]);
          }),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// Where a signed-out tile leads. Douyu's leads to its web login (the manual
  /// cookie page is a choice there); a Douyu cookie that no longer holds a
  /// session is replaced, not signed out of.
  void _signIn(AccountPlatform platform) {
    switch (platform) {
      case AccountPlatform.bilibili:
        controller.bilibiliTap();
      case AccountPlatform.douyu:
        AppNavigator.toDouyuLogin();
      case AccountPlatform.huya:
        Get.toNamed(RoutePath.kHuyaCookie);
      case AccountPlatform.yy:
        Get.toNamed(RoutePath.kYyCookie);
      case AccountPlatform.bigo:
        Get.toNamed(RoutePath.kBigoCookie);
      case AccountPlatform.douyin:
        Get.toNamed(RoutePath.kDouyinCookie);
      case AccountPlatform.kuaishou:
        Get.toNamed(RoutePath.kKuaishouCookie);
      case AccountPlatform.twitch:
        Get.toNamed(RoutePath.kTwitchCookie);
      case AccountPlatform.soop:
        Get.toNamed(RoutePath.kSoop);
    }
  }

  FutureOr<void> _signOut(AccountPlatform platform) {
    final cookie = controller.cookie;
    switch (platform) {
      case AccountPlatform.bilibili:
        return BiliBiliAccountService.instance.logout();
      case AccountPlatform.douyu:
        cookie.clearDouyuSession();
      case AccountPlatform.huya:
        cookie.huyaCookie.v = '';
      case AccountPlatform.yy:
        cookie.yyCookie.v = '';
      case AccountPlatform.bigo:
        cookie.bigoCookie.v = '';
      case AccountPlatform.douyin:
        cookie.douyinCookie.v = '';
      case AccountPlatform.kuaishou:
        cookie.kuaishouCookie.v = '';
      case AccountPlatform.twitch:
        cookie.twitchCookie.v = '';
      case AccountPlatform.soop:
        cookie.soopCookie.v = '';
    }
  }

  Widget _buildAccountTile(
    BuildContext context, {
    required String logo,
    required String title,
    required String subtitle,
    required bool isLogined,
    VoidCallback? onTap,
    bool isEnabled = true,
  }) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final expandedText = constraints.maxWidth < 360 || MediaQuery.textScalerOf(context).scale(1) > 1.5;
        return ListTile(
          enabled: isEnabled,
          leading: Image.asset(logo, width: 24, height: 24),
          title: Text(
            title,
            style: AppTextStyles.t15.copyWith(
              fontWeight: FontWeight.w600,
              color: isEnabled ? null : theme.disabledColor,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle,
              style: AppTextStyles.t12.copyWith(
                color: isLogined ? theme.colorScheme.primary : theme.hintColor.withValues(alpha: 0.75),
                fontWeight: isLogined ? FontWeight.w500 : FontWeight.normal,
              ),
              maxLines: expandedText ? 2 : 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          trailing: !isEnabled
              ? null
              : isLogined
              ? IconButton(
                  tooltip: i18n('logout'),
                  visualDensity: VisualDensity.standard,
                  constraints: const BoxConstraints(
                    minWidth: kMinInteractiveDimension,
                    minHeight: kMinInteractiveDimension,
                  ),
                  onPressed: onTap,
                  icon: Icon(Remix.logout_box_r_line, color: theme.colorScheme.error.withValues(alpha: 0.8), size: 18),
                )
              : Icon(Icons.chevron_right_rounded, color: theme.hintColor.withValues(alpha: 0.4), size: 20),
          onTap: isEnabled ? onTap : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        );
      },
    );
  }

  void _showLogoutDialog(
    BuildContext context, {
    required String accountName,
    required FutureOr<void> Function() onConfirm,
  }) {
    unawaited(
      controller.runLogoutTransaction(() async {
        if (!context.mounted) return;
        final confirmed = await _confirmDangerDialog(
          context,
          title: i18n('logout'),
          message: i18n('confirm_logout_named', args: {'name': accountName}),
          confirmLabel: i18n('logout'),
        );
        if (!confirmed || !context.mounted) return;
        await onConfirm();
      }),
    );
  }

  void _showClearAllDialog(BuildContext context) {
    unawaited(
      controller.runLogoutTransaction(() async {
        if (!context.mounted) return;
        final confirmed = await _confirmDangerDialog(
          context,
          title: i18n('clear_all_accounts'),
          message: i18n('confirm_clear_all_accounts'),
          confirmLabel: i18n('clear'),
        );
        if (!confirmed || !context.mounted) return;
        await BiliBiliAccountService.instance.logout();
        controller.cookie.clearAllCookies();
        ToastUtil.show(i18n('clear_all_accounts_done'));
      }),
    );
  }

  Future<bool> _confirmDangerDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        title: Text(title),
        content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Text(message)),
        actionsOverflowDirection: VerticalDirection.down,
        actionsOverflowButtonSpacing: 8,
        actions: [
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => Navigator.of(dialogContext, rootNavigator: true).pop(false),
            child: Text(i18n('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext, rootNavigator: true).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed == true;
  }
}
