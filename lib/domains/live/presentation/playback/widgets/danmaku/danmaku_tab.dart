import 'package:pure_live/core/index.dart';
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
      final videoController = state.player.videoController;
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
                child: TabBarView(
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
                              : DanmakuListView(room: detail, controller: controller),
                        // RxList mutations do not invalidate this outer Obx unless
                        // its value is read while building. Snapshot it here so new
                        // SC entries appear immediately without switching tabs.
                        LivePanelTab.superChat => Obx(
                          () => SuperChatPage(messages: controller.superChats.toList(growable: false)),
                        ),
                        // 屏蔽管理 closes the page as its last section.
                        LivePanelTab.danmakuSettings =>
                          videoController == null
                              ? loading()
                              : DanmakuSettingsPage(
                                  controller: videoController,
                                  footer: const KeywordBlockPage(asSection: true),
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

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: ScrollableTabBar(
        key: const ValueKey('live-danmaku-section-tabs'),
        isScrollable: false,
        tabAlignment: TabAlignment.fill,
        physics: const PureLiveBoundedScrollPhysics(),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        // One role above the list text: the section names lead the panel.
        labelStyle: AppText.of(context).sectionTitle.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: AppText.of(context).sectionTitle.copyWith(fontWeight: FontWeight.w500),
        controller: controller,
        // Five equal-width sections share a narrow panel: shrink a label that
        // does not fit instead of letting neighbouring labels overlap.
        tabs: tabs
            .map(
              (name) => Tab(
                child: FittedBox(fit: BoxFit.scaleDown, child: Text(name, maxLines: 1, softWrap: false)),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}
