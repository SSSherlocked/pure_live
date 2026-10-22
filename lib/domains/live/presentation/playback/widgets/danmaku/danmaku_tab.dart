import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/widgets/calm_tab_bar_view.dart';
import 'package:pure_live/core/widgets/keep_alive_wrapper.dart';
import 'package:pure_live/core/player/presentation/danmaku/danmaku_surface_settings.dart';
import 'package:pure_live/core/config/live_panel_layout.dart';
import 'package:pure_live/domains/live/presentation/playback/pages/super_chat_page.dart';
import 'package:pure_live/domains/live/presentation/playback/pages/keyword_block_page.dart';
import 'package:pure_live/domains/live/presentation/playback/pages/follow_rooms_page.dart';
import 'package:pure_live/domains/live/presentation/playback/pages/danmaku_settings_page.dart';
import 'package:pure_live/domains/live/presentation/playback/controllers/live_play_controller.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/danmaku/danmaku_list_view.dart';

class DanmakuTabView extends GetView<LivePlayController> {
  const DanmakuTabView({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final state = controller.state.value;
      final detail = state.room.detail;
      // The player's settings while live; typed as the shared source so the
      // fallback below unifies with it.
      final DanmakuSettingsSource? playerSettings = state.player.videoController;
      // The tab bar and every section stay mounted while a room switch
      // reloads: only the sections that need the new room show a loading
      // state, so the 关注 list never blanks out during the switch.
      Widget loading() => AppStatusView(type: AppStatusType.loading, title: "", subtitle: "");
      // The side panel is a dense surface: every text role one step smaller
      // (the chat list keeps its own size setting).
      return CompactText(
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            children: [
              DanmakuSectionTabBar(controller: controller.tabController, tabs: controller.tabs),
              Expanded(
                child: CalmTabBarView(
                  controller: controller.tabController,
                  physics: const PureLiveBoundedScrollPhysics(),
                  children: [
                    for (final tab in controller.panelTabs)
                      switch (tab) {
                        LivePanelTab.danmakuList =>
                          SettingsService.to.danmaku.hideDanmaku.v
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(i18n('danmaku_display_disabled_hint'), textAlign: TextAlign.center),
                                  ),
                                )
                              : detail == null
                              ? loading()
                              // Kept alive: TabBarView drops an off-screen
                              // page, and a new chat list has to build and
                              // lay out every message above the restored or
                              // live-tail offset to reach it (row heights are
                              // unknown until laid out). In the frame a swipe
                              // from 付费留言 first showed it, that hitched
                              // the swipe, the longer the more messages.
                              : KeepAliveWrapper(child: DanmakuListView(room: detail, controller: controller)),
                        // RxList mutations do not invalidate this outer Obx unless
                        // its value is read while building. Snapshot it here so new
                        // SC entries appear immediately without switching tabs.
                        LivePanelTab.superChat => Obx(
                          () => SuperChatPage(messages: controller.superChats.toList(growable: false)),
                        ),
                        // 屏蔽管理 closes the page as its last section. A room
                        // with no player (not live) edits the same global
                        // settings directly, so the tab always has content.
                        LivePanelTab.danmakuSettings => DanmakuSettingsPage(
                          controller: playerSettings ?? const SettingsDanmakuSource(),
                          footer: const KeywordBlockPage(),
                        ),
                        LivePanelTab.follow => FollowRoomsPage(
                          key: const ValueKey('live-panel-follow'),
                          controller: controller,
                        ),
                      },
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// The room panel sections are navigation, not a free-scrolling chip
/// strip. Giving them equal bounded widths keeps the row fixed while the
/// associated [TabBarView] remains swipeable between its first and last page.
class DanmakuSectionTabBar extends StatelessWidget {
  const DanmakuSectionTabBar({super.key, required this.tabs, this.controller});

  final List<String> tabs;
  final TabController? controller;

  // The labels sit centred between the divider above the bar and the one
  // under it, a touch high (1.5 px) for optical balance: the space above a
  // label is 3 px less than everything below it (the space under the label,
  // the indicator strip and the divider). The indicator is drawn 4 px under
  // the text, not at the bottom of the strip.
  static const double _labelTopSpace = 8;
  static const double _labelBottomSpace = 7;
  static const double _indicatorGap = 4;
  static const double _indicatorThickness = 3;
  static const double _dividerThickness = 1;
  static const double _indicatorStrip = _indicatorThickness + _dividerThickness;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // One role above the list text: the section names lead the panel.
    // Bold whether selected or not; the colour marks the current tab.
    final labelStyle = AppText.of(context).sectionTitle.copyWith(fontWeight: FontWeight.w700);
    // A tab is exactly the tallest label plus the space above and below it;
    // TabBar adds the indicator strip (with the divider) under the tabs.
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    var labelHeight = 0.0;
    for (final name in tabs) {
      final painter = TextPainter(
        text: TextSpan(text: name, style: labelStyle),
        textScaler: textScaler,
        textDirection: textDirection,
        maxLines: 1,
      )..layout();
      if (painter.height > labelHeight) labelHeight = painter.height;
      painter.dispose();
    }
    final tabHeight = _labelTopSpace + labelHeight + _labelBottomSpace;
    return Container(
      color: theme.colorScheme.surface,
      child: ScrollableTabBar(
        key: const ValueKey('live-danmaku-section-tabs'),
        isScrollable: false,
        tabAlignment: TabAlignment.fill,
        physics: const PureLiveBoundedScrollPhysics(),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        labelStyle: labelStyle,
        unselectedLabelStyle: labelStyle,
        indicatorWeight: _indicatorStrip,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(width: _indicatorThickness, color: theme.colorScheme.primary),
          borderRadius: const BorderRadius.all(Radius.circular(1.5)),
          // Raised from the bottom of the bar to [_indicatorGap] under the
          // text, clear of the divider.
          insets: const EdgeInsets.only(
            bottom: _labelBottomSpace + _indicatorStrip - _indicatorGap - _indicatorThickness,
          ),
        ),
        // The same faint line as the divider above the bar.
        dividerColor: dividerLineColor(theme.colorScheme),
        dividerHeight: _dividerThickness,
        controller: controller,
        // Five equal-width sections share a narrow panel: shrink a label that
        // does not fit instead of letting neighbouring labels overlap.
        tabs: tabs
            .map(
              (name) => Tab(
                height: tabHeight,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  // As wide as the label, so the indicator matches it.
                  widthFactor: 1,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: _labelBottomSpace),
                    child: FittedBox(fit: BoxFit.scaleDown, child: Text(name, maxLines: 1, softWrap: false)),
                  ),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}
