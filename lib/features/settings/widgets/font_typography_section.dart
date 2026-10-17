import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/utils/setting_value_format.dart';
import 'package:pure_live/core/config/font_settings_controller.dart';

/// The five typography sliders with their reset, listed inline in
/// 通用 › 字体设置. Each sets exactly one [AppText] role (the tag role follows
/// the secondary size) and previews that role under its slider.
class FontTypographySection extends StatefulWidget {
  const FontTypographySection({super.key});

  @override
  State<FontTypographySection> createState() => _FontTypographySectionState();
}

class _FontTypographySectionState extends State<FontTypographySection> {
  bool _resetBusy = false;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final font = SettingsService.to.font;
      final text = AppText.of(context);
      return Column(
        key: const ValueKey('font-settings-content'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: context.buildGroupTitle(i18n("header_typography_group"))),
              TextButton.icon(
                key: const ValueKey('font-settings-reset'),
                onPressed: _resetBusy ? null : _resetToDefaults,
                icon: const Icon(Remix.rest_time_line, size: 16),
                label: Text(i18n("reset")),
              ),
            ],
          ),
          context.buildModernCard([
            _sizeRow(
              icon: Remix.bold,
              title: i18n("font_title_large_title"),
              subtitle: i18n("font_title_large_desc"),
              setting: font.fontSizeTitleLarge,
              min: FontSettingsController.minFontSizeTitleLarge,
              max: FontSettingsController.maxFontSizeTitleLarge,
              preview: Text(i18n("font_title_large_preview"), style: text.pageTitle),
            ),
            _sizeRow(
              icon: Remix.heading,
              title: i18n("font_title_medium_title"),
              subtitle: i18n("font_title_medium_desc"),
              setting: font.fontSizeTitleMedium,
              min: FontSettingsController.minFontSizeTitleMedium,
              max: FontSettingsController.maxFontSizeTitleMedium,
              preview: Text(i18n("font_title_medium_preview"), style: text.sectionTitle),
            ),
          ]),
          const SizedBox(height: 20),
          context.buildGroupTitle(i18n("body_typography_group")),
          context.buildModernCard([
            _sizeRow(
              icon: Remix.text_wrap,
              title: i18n("font_body_large_title"),
              subtitle: i18n("font_body_large_desc"),
              setting: font.fontSizeBodyLarge,
              min: FontSettingsController.minFontSizeBodyLarge,
              max: FontSettingsController.maxFontSizeBodyLarge,
              preview: Text(i18n("font_body_large_preview"), style: text.listPrimary),
            ),
            _sizeRow(
              icon: Remix.text,
              title: i18n("font_body_medium_title"),
              subtitle: i18n("font_body_medium_desc"),
              setting: font.fontSizeBodyMedium,
              min: FontSettingsController.minFontSizeBodyMedium,
              max: FontSettingsController.maxFontSizeBodyMedium,
              preview: Text(i18n("font_body_medium_preview"), style: text.body),
            ),
            _sizeRow(
              icon: Remix.font_size,
              title: i18n("font_body_small_title"),
              subtitle: i18n("font_body_small_desc"),
              setting: font.fontSizeBodySmall,
              min: FontSettingsController.minFontSizeBodySmall,
              max: FontSettingsController.maxFontSizeBodySmall,
              // The tag role follows this size one pixel down; show both.
              preview: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: i18n("font_body_small_preview"), style: text.secondary),
                    const TextSpan(text: '  '),
                    TextSpan(text: i18n("font_tag_preview"), style: text.tag),
                  ],
                ),
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              i18n("font_typography_note"),
              style: text.secondary.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      );
    });
  }

  /// One size slider and, under it, a line drawn in the text role it sets.
  Widget _sizeRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required RxDouble setting,
    required double min,
    required double max,
    required Widget preview,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        context.buildSliderTile(
          context,
          icon: icon,
          title: title,
          subtitle: subtitle,
          value: setting.v,
          min: min,
          max: max,
          displayValue: formatPixels(setting.v.round()),
          onChanged: (newValue) => setting.v = newValue,
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            kSettingsRowSidePadding + kSettingsIconSlot + kSettingsIconGap,
            0,
            kSettingsRowSidePadding,
            settingsRowVerticalPadding,
          ),
          child: preview,
        ),
      ],
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
