import 'dart:io';

import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/utils/setting_value_format.dart';
import 'package:pure_live/core/consts/app_consts.dart';
import 'package:pure_live/core/config/room_card_settings_controller.dart';
import 'package:pure_live/domains/live/presentation/widgets/room_card.dart';
import 'package:pure_live/domains/live/presentation/widgets/room_grid_sizing.dart';
import 'package:pure_live/core/config/theme_settings_controller.dart';
import 'package:pure_live/features/settings/pages/audience_metric_settings_page.dart';

class RoomCardSettingsPage extends StatefulWidget {
  const RoomCardSettingsPage({super.key});

  @override
  State<RoomCardSettingsPage> createState() => _RoomCardSettingsPageState();
}

class _RoomCardSettingsPageState extends State<RoomCardSettingsPage> {
  // A made-up room: the preview only draws it and never opens it.
  LiveRoom get _previewRoom => LiveRoom(
    roomId: '',
    platform: 'bilibili',
    title: 'Pure Live · ${i18n('room_card_preview_title')}',
    nick: i18n('room_card_preview_anchor'),
    cover: '',
    avatar: '',
    popularity: '12800',
    liveStatus: LiveStatus.live,
  );

  /// Width a card of the layout being edited gets in a grid: its fixed width
  /// when set, otherwise its column width for this window.
  double _previewCardWidth(BuildContext context, RoomCardSettingsController controller) {
    final width = MediaQuery.sizeOf(context).width;
    final layout = controller.editingLayout.value;
    final sizing = resolveRoomGridSizing(
      width: width,
      autoColumns: roomGridAutoColumns(width, dense: SettingsService.to.app.enableDenseFavorites.v),
      spacing: SettingsService.to.theme.cardCrossSpacing(compact: layout == RoomCardLayout.compact),
      basePadding: 12,
      fixedCardWidth: controller.cardWidthFor(layout),
      columns: controller.columnsFor(layout),
    );
    return sizing.itemWidth;
  }

  @override
  Widget build(BuildContext context) {
    final controller = SettingsService.to.roomCard;
    return Scaffold(
      appBar: AppBar(
        title: Text(i18n('room_card_settings')),
        actions: [
          IconButton(
            key: const ValueKey('room-card-reset'),
            tooltip: i18n('room_card_reset_current'),
            onPressed: controller.reset,
            icon: const Icon(Remix.restart_line),
          ),
        ],
      ),
      body: SettingsContentWidth(child: Obx(() {
        // Everything below edits the look of one layout: the one picked at
        // the top of 外观 (紧凑信息行 or 封面卡片).
        final config = controller.appearanceFor(controller.editingLayout.value);
        final compact = config.layout == RoomCardLayout.compact;
        final profile = controller.profile.value;
        return ListView(
          key: const ValueKey('room-card-settings-scroll'),
          physics: const PureLiveScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            context.buildGroupTitle(i18n('room_card_preview')),
            // Drawn at the width and density the 关注 grid gives a card, so
            // what shows here is what the grid shows.
            Center(
              child: SizedBox(
                width: _previewCardWidth(context, controller),
                // A picture of a card, not a card: nothing in it responds.
                child: IgnorePointer(
                  child: RoomCard(
                    key: ValueKey('room-card-preview-${profile.name}'),
                    room: _previewRoom,
                    layout: config.layout,
                    dense: SettingsService.to.app.enableDenseFavorites.v,
                    interactive: false,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            context.buildGroupTitle(i18n('room_card_appearance')),
            context.buildModernCard([
              _layoutMode(controller, config),
              // Card size: automatic (scales with the window) or a fixed width;
              // the grid then only changes its column count.
              context.buildTile(
                icon: Remix.aspect_ratio_line,
                title: i18n('room_card_fixed_width'),
                subtitle: i18n('room_card_fixed_width_subtitle'),
                trailing: Switch(
                  key: ValueKey('room-card-fixed-width-${profile.name}'),
                  value: controller.cardWidthFor(config.layout) > 0,
                  onChanged: (on) => controller.setCardWidth(
                    config.layout,
                    on ? RoomCardSettingsController.defaultFixedCardWidth : RoomCardSettingsController.autoCardWidth,
                  ),
                ),
              ),
              if (controller.cardWidthFor(config.layout) > 0)
                context.buildSliderTile(
                  context,
                  icon: Remix.ruler_line,
                  title: i18n('room_card_width'),
                  value: controller.cardWidthFor(config.layout),
                  min: RoomCardSettingsController.minCardWidth,
                  max: RoomCardSettingsController.maxCardWidth,
                  displayValue: formatPixels(controller.cardWidthFor(config.layout).round()),
                  onChanged: (value) => controller.setCardWidth(config.layout, value.roundToDouble()),
                )
              else
                // Without a fixed width the cards stretch to fill each row;
                // the row holds the chosen number of columns.
                context.buildSliderTile(
                  context,
                  icon: Remix.layout_column_line,
                  title: i18n('room_card_columns'),
                  subtitle: i18n('room_card_columns_subtitle'),
                  value: controller.columnsFor(config.layout).toDouble(),
                  min: RoomCardSettingsController.autoColumns.toDouble(),
                  max: RoomCardSettingsController.maxColumns.toDouble(),
                  displayValue: controller.columnsFor(config.layout) == RoomCardSettingsController.autoColumns
                      ? i18n('room_card_columns_auto')
                      : '${controller.columnsFor(config.layout)}',
                  onChanged: (value) =>
                      controller.setColumns(config.layout, RoomCardSettingsController.normalizeColumns(value)),
                ),
              context.buildSliderTile(
                context,
                icon: Remix.rounded_corner,
                title: i18n('room_card_corner_radius'),
                subtitle: i18n('room_card_corner_radius_subtitle'),
                value: config.cornerRadius,
                min: RoomCardAppearance.minCornerRadius,
                max: RoomCardAppearance.maxCornerRadius,
                displayValue: formatPixels(config.cornerRadius.round()),
                onChanged: (value) => controller.updateConfig(config.copyWith(cornerRadius: value)),
              ),
              // The cover cards' outline; the compact rows keep their own.
              if (!compact)
                context.buildSliderTile(
                  context,
                  icon: Remix.contrast_drop_2_line,
                  title: i18n('room_card_cover_border_opacity'),
                  subtitle: i18n('room_card_cover_border_opacity_subtitle'),
                  value: controller.coverBorderOpacity.v,
                  min: 0,
                  max: 1,
                  displayValue: formatPercent(controller.coverBorderOpacity.v),
                  onChanged: (value) =>
                      controller.coverBorderOpacity.v = RoomCardSettingsController.normalizeCoverBorderOpacity(value),
                ),
              // Gaps between cards in the grids: the same two sliders edit the
              // compact rows' pair or the cover cards' pair, whichever layout
              // is chosen above; each layout keeps its own.
              context.buildSliderTile(
                context,
                icon: Remix.arrow_left_right_line,
                title: i18n("cross_axis_spacing"),
                subtitle: i18n("cross_axis_spacing_subtitle"),
                value: SettingsService.to.theme.cardCrossSpacing(compact: compact),
                min: ThemeSettingsController.minSpacing,
                max: ThemeSettingsController.maxSpacing,
                displayValue: formatPixels(SettingsService.to.theme.cardCrossSpacing(compact: compact).round()),
                onChanged: (value) =>
                    SettingsService.to.theme.crossSpacingSetting(compact: compact).v = value.roundToDouble(),
              ),
              context.buildSliderTile(
                context,
                icon: Remix.arrow_up_down_line,
                title: i18n("main_axis_spacing"),
                subtitle: i18n("main_axis_spacing_subtitle"),
                value: SettingsService.to.theme.cardMainSpacing(compact: compact),
                min: ThemeSettingsController.minSpacing,
                max: ThemeSettingsController.maxSpacing,
                displayValue: formatPixels(SettingsService.to.theme.cardMainSpacing(compact: compact).round()),
                onChanged: (value) =>
                    SettingsService.to.theme.mainSpacingSetting(compact: compact).v = value.roundToDouble(),
              ),
            ]),
            const SizedBox(height: 20),
            // The home 关注 page: its platform tab bar and room order (the
            // order is also the 排序 button on that page).
            context.buildGroupTitle(i18n('favorite_page_group')),
            context.buildModernCard([
              _favoriteLayoutChoice(controller),
              _toggle(
                icon: Remix.apps_2_line,
                title: i18n('favorite_show_platform_tabs'),
                subtitle: i18n('favorite_show_platform_tabs_subtitle'),
                value: controller.showFavoritePlatformTabs.v,
                onChanged: (value) => controller.showFavoritePlatformTabs.v = value,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(padding: EdgeInsets.only(top: 2), child: SettingsRowIcon(Icons.filter_list_rounded)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(i18n('favorite_sort'), style: AppText.of(context).sectionTitle),
                          const SizedBox(height: 10),
                          Wrap(
                            key: const ValueKey('room-card-favorite-sort'),
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final mode in FavoriteSortMode.values)
                                ChoiceChip(
                                  label: Text(switch (mode) {
                                    FavoriteSortMode.name => i18n('favorite_sort_name'),
                                    FavoriteSortMode.platform => i18n('favorite_sort_platform'),
                                    FavoriteSortMode.audience => i18n('favorite_sort_audience'),
                                  }),
                                  selected: controller.favoriteSortMode == mode,
                                  onSelected: (_) => controller.favoriteSortModeName.v = mode.name,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 20),
            context.buildGroupTitle(i18n('room_card_visible_content')),
            context.buildModernCard([
              _toggle(
                icon: Remix.user_3_line,
                title: i18n('room_card_show_avatar'),
                subtitle: i18n('room_card_show_avatar_subtitle'),
                value: config.showAvatar,
                onChanged: (value) => controller.updateConfig(config.copyWith(showAvatar: value)),
              ),
              _toggle(
                icon: Remix.account_circle_line,
                title: i18n('room_card_show_anchor'),
                subtitle: i18n('room_card_show_anchor_subtitle'),
                value: config.showAnchorName,
                onChanged: (value) => controller.updateConfig(config.copyWith(showAnchorName: value)),
              ),
              _platformBadgeMode(controller, config),
              _toggle(
                icon: Remix.group_line,
                title: i18n('room_card_show_audience'),
                subtitle: i18n('room_card_show_audience_subtitle'),
                value: config.showAudience,
                onChanged: (value) => controller.updateConfig(config.copyWith(showAudience: value)),
              ),
              _toggle(
                icon: Remix.video_line,
                title: i18n('room_card_show_replay'),
                subtitle: i18n('room_card_show_replay_subtitle'),
                value: config.showReplayBadge,
                onChanged: (value) => controller.updateConfig(config.copyWith(showReplayBadge: value)),
              ),
              // Which audience figure the cards show (热度 or real viewers),
              // and per platform: global, unlike the toggles above.
              context.buildTile(
                icon: Icons.groups_2_rounded,
                title: i18n('audience_metric_settings'),
                subtitle: i18n('audience_metric_settings_desc'),
                onTap: () => Get.to(() => const AudienceMetricSettingsPage()),
              ),
            ]),
            const SizedBox(height: 16),
            Text(
              i18n('room_card_settings_scope_hint'),
              key: const ValueKey('room-card-settings-scope-hint'),
              style: AppText.of(context).secondary.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 20),
            // The home page menus. Global: unlike the card settings they are
            // the same in every display profile.
            context.buildGroupTitle(i18n("menu")),
            context.buildModernCard([
              for (final (menu, icon, title, page) in [
                (HomeMenu.search, Remix.search_line, i18n("search_live"), RoomListPage.search),
                (HomeMenu.areas, Remix.apps_2_line, i18n("areas_title"), RoomListPage.areaRooms),
                (HomeMenu.popular, Remix.fire_line, i18n("popular_title"), RoomListPage.popular),
              ])
                KeyedSubtree(
                  key: ValueKey('menu-entry-${menu.id}'),
                  child: Obx(
                    () => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        context.buildSwitchTile(
                          title: title,
                          subtitle: i18n("menu_entry_visible_subtitle"),
                          value: SettingsService.to.app.showsMenu(menu).obs,
                          icon: icon,
                          autoCommit: false,
                          onChanged: (visible) => SettingsService.to.app.toggleMenuVisibility(menu, visible),
                        ),
                        // The page's rooms as 紧凑信息 or 封面卡片, each with
                        // the gaps set above for it.
                        if (SettingsService.to.app.showsMenu(menu)) _pageLayoutChoice(controller, page),
                      ],
                    ),
                  ),
                ),
              if (Platform.isWindows)
                context.buildSwitchTile(
                  title: i18n("multiview_title"),
                  subtitle: i18n("multiview_entry_subtitle"),
                  value: SettingsService.to.app.enableMultiView,
                  icon: Remix.layout_grid_line,
                ),
            ]),
          ],
        );
      })),
    );
  }

  Widget _toggle({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: SettingsRowIcon(icon),
      title: Text(title, style: AppText.of(context).sectionTitle),
      subtitle: Text(subtitle, style: AppText.of(context).secondary),
      value: value,
      onChanged: onChanged,
      contentPadding: kSettingsSwitchRowPadding,
    );
  }

  Widget _platformBadgeMode(RoomCardSettingsController controller, RoomCardAppearance config) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: SettingsRowIcon(Remix.layout_grid_line)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i18n('room_card_show_platform'), style: AppText.of(context).sectionTitle),
                const SizedBox(height: 2),
                Text(i18n('room_card_show_platform_subtitle'), style: AppText.of(context).secondary),
                const SizedBox(height: 10),
                Wrap(
                  key: const ValueKey('room-card-platform-mode'),
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _platformModeChip(
                      controller,
                      config,
                      RoomCardPlatformBadgeMode.automatic,
                      i18n('room_card_platform_automatic'),
                    ),
                    _platformModeChip(
                      controller,
                      config,
                      RoomCardPlatformBadgeMode.always,
                      i18n('room_card_platform_always'),
                    ),
                    _platformModeChip(
                      controller,
                      config,
                      RoomCardPlatformBadgeMode.hidden,
                      i18n('room_card_platform_hidden'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _layoutMode(RoomCardSettingsController controller, RoomCardAppearance config) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: SettingsRowIcon(Icons.view_agenda_outlined)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i18n('room_card_layout'), style: AppText.of(context).sectionTitle),
                const SizedBox(height: 2),
                Text(i18n('room_card_layout_subtitle'), style: AppText.of(context).secondary),
                const SizedBox(height: 10),
                Wrap(
                  key: const ValueKey('room-card-layout-mode'),
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _layoutModeChip(controller, config, RoomCardLayout.cover, i18n('room_card_layout_cover')),
                    _layoutModeChip(controller, config, RoomCardLayout.compact, i18n('room_card_layout_compact')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Which layout 主页关注 shows (each layout keeps its own look).
  Widget _favoriteLayoutChoice(RoomCardSettingsController controller) {
    final current = controller.favoriteLayout;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: SettingsRowIcon(Icons.favorite_border_rounded)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i18n('favorite_page_layout'), style: AppText.of(context).sectionTitle),
                const SizedBox(height: 10),
                Wrap(
                  key: const ValueKey('favorite-page-layout'),
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (layout, label) in [
                      (RoomCardLayout.compact, i18n('room_card_layout_compact')),
                      (RoomCardLayout.cover, i18n('room_card_layout_cover')),
                    ])
                      ChoiceChip(
                        key: ValueKey('favorite-page-layout-${layout.name}'),
                        label: Text(label),
                        selected: current == layout,
                        onSelected: (_) => controller.setFavoriteLayout(layout),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pageLayoutChoice(RoomCardSettingsController controller, RoomListPage page) {
    final current = controller.layoutFor(page);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16 + kSettingsIconSlot + kSettingsIconGap, 0, 16, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          key: ValueKey('room-list-layout-${page.name}'),
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (layout, label) in [
              (RoomCardLayout.compact, i18n('room_card_layout_compact')),
              (RoomCardLayout.cover, i18n('room_card_layout_cover')),
            ])
              ChoiceChip(
                key: ValueKey('room-list-layout-${page.name}-${layout.name}'),
                label: Text(label),
                selected: current == layout,
                onSelected: (_) => controller.setLayoutFor(page, layout),
              ),
          ],
        ),
      ),
    );
  }

  Widget _layoutModeChip(
    RoomCardSettingsController controller,
    RoomCardAppearance config,
    RoomCardLayout layout,
    String label,
  ) {
    return ChoiceChip(
      key: ValueKey('room-card-layout-${layout.name}'),
      label: Text(label),
      selected: config.layout == layout,
      onSelected: (_) => controller.editingLayout.value = layout,
    );
  }

  Widget _platformModeChip(
    RoomCardSettingsController controller,
    RoomCardAppearance config,
    RoomCardPlatformBadgeMode mode,
    String label,
  ) {
    return ChoiceChip(
      key: ValueKey('room-card-platform-${mode.name}'),
      label: Text(label),
      selected: config.platformBadgeMode == mode,
      onSelected: (_) => controller.updateConfig(config.withPlatformBadgeMode(mode)),
    );
  }
}
