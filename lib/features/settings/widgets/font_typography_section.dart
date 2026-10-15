import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/utils/setting_value_format.dart';
import 'package:pure_live/core/config/font_settings_controller.dart';

/// The five typography sliders (body and heading sizes) with their reset,
/// listed inline in 通用 › 字体设置.
class FontTypographySection extends StatefulWidget {
  const FontTypographySection({super.key});

  @override
  State<FontTypographySection> createState() => _FontTypographySectionState();
}

class _FontTypographySectionState extends State<FontTypographySection> {
  bool _resetBusy = false;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Column(
        key: const ValueKey('font-settings-content'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: context.buildGroupTitle(i18n("body_typography_group"))),
              TextButton.icon(
                key: const ValueKey('font-settings-reset'),
                onPressed: _resetBusy ? null : _resetToDefaults,
                icon: const Icon(Remix.rest_time_line, size: 16),
                label: Text(i18n("reset")),
              ),
            ],
          ),
          context.buildModernCard([
            context.buildSliderTile(
              context,
              icon: Remix.font_size,
              title: i18n("font_body_small_title"),
              subtitle: i18n("font_body_small_desc"),
              value: SettingsService.to.font.fontSizeBodySmall.v,
              min: FontSettingsController.minFontSizeBodySmall,
              max: FontSettingsController.maxFontSizeBodySmall,
              displayValue: formatPixels(SettingsService.to.font.fontSizeBodySmall.v.round()),
              onChanged: (newValue) {
                SettingsService.to.font.fontSizeBodySmall.v = newValue;
              },
            ),
            context.buildSliderTile(
              context,
              icon: Remix.text,
              title: i18n("font_body_medium_title"),
              subtitle: i18n("font_body_medium_desc"),
              value: SettingsService.to.font.fontSizeBodyMedium.v,
              min: FontSettingsController.minFontSizeBodyMedium,
              max: FontSettingsController.maxFontSizeBodyMedium,
              displayValue: formatPixels(SettingsService.to.font.fontSizeBodyMedium.v.round()),
              onChanged: (newValue) {
                SettingsService.to.font.fontSizeBodyMedium.v = newValue;
              },
            ),
            context.buildSliderTile(
              context,
              icon: Remix.text_wrap,
              title: i18n("font_body_large_title"),
              subtitle: i18n("font_body_large_desc"),
              value: SettingsService.to.font.fontSizeBodyLarge.v,
              min: FontSettingsController.minFontSizeBodyLarge,
              max: FontSettingsController.maxFontSizeBodyLarge,
              displayValue: formatPixels(SettingsService.to.font.fontSizeBodyLarge.v.round()),
              onChanged: (newValue) {
                SettingsService.to.font.fontSizeBodyLarge.v = newValue;
              },
            ),
          ]),
          const SizedBox(height: 20),
          context.buildGroupTitle(i18n("header_typography_group")),
          context.buildModernCard([
            context.buildSliderTile(
              context,
              icon: Remix.heading,
              title: i18n("font_title_medium_title"),
              subtitle: i18n("font_title_medium_desc"),
              value: SettingsService.to.font.fontSizeTitleMedium.v,
              min: FontSettingsController.minFontSizeTitleMedium,
              max: FontSettingsController.maxFontSizeTitleMedium,
              displayValue: formatPixels(SettingsService.to.font.fontSizeTitleMedium.v.round()),
              onChanged: (newValue) {
                SettingsService.to.font.fontSizeTitleMedium.v = newValue;
              },
            ),
            context.buildSliderTile(
              context,
              icon: Remix.bold,
              title: i18n("font_title_large_title"),
              subtitle: i18n("font_title_large_desc"),
              value: SettingsService.to.font.fontSizeTitleLarge.v,
              min: FontSettingsController.minFontSizeTitleLarge,
              max: FontSettingsController.maxFontSizeTitleLarge,
              displayValue: formatPixels(SettingsService.to.font.fontSizeTitleLarge.v.round()),
              onChanged: (newValue) {
                SettingsService.to.font.fontSizeTitleLarge.v = newValue;
              },
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _resetToDefaults() async {
    if (_resetBusy || !mounted) return;
    final font = SettingsService.to.font;
    setState(() => _resetBusy = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
          key: const ValueKey('font-settings-reset-dialog'),
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          title: Text(i18n('reset'), style: AppText.of(context).sectionTitle),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(i18n('font_settings_reset_confirm'), style: AppText.of(context).listPrimary),
          ),
          actionsOverflowDirection: VerticalDirection.down,
          actionsOverflowButtonSpacing: 8,
          actions: [
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => Navigator.of(dialogContext, rootNavigator: true).pop(false),
              child: Text(i18n('cancel'), style: AppText.of(context).listPrimary.copyWith(color: Theme.of(context).hintColor)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(48, 48),
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext, rootNavigator: true).pop(true),
              child: Text(i18n('reset')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || font.isClosed) return;
      font.resetTypography();
      ToastUtil.show(i18n('restore_default'));
    } finally {
      if (mounted) setState(() => _resetBusy = false);
    }
  }
}
