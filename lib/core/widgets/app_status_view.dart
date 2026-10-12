import 'package:flutter/material.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/core/utils/i18n.dart';
import 'package:pure_live/core/theme/app_text_styles.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

enum AppStatusType { loading, empty, error }

class AppStatusView extends StatefulWidget {
  final AppStatusType type;
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final String? buttonText;
  final VoidCallback? onButtonPressed;
  final bool isMini;
  final Color? iconColor;
  final Color? titleColor;
  final Color? subtitleColor;

  const AppStatusView({
    super.key,
    required this.type,
    this.title,
    this.subtitle,
    this.icon,
    this.buttonText,
    this.onButtonPressed,
    this.isMini = false,
    this.iconColor,
    this.titleColor,
    this.subtitleColor,
  });

  @override
  State<AppStatusView> createState() => _AppStatusViewState();
}

class _AppStatusViewState extends State<AppStatusView> {
  /// The app's one loading animation (三重连环).
  Widget _buildLoadingWidget(Color color) {
    final double size = widget.isMini
        ? 24
        : Get.width > 680
        ? 32
        : 24;
    return LoadingAnimationWidget.threeArchedCircle(color: color, size: size);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveIconColor = widget.iconColor ?? theme.colorScheme.primary;

    if (widget.type == AppStatusType.loading) {
      return Center(child: _buildLoadingWidget(effectiveIconColor));
    }

    final String finalTitle =
        widget.title ?? (widget.type == AppStatusType.error ? i18n('status_error_title') : i18n('status_empty_title'));
    final String finalSubtitle =
        widget.subtitle ??
        (widget.type == AppStatusType.error ? i18n('status_error_subtitle') : i18n('status_empty_subtitle'));
    final String finalButtonText = widget.buttonText ?? i18n('status_retry_button');

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 1000),
            curve: Curves.elasticOut,
            builder: (context, value, child) {
              return Transform.scale(scale: value, child: child);
            },
            child: Container(
              padding: EdgeInsets.all(widget.isMini ? 8 : 22),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: effectiveIconColor.withValues(alpha: 0.05), width: 1),
              ),
              child: Icon(
                widget.icon ?? (widget.type == AppStatusType.error ? Icons.wifi_off_rounded : Icons.live_tv_rounded),
                size: widget.isMini ? 16 : 42,
                color: widget.iconColor ?? theme.colorScheme.primary.withValues(alpha: 0.6),
              ),
            ),
          ),
          if (!widget.isMini || finalTitle.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              finalTitle,
              style: AppTextStyles.t15.copyWith(
                fontWeight: FontWeight.w600,
                color: widget.titleColor ?? theme.textTheme.titleMedium?.color,
              ),
            ),
          ],
          if (!widget.isMini || finalSubtitle.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 6, 28, 0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  finalSubtitle,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.t13.copyWith(color: widget.subtitleColor ?? theme.hintColor, height: 1.5),
                ),
              ),
            ),
          ],
          if (!widget.isMini && widget.onButtonPressed != null) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: widget.onButtonPressed,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(finalButtonText),
            ),
          ],
        ],
      ),
    );
  }
}
