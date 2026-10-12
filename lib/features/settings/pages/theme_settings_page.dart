import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/consts/app_consts.dart';
import 'package:pure_live/core/config/font_settings_controller.dart';
import 'package:pure_live/core/config/live_panel_layout.dart';
import 'package:pure_live/features/settings/pages/live_panel_tab_order_page.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:pure_live/features/settings/pages/font_settings_page.dart';
import 'package:pure_live/features/settings/pages/font_family_manager_page.dart';
import 'package:pure_live/features/settings/widgets/app_color_picker_dialog.dart';

/// The entries of 通用 › 主题设置 that this page serves, one card each.
enum ThemeSettingsSection { theme, fonts, livePanel }

class ThemeSettingsPage extends GetView<SettingsService> {
  const ThemeSettingsPage({super.key, this.section = ThemeSettingsSection.theme});

  final ThemeSettingsSection section;

  static String _currentFontName() {
    final font = SettingsService.to.font;
    return font.fontFamilyFileName.v.isNotEmpty ? font.fontFamilyFileName.v : font.fontFamilyName.v;
  }

  String get _title => switch (section) {
    ThemeSettingsSection.theme => i18n('theme_customization'),
    ThemeSettingsSection.fonts => i18n('font_group_settings'),
    ThemeSettingsSection.livePanel => i18n('live_panel_settings'),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: SettingsContentWidth(child: ListView(
        physics: const PureLiveScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          ...switch (section) {
            ThemeSettingsSection.theme => [
              context.buildModernCard([
                context.buildTile(
                  icon: Remix.moon_clear_line,
                  title: i18n("change_theme_mode"),
                  subtitle: i18n("change_theme_mode_subtitle"),
                  onTap: () => showThemeModeSelectorDialog(context),
                ),
                context.buildTile(
                  icon: Remix.palette_line,
                  title: i18n("change_theme_color"),
                  subtitle: i18n("change_theme_color_subtitle"),
                  onTap: () => colorPickerDialog(context),
                  trailing: Obx(
                    () => ColorIndicator(
                      width: 28,
                      height: 28,
                      borderRadius: 6,
                      color: SettingsService.to.theme.themeColor,
                      onSelectFocus: false,
                    ),
                  ),
                ),
                context.buildSwitchTile(
                  title: i18n("enable_dynamic_color"),
                  subtitle: i18n("enable_dynamic_color_subtitle"),
                  value: SettingsService.to.theme.enableDynamicTheme,
                  icon: Remix.magic_line,
                ),
                // Greyed out while the app is forced to the light theme.
                Obx(
                  () => context.buildSwitchTile(
                    title: i18n("pure_black_dark"),
                    subtitle: i18n("pure_black_dark_subtitle"),
                    value: SettingsService.to.theme.pureBlackDark,
                    icon: Remix.contrast_drop_2_line,
                    enabled: SettingsService.to.theme.themeMode != ThemeMode.light,
                  ),
                ),
              ]),
            ],
            ThemeSettingsSection.fonts => [
              context.buildModernCard([
                Obx(
                  () => context.buildTile(
                    icon: Remix.font_color,
                    title: i18n("change_font_family"),
                    subtitle: "${i18n("current_font_prefix")}: ${_currentFontName()}",
                    onTap: () => Get.to(() => const FontFamilyManagerPage()),
                  ),
                ),
                context.buildTile(
                  icon: Remix.font_size,
                  title: i18n("font_settings_title"),
                  subtitle: i18n("font_settings_desc"),
                  onTap: () => Get.to(() => const FontSettingsPage()),
                ),
                Obx(
                  () => context.buildSliderTile(
                    context,
                    icon: Remix.text_spacing,
                    title: i18n("text_size_title"),
                    value: SettingsService.to.font.textScaleFactor.v,
                    min: FontSettingsController.minTextScaleFactor,
                    max: FontSettingsController.maxTextScaleFactor,
                    displayValue: SettingsService.to.font.textScaleFactor.v.toStringAsFixed(2),
                    onChanged: (val) {
                      SettingsService.to.font.textScaleFactor.v = val;
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Align(
                    alignment: Alignment.center,
                    child: Text(i18n("text_size_preview"), style: TextStyle(color: theme.colorScheme.outline)),
                  ),
                ),
              ]),
            ],
            ThemeSettingsSection.livePanel => [
              context.buildModernCard([
                context.buildTile(
                  icon: Remix.drag_move_2_line,
                  title: i18n("live_panel_tab_order"),
                  subtitle: i18n("live_panel_tab_order_subtitle"),
                  onTap: () => Get.to(() => const LivePanelTabOrderPage()),
                ),
                Obx(
                  () => context.buildSliderTile(
                    context,
                    icon: Remix.layout_right_2_line,
                    title: i18n("live_panel_width"),
                    subtitle: i18n("live_panel_width_subtitle"),
                    value: LivePanelWidth.normalize(SettingsService.to.theme.livePanelWidth.v),
                    min: LivePanelWidth.min,
                    max: LivePanelWidth.max,
                    displayValue: '${LivePanelWidth.normalize(SettingsService.to.theme.livePanelWidth.v).round()}',
                    onChanged: (val) => SettingsService.to.theme.livePanelWidth.v = val.roundToDouble(),
                  ),
                ),
              ]),
            ],
          },
          const SizedBox(height: 32),
        ],
      )),
    );
  }

  Future<void> showThemeModeSelectorDialog(BuildContext context) async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => ThemeChoiceDialog<String>(
        title: i18n('change_theme_mode'),
        value: SettingsService.to.theme.resolvedThemeModeName,
        items: {for (final name in AppConsts.themeModes.keys) name: i18n(AppConsts.themeModeI18n[name]!)},
      ),
    );
    if (value != null) SettingsService.to.theme.changeThemeMode(value);
  }

  Future<bool> colorPickerDialog(BuildContext context) async {
    final bool isZh = Get.locale?.languageCode == 'zh';
    final initialColor = SettingsService.to.theme.themeColor;
    return showAppColorPickerDialog(
      context: context,
      initialColor: initialColor,
      title: i18n('theme_color'),
      enableOpacity: false,
      labels: buildAppColorPickerLabels(translate: (key) => i18n(key), isChinese: isZh, enableOpacity: false),
      customColorSwatchesAndNames: AppConsts.colorsNameMap,
      onColorChanged: (Color color) {
        // The app root rebuilds both themes from this value.
        SettingsService.to.theme.themeColorSwitch.v = color.hex;
      },
    );
  }
}

class ThemeChoiceDialog<T> extends StatelessWidget {
  const ThemeChoiceDialog({super.key, required this.title, required this.value, required this.items});

  final String title;
  final T value;
  final Map<T, String> items;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final compact = mediaQuery.size.width < 420 || mediaQuery.textScaler.scale(13) > 18;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: compact ? 12 : 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 400, maxHeight: mediaQuery.size.height - 48),
        child: SingleChildScrollView(
          key: const ValueKey('theme-choice-dialog-scroll'),
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(compact ? 12 : 20, 20, compact ? 12 : 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Tooltip(
                  message: title,
                  child: Text(
                    title,
                    key: const ValueKey('theme-choice-dialog-title'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              RadioGroup<T>(
                groupValue: value,
                onChanged: (selected) {
                  if (selected != null) Navigator.of(context).pop(selected);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: items.entries.map((entry) {
                    return RadioListTile<T>(
                      key: ValueKey('theme-choice-${entry.key}'),
                      title: Tooltip(message: entry.value, child: Text(entry.value)),
                      value: entry.key,
                      activeColor: Theme.of(context).colorScheme.primary,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Picks the app language; shared by the 通用 settings page.
Future<void> showLanguageSelectDialog(BuildContext pageContext) async {
  final value = await showDialog<String>(
    context: pageContext,
    builder: (context) => ThemeChoiceDialog<String>(
      title: i18n('change_language'),
      value: SettingsService.to.theme.resolvedLanguageName,
      items: {for (final name in AppConsts.languages.keys) name: name},
    ),
  );
  if (value != null && pageContext.mounted) {
    await SettingsService.to.theme.changeLanguage(value, pageContext);
  }
}
