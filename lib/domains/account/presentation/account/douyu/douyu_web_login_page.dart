import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';
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
                // The renewal request presents this same browser identity, so
                // the session is issued to it rather than to a mobile one.
                initialSettings: InAppWebViewSettings(userAgent: DouyuUtils.userAgent),
              )
            else
              const ColoredBox(color: Colors.transparent),
            if (controller.isVerifying.value)
              _buildProgressState(
                message: i18n('douyu_web_login_verifying'),
                backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.94),
              ),
            if (!controller.isVerifying.value && controller.errorMessageKey.value.isNotEmpty)
              _buildErrorBanner(theme, i18n(controller.errorMessageKey.value)),
          ],
        );
      }),
    );
  }

  Widget _buildProgressState({required String message, Color? backgroundColor}) {
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
              Text(message, textAlign: TextAlign.center, style: AppTextStyles.t14),
            ],
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
                      style: AppTextStyles.t13.copyWith(color: theme.colorScheme.onErrorContainer, height: 1.35),
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
