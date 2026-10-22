import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/utils/setting_value_format.dart';
import 'package:pure_live/core/config/danmaku_settings_controller.dart';
import 'package:pure_live/core/consts/app_consts.dart';
import 'package:pure_live/core/platform/platform_utils.dart';
import 'package:pure_live/core/widgets/thumb_only_slider.dart';
import 'package:pure_live/core/widgets/count_button.dart';
import 'package:pure_live/core/player/presentation/danmaku/danmaku_surface_settings.dart';
import 'package:pure_live/core/player/presentation/danmaku/chat_list_color_mode_tile.dart';

class DanmakuSettingsPage extends StatelessWidget {
  const DanmakuSettingsPage({super.key, required this.controller, this.footer});
  final DanmakuSettingsSource controller;

  /// Extra section appended after the settings (the room panel's 屏蔽管理).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DanmakuSettingsContent(controller: controller, footer: footer),
    );
  }
}

/// One canonical live-danmaku settings surface.
///
/// Portrait embeds it in the room tab while fullscreen/landscape embeds the
/// same widget in an adaptive side dialog. Both entries therefore share the
/// same controls, ranges, presets and reactive state.
class DanmakuSettingsContent extends StatefulWidget {
  const DanmakuSettingsContent({
    super.key,
    required this.controller,
    this.embedded = false,
    this.includePipSettings = true,
    this.header,
    this.footer,
    this.trailing,
  });

  final DanmakuSettingsSource controller;
  final bool embedded;
  final bool includePipSettings;

  /// Extra section placed before the settings (the settings page's global
  /// show switch and frame-rate cap).
  final Widget? header;

  /// Extra section appended after the settings.
  final Widget? footer;

  /// Extra section placed after everything else (the settings page's danmaku
  /// font list).
  final Widget? trailing;

  @override
  State<DanmakuSettingsContent> createState() => _DanmakuSettingsContentState();
}

class _DanmakuSettingsContentState extends State<DanmakuSettingsContent> {
  late final ScrollController _scrollController;

  DanmakuSettingsSource get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _scrollController = createPureLiveScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool get isEmbedded => widget.embedded;

  /// Space between sections, and under a section title.
  static const double _titleGap = 6;

  /// The settings page on desktop spaces its rows out, as the other
  /// settings pages do there; the in-room panel stays dense everywhere.
  bool get _roomy => PlatformUtils.isDesktop && !isEmbedded;

  double get _sectionGap => _roomy ? 22 : 14;

  ThemeData get theme => Theme.of(context);

  Color get labelColor => isEmbedded ? theme.colorScheme.onSurface : theme.colorScheme.onSurface;

  Color get primaryColor => theme.colorScheme.primary;

  Color get cardColor =>
      isEmbedded ? theme.colorScheme.surfaceContainerLowest : theme.colorScheme.surfaceContainerHighest;
  Widget reactiveCard(List<Widget> Function() builder) {
    return Obx(() {
      final children = builder();

      if (isEmbedded) {
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(children: children),
        );
      }

      return context.buildModernCard(children);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color labelColor = theme.colorScheme.onSurface;
    final Color digitColor = theme.colorScheme.primary;
    return SingleChildScrollView(
      key: ValueKey(widget.embedded ? 'danmaku-settings-content-embedded' : 'danmaku-settings-content-page'),
      controller: _scrollController,
      physics: const PureLiveScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: widget.embedded ? 12 : 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?widget.header,
          // The first group title keeps the same space above it as every
          // later one (the list's own top padding plus the rest of a gap).
          SizedBox(height: _sectionGap - 8),
          // The side panel chat list has its own text size and spacing,
          // separate from the danmaku scrolling over the video below.
          context.buildGroupTitle(i18n('chat_list_display')),
          const SizedBox(height: _titleGap),
          reactiveCard(
            () => [
              _slider(
                title: i18n('chat_list_font_size'),
                value: SettingsService.to.danmaku.chatListFontSize.v.clamp(10.0, 28.0).toDouble(),
                min: 10,
                max: 28,
                // Continuous, kept to 0.1 px.
                display: formatPixels(SettingsService.to.danmaku.chatListFontSize.v),
                semanticValueBuilder: (value) => formatPixels((value * 10).round() / 10),
                onChanged: (v) => SettingsService.to.danmaku.chatListFontSize.v = (v * 10).round() / 10,
                labelColor: labelColor,
              ),
              _slider(
                title: i18n('chat_list_font_weight'),
                value: SettingsService.to.danmaku.chatListFontWeight.v.clamp(100, 900).toDouble(),
                min: 100,
                max: 900,
                stepSize: 100,
                display: i18n(
                  AppConsts.fontWeightLabels[SettingsService.to.danmaku.chatListFontWeight.v] ?? 'font_weight_normal',
                ),
                semanticValueBuilder: (value) =>
                    i18n(AppConsts.fontWeightLabels[value.round()] ?? 'font_weight_normal'),
                onChanged: (v) => SettingsService.to.danmaku.chatListFontWeight.v = (v / 100).round() * 100,
                labelColor: labelColor,
              ),
              _slider(
                title: i18n('chat_list_name_font_weight'),
                value: SettingsService.to.danmaku.chatListNameFontWeight.v.clamp(100, 900).toDouble(),
                min: 100,
                max: 900,
                stepSize: 100,
                display: i18n(
                  AppConsts.fontWeightLabels[SettingsService.to.danmaku.chatListNameFontWeight.v] ??
                      'font_weight_normal',
                ),
                semanticValueBuilder: (value) =>
                    i18n(AppConsts.fontWeightLabels[value.round()] ?? 'font_weight_normal'),
                onChanged: (v) => SettingsService.to.danmaku.chatListNameFontWeight.v = (v / 100).round() * 100,
                labelColor: labelColor,
              ),
              _slider(
                title: i18n('chat_list_item_spacing'),
                value: SettingsService.to.danmaku.chatListItemGap.v
                    .clamp(0.0, DanmakuSettingsController.maxChatListItemGap)
                    .toDouble(),
                min: 0,
                max: DanmakuSettingsController.maxChatListItemGap,
                stepSize: 0.05,
                // In text lines, as the bubble height; 0 shares one edge.
                display: formatTimes(SettingsService.to.danmaku.chatListItemGap.v),
                semanticValueBuilder: (value) => formatTimes(value),
                onChanged: (v) => SettingsService.to.danmaku.chatListItemGap.v = (v * 20).round() / 20,
                labelColor: labelColor,
              ),
              _switch(
                theme,
                title: i18n('chat_list_bubble'),
                subtitle: i18n('chat_list_bubble_subtitle'),
                value: SettingsService.to.danmaku.chatListBubble.v,
                onChanged: (v) => SettingsService.to.danmaku.chatListBubble.v = v,
                labelColor: labelColor,
              ),
              if (SettingsService.to.danmaku.chatListBubble.v) ...[
                _slider(
                  title: i18n('chat_list_bubble_height'),
                  value: SettingsService.to.danmaku.chatListBubbleHeight.v
                      .clamp(
                        DanmakuSettingsController.minChatListBubbleHeight,
                        DanmakuSettingsController.maxChatListBubbleHeight,
                      )
                      .toDouble(),
                  min: DanmakuSettingsController.minChatListBubbleHeight,
                  max: DanmakuSettingsController.maxChatListBubbleHeight,
                  display: formatTimes(SettingsService.to.danmaku.chatListBubbleHeight.v, digits: 1),
                  semanticValueBuilder: (value) => formatTimes(value, digits: 1),
                  onChanged: (v) => SettingsService.to.danmaku.chatListBubbleHeight.v = (v * 10).round() / 10,
                  labelColor: labelColor,
                ),
                _slider(
                  title: i18n('chat_list_bubble_fill_opacity'),
                  value: SettingsService.to.danmaku.chatListBubbleFillOpacity.v,
                  min: 0,
                  max: 1,
                  display: formatPercent(SettingsService.to.danmaku.chatListBubbleFillOpacity.v),
                  semanticValueBuilder: (value) => formatPercent(value),
                  onChanged: (v) => SettingsService.to.danmaku.chatListBubbleFillOpacity.v = (v * 20).round() / 20,
                  labelColor: labelColor,
                ),
              ],
              ChatListColorModeTile(horizontalPadding: isEmbedded ? 14 : 16, labelColor: labelColor),
            ],
          ),
          SizedBox(height: _sectionGap),
          context.buildGroupTitle(i18n("danmaku_display_group")),
          const SizedBox(height: _titleGap),
          reactiveCard(
            () => [
              _slider(
                title: i18n("opacity"),
                value: controller.danmakuOpacity.value,
                min: 0,
                max: 1,
                display: formatPercent(controller.danmakuOpacity.value),
                semanticValueBuilder: (value) => formatPercent(value),
                onChanged: (v) => controller.danmakuOpacity.value = v,
                labelColor: labelColor,
              ),
              _slider(
                title: i18n("font_size"),
                value: controller.danmakuFontSize.value.toDouble(),
                min: 10,
                max: 30,
                display: formatPixels(double.parse(controller.danmakuFontSize.value.toStringAsFixed(1))),
                semanticValueBuilder: (value) => formatPixels(double.parse(value.toStringAsFixed(1))),
                onChanged: (v) => controller.danmakuFontSize.value = v,
                labelColor: labelColor,
              ),
              _slider(
                title: i18n('font_weight'),
                value: controller.danmakuFontWeight.value.toDouble(),
                min: 100,
                max: 900,
                stepSize: 100,
                display: i18n(AppConsts.fontWeightLabels[controller.danmakuFontWeight.value] ?? 'font_weight_medium'),
                semanticValueBuilder: (value) =>
                    i18n(AppConsts.fontWeightLabels[value.round()] ?? 'font_weight_medium'),
                onChanged: (v) => controller.danmakuFontWeight.value = (v / 100).round() * 100,
                labelColor: labelColor,
              ),
              // 弹幕间距: the gap between two tracks, as a share of the font
              // size. Kept per profile with the rest of the floating style.
              _slider(
                title: i18n('danmaku_line_spacing'),
                value: DanmakuSettingsController.normalizeLineSpacing(
                  SettingsService.to.danmaku.danmakuLineSpacing.value,
                ),
                min: DanmakuSettingsController.minDanmakuLineSpacing,
                max: DanmakuSettingsController.maxDanmakuLineSpacing,
                stepSize: 0.05,
                // A multiple of the font size, as the list's gap is of its line.
                display: formatTimes(SettingsService.to.danmaku.danmakuLineSpacing.value),
                semanticValueBuilder: (value) => formatTimes(value),
                onChanged: (v) =>
                    SettingsService.to.danmaku.danmakuLineSpacing.value = DanmakuSettingsController.normalizeLineSpacing(v),
                labelColor: labelColor,
              ),
              _switch(
                theme,
                title: i18n("danmaku_stroke"),
                value: controller.enableDanmakuStroke.value,
                onChanged: (v) => controller.enableDanmakuStroke.value = v,
                labelColor: labelColor,
              ),
              _slider(
                title: i18n("stroke"),
                value: controller.danmakuFontBorder.value.toDouble(),
                min: 0,
                max: 4,
                display: formatPixels(double.parse(controller.danmakuFontBorder.value.toStringAsFixed(1))),
                semanticValueBuilder: (value) => formatPixels(double.parse(value.toStringAsFixed(1))),
                onChanged: (v) => controller.danmakuFontBorder.value = v,
                labelColor: labelColor,
              ),
              _switch(
                theme,
                title: i18n('max_visible_count_auto'),
                subtitle: i18n('max_visible_count_auto_subtitle'),
                value: controller.danmakuAutoMaxVisible.value,
                onChanged: (v) => controller.danmakuAutoMaxVisible.value = v,
                labelColor: labelColor,
              ),
              if (!controller.danmakuAutoMaxVisible.value)
                _slider(
                  title: i18n("max_visible_count"),
                  value: controller.danmakuMaxVisibleCount.value.toDouble(),
                  min: DanmakuSettingsController.minDanmakuMaxVisibleCount.toDouble(),
                  max: DanmakuSettingsController.maxDanmakuMaxVisibleCount.toDouble(),
                  display: controller.danmakuMaxVisibleCount.value.toString(),
                  semanticValueBuilder: (value) => value.toInt().toString(),
                  onChanged: (v) => controller.danmakuMaxVisibleCount.v = v.toInt(),
                  labelColor: labelColor,
                ),
              _switch(
                theme,
                title: i18n("danmaku_mass_mode"),
                subtitle: i18n("danmaku_mass_mode_subtitle"),
                value: controller.danmakuMassMode.value,
                onChanged: (v) => controller.danmakuMassMode.value = v,
                labelColor: labelColor,
              ),
              _switch(
                theme,
                title: i18n('danmaku_no_emoji'),
                value: controller.noEmojiMode.value,
                onChanged: (value) => controller.noEmojiMode.value = value,
                labelColor: labelColor,
              ),
              _slider(
                title: i18n("speed"),
                value: controller.danmakuSpeed.value.toDouble(),
                min: 20,
                max: 400,
                display: '${controller.danmakuSpeed.value.toInt()} px/s',
                semanticValueBuilder: (value) => '${value.toInt()} px/s',
                onChanged: (v) => controller.danmakuSpeed.value = v,
                labelColor: labelColor,
              ),
              _switch(
                theme,
                title: '${i18n("danmaku_fps")} · ${i18n("dynamic_follow_display")}',
                subtitle: i18n('danmaku_fps_policy_desc'),
                value: SettingsService.to.danmaku.danmakuAutoFps.v,
                onChanged: (v) => SettingsService.to.danmaku.danmakuAutoFps.v = v,
                labelColor: labelColor,
                subtitleColor: labelColor,
              ),
              if (!SettingsService.to.danmaku.danmakuAutoFps.v)
                _slider(
                  title: i18n("danmaku_fps"),
                  value: controller.danmakuFps.value.toDouble(),
                  min: 30,
                  max: 240,
                  display: "${controller.danmakuFps.value.toInt()} FPS",
                  semanticValueBuilder: (value) => '${value.toInt()} FPS',
                  onChanged: (v) => controller.danmakuFps.value = v.toInt(),
                  labelColor: labelColor,
                )
              else
                Padding(
                  padding: EdgeInsets.fromLTRB(isEmbedded ? 14 : 16, 0, isEmbedded ? 14 : 16, isEmbedded ? 10 : 12),
                  child: Text(
                    '${SettingsService.to.danmaku.resolvedDanmakuFps()} FPS',
                    style: AppText.of(context).body.copyWith(color: digitColor, fontWeight: FontWeight.w600),
                  ),
                ),
              _slider(
                title: i18n("danmaku_display_area"),
                value: DanmakuSettingsController.normalizeDanmakuArea(controller.danmakuArea.value),
                min: DanmakuSettingsController.minDanmakuArea,
                max: 1,
                stepSize: DanmakuSettingsController.danmakuAreaStep,
                display: formatPercent(controller.danmakuArea.value),
                semanticValueBuilder: (value) => formatPercent(value),
                onChanged: (v) => controller.danmakuArea.value = DanmakuSettingsController.normalizeDanmakuArea(v),
                labelColor: labelColor,
              ),
              _counter(
                theme,
                title: i18n("margin_top"),
                value: controller.danmakuTopArea.value.toInt(),
                max: 300,
                unit: 'px',
                onChanged: (v) => controller.danmakuTopArea.value = v.toDouble(),
                labelColor: labelColor,
              ),
              _counter(
                theme,
                title: i18n("margin_bottom"),
                value: controller.danmakuBottomArea.value.toInt(),
                max: 300,
                unit: 'px',
                onChanged: (v) => controller.danmakuBottomArea.value = v.toDouble(),
                labelColor: labelColor,
              ),
              _switch(
                theme,
                title: i18n("pip_danmaku_scale_auto"),
                subtitle: i18n("pip_danmaku_scale_auto_subtitle"),
                value: controller.pipDanmakuScaleAuto.value,
                onChanged: (v) => controller.pipDanmakuScaleAuto.value = v,
                labelColor: labelColor,
              ),
              if (!controller.pipDanmakuScaleAuto.value)
                _slider(
                  title: i18n("pip_danmaku_scale"),
                  value: controller.pipDanmakuScaleValue.value,
                  min: DanmakuSettingsController.pipDanmakuScaleMin,
                  max: DanmakuSettingsController.pipDanmakuScaleMax,
                  display: formatTimes(controller.pipDanmakuScaleValue.value),
                  semanticValueBuilder: (value) => formatTimes(value),
                  onChanged: (v) => controller.pipDanmakuScaleValue.value = v,
                  labelColor: labelColor,
                ),
            ],
          ),
          SizedBox(height: _sectionGap),
          // 留言: super chats get their own cards on a live room's picture,
          // independent of the scrolling barrage above.
          context.buildGroupTitle(i18n('super_chat_group')),
          const SizedBox(height: _titleGap),
          reactiveCard(
            () => [
              // One setting shown as its two states, after Simple Live: the
              // 留言 list keeps every super chat, or each leaves when its
              // countdown ends. Turning either on turns the other off.
              _switch(
                theme,
                title: i18n('super_chat_pinned'),
                subtitle: i18n('super_chat_pinned_subtitle'),
                value: SettingsService.to.danmaku.superChatPinned.value,
                onChanged: (v) => SettingsService.to.danmaku.superChatPinned.value = v,
                labelColor: labelColor,
              ),
              _switch(
                theme,
                title: i18n('super_chat_countdown'),
                subtitle: i18n('super_chat_countdown_subtitle'),
                value: !SettingsService.to.danmaku.superChatPinned.value,
                onChanged: (v) => SettingsService.to.danmaku.superChatPinned.value = !v,
                labelColor: labelColor,
              ),
              // The message text's weight, in the 留言 list and on the picture;
              // one shared setting, so every open card follows it at once.
              _slider(
                title: i18n('super_chat_font_weight'),
                value: SettingsService.to.danmaku.superChatFontWeight.value.clamp(100, 900).toDouble(),
                min: 100,
                max: 900,
                stepSize: 100,
                display: i18n(
                  AppConsts.fontWeightLabels[SettingsService.to.danmaku.superChatFontWeight.value] ??
                      'font_weight_normal',
                ),
                semanticValueBuilder: (value) => i18n(AppConsts.fontWeightLabels[value.round()] ?? 'font_weight_normal'),
                onChanged: (v) => SettingsService.to.danmaku.superChatFontWeight.value = (v / 100).round() * 100,
                labelColor: labelColor,
              ),
              _switch(
                theme,
                title: i18n('show_super_chat_on_player'),
                subtitle: i18n('show_super_chat_on_player_subtitle'),
                value: controller.showSuperChatOnPlayer.value,
                onChanged: (v) => controller.showSuperChatOnPlayer.value = v,
                labelColor: labelColor,
              ),
              if (controller.showSuperChatOnPlayer.value) ...[
                _slider(
                  title: i18n('super_chat_opacity'),
                  value: DanmakuSettingsController.normalizeSuperChatOpacity(controller.superChatOpacity.value),
                  min: DanmakuSettingsController.minSuperChatOpacity,
                  max: 1,
                  stepSize: 0.05,
                  display: formatPercent(controller.superChatOpacity.value),
                  semanticValueBuilder: (value) => formatPercent(value),
                  onChanged: (v) =>
                      controller.superChatOpacity.value = DanmakuSettingsController.normalizeSuperChatOpacity(v),
                  labelColor: labelColor,
                ),
                _slider(
                  title: i18n('super_chat_font_scale'),
                  value: DanmakuSettingsController.normalizeSuperChatFontScale(controller.superChatFontScale.value),
                  min: DanmakuSettingsController.minSuperChatFontScale,
                  max: DanmakuSettingsController.maxSuperChatFontScale,
                  stepSize: 0.1,
                  display: formatTimes(controller.superChatFontScale.value, digits: 1),
                  semanticValueBuilder: (value) => formatTimes(value, digits: 1),
                  onChanged: (v) =>
                      controller.superChatFontScale.value = DanmakuSettingsController.normalizeSuperChatFontScale(v),
                  labelColor: labelColor,
                ),
              ],
            ],
          ),
          SizedBox(height: _sectionGap),
          // The side panel's footer brings the full 弹幕过滤 group (repeated,
          // similar and keyword filtering); elsewhere only the repeat filter.
          if (widget.footer != null)
            widget.footer!
          else ...[
            context.buildGroupTitle(i18n('danmaku_filter_group')),
            const SizedBox(height: _titleGap),
            reactiveCard(
              () => [
                _switch(
                  theme,
                  title: i18n('collapse_repeated_danmaku'),
                  subtitle: i18n('collapse_repeated_danmaku_desc'),
                  value: SettingsService.to.danmaku.collapseRepeatedDanmaku.v,
                  onChanged: (v) => SettingsService.to.danmaku.collapseRepeatedDanmaku.v = v,
                  labelColor: labelColor,
                  subtitleColor: labelColor,
                ),
                if (SettingsService.to.danmaku.collapseRepeatedDanmaku.v)
                  _counter(
                    theme,
                    title: i18n('repeated_danmaku_window'),
                    value: SettingsService.to.danmaku.repeatedDanmakuWindowSeconds.v,
                    min: 1,
                    max: 30,
                    unit: i18n('value_seconds', args: {'n': ''}).trim(),
                    onChanged: (v) => SettingsService.to.danmaku.repeatedDanmakuWindowSeconds.v = v,
                    labelColor: labelColor,
                  ),
              ],
            ),
            SizedBox(height: _sectionGap),
          ],
          context.buildGroupTitle(i18n('danmaku_screen_interaction')),
          const SizedBox(height: _titleGap),
          reactiveCard(
            () => [
              _switch(
                theme,
                title: i18n('danmaku_tap_action'),
                value: SettingsService.to.danmaku.enableDanmakuTapInteraction.v,
                onChanged: (v) => SettingsService.to.danmaku.enableDanmakuTapInteraction.v = v,
                labelColor: labelColor,
              ),
              _switch(
                theme,
                title: i18n('danmaku_long_press_action'),
                value: SettingsService.to.danmaku.enableDanmakuLongPressInteraction.v,
                onChanged: (v) => SettingsService.to.danmaku.enableDanmakuLongPressInteraction.v = v,
                labelColor: labelColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ?widget.trailing,
        ],
      ),
    );
  }

  Widget _slider({
    required String title,
    required double value,
    required double min,
    required double max,
    required String display,
    required String Function(double value) semanticValueBuilder,
    required ValueChanged<double> onChanged,
    required Color labelColor,
    double? stepSize,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: _roomy ? 12 : 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppText.of(context).sectionTitle.copyWith(color: labelColor),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: SliderPalette.of(context).badge,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  display,
                  style: AppText.of(context).secondary.copyWith(
                    fontWeight: FontWeight.bold,
                    color: SliderPalette.of(context).badgeText,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: _roomy ? 6 : 2),
          SizedBox(
            width: double.infinity,
            child: ThumbOnlySlider(
              min: min,
              max: max,
              value: value,
              stepSize: stepSize,
              semanticFormatterCallback: (semanticValue) =>
                '$title, ${semanticValueBuilder(semanticValue)}',
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _counter(
    ThemeData theme, {
    required String title,
    required int value,
    int min = 0,
    required int max,
    required ValueChanged<int> onChanged,
    required Color labelColor,
    String? unit,
  }) {
    // The stepper is neutral grey, as the slider value badges are.
    final palette = SliderPalette.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: _roomy ? 12 : 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: AppText.of(context).sectionTitle.copyWith(color: labelColor),
            ),
          ),
          const SizedBox(width: 8),
          CountButton(
            maxValue: max,
            minValue: min,
            selectedValue: value,
            semanticLabel: title,
            decrementSemanticLabel: i18n('decrease_value', args: {'label': title}),
            incrementSemanticLabel: i18n('increase_value', args: {'label': title}),
            onChanged: onChanged,
            backgroundColor: palette.badge,
            foregroundColor: palette.badgeText,
            // A compact stepper: small −/+ buttons around a value box wide
            // enough for three digits.
            buttonSize: const Size(30, 28),
            borderRadius: 8,
            valueMinWidth: 48,
            decrementIcon: Icon(Icons.remove, size: 16, color: palette.badgeText),
            incrementIcon: Icon(Icons.add, size: 16, color: palette.badgeText),
            textStyle: AppText.of(context).body.copyWith(color: palette.badgeText, fontWeight: FontWeight.bold),
          ),
          // The value's unit after the stepper, as the sliders show theirs.
          if (unit != null) ...[
            const SizedBox(width: 6),
            Text(unit, style: AppText.of(context).body.copyWith(color: palette.badgeText)),
          ],
        ],
      ),
    );
  }

  Widget _switch(
    ThemeData theme, {
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color labelColor,
    Color? subtitleColor,
  }) {
    return Material(
      type: MaterialType.transparency,
      child: SwitchListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: isEmbedded ? 14 : 16),
        dense: false,
        // A little shorter than a standard row where the list is dense;
        // standard height on the desktop settings page.
        visualDensity: _roomy ? VisualDensity.standard : const VisualDensity(vertical: -2),
        title: Text(
          title,
          style: AppText.of(context).sectionTitle.copyWith(color: labelColor),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle,
                style: subtitleColor != null
                    ? AppText.of(context).secondary.copyWith(color: subtitleColor)
                    : AppText.of(context).secondary,
              ),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
