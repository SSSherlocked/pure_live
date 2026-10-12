import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/platform/platform_utils.dart';
import 'package:pure_live/core/network/douyu_utils.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pure_live/domains/account/presentation/account/douyu/douyu_web_login_controller.dart';

/// Douyu sign-in in a WebView; see [DouyuWebLoginController] for what counts as
/// signed in.
class DouyuWebLoginPage extends GetView<DouyuWebLoginController> {
  const DouyuWebLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compactAction = MediaQuery.sizeOf(context).width < 520 || MediaQuery.textScalerOf(context).scale(14) > 20;

    return Scaffold(
      appBar: AppBar(
        title: Text(i18n('douyu_web_login')),
        actions: [
          // A sign-in that does not navigate anywhere afterwards (some flows
          // only refresh the page) still has a way to finish.
          Obx(() {
            final busy = controller.isVerifying.value;
            if (compactAction) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton(
                  key: const ValueKey('douyu-web-login-check'),
                  onPressed: busy ? null : controller.checkNow,
                  tooltip: i18n('douyu_web_login_check'),
                  icon: const Icon(Remix.checkbox_circle_line),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                key: const ValueKey('douyu-web-login-check'),
                onPressed: busy ? null : controller.checkNow,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                  textStyle: const TextStyle(fontWeight: FontWeight.w600),
                ),
                icon: const Icon(Remix.checkbox_circle_line, size: 16),
                label: Text(i18n('douyu_web_login_check')),
              ),
            );
          }),
        ],
      ),
      body: Obx(() {
        return Stack(
          fit: StackFit.expand,
          children: [
            if (controller.showWebView.value)
              InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(douyuWebLoginUrl)),
                onWebViewCreated: controller.onWebViewCreated,
                onLoadStop: controller.onLoadStop,
                onUpdateVisitedHistory: controller.onUpdateVisitedHistory,
                // Phones keep the WebView's own (mobile) identity: Douyu then
                // serves its H5 sign-in with SMS and password login. Forcing a
                // desktop identity got the desktop page, which defaults to QR
                // and squeezes its other tabs off a phone screen. Desktop keeps
                // the identity its renewal requests present.
                initialSettings: InAppWebViewSettings(userAgent: PlatformUtils.isMobile ? null : DouyuUtils.userAgent),
              )
            else
              const ColoredBox(color: Colors.transparent),
            if (controller.isVerifying.value)
              _buildProgressState(
                context,
                message: i18n('douyu_web_login_verifying'),
                backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.94),
              ),
            if (!controller.isVerifying.value && controller.errorMessageKey.value.isNotEmpty)
              _buildErrorBanner(theme, i18n(controller.errorMessageKey.value))
            else if (!controller.isVerifying.value && controller.infoMessageKey.value.isNotEmpty)
              _buildInfoBanner(theme, i18n(controller.infoMessageKey.value)),
          ],
        );
      }),
    );
  }

  Widget _buildProgressState(BuildContext context, {required String message, Color? backgroundColor}) {
    return ColoredBox(
      key: const ValueKey('douyu-web-login-verifying'),
      color: backgroundColor ?? Colors.transparent,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(height: 20),
              Text(message, textAlign: TextAlign.center, style: AppText.of(context).listPrimary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoBanner(ThemeData theme, String message) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Material(
            key: const ValueKey('douyu-web-login-info'),
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(16),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.onSecondaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      message,
                      style: AppText.from(theme).body.copyWith(color: theme.colorScheme.onSecondaryContainer, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(ThemeData theme, String message) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Material(
            key: const ValueKey('douyu-web-login-error'),
            color: theme.colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(16),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(Remix.error_warning_line, color: theme.colorScheme.onErrorContainer, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message,
                      style: AppText.from(theme).body.copyWith(color: theme.colorScheme.onErrorContainer, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
