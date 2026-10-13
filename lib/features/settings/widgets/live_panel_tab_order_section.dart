import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/config/live_panel_layout.dart';

/// Reorders the live room side panel sections and switches them on or off.
/// Applies to rooms opened after the change; a room that is already open
/// keeps its tabs. Only here: the room's own 设置 tab does not offer it.
///
/// Listed inline in 通用 › 直播间侧栏, so the reorderable list shrink-wraps
/// and leaves scrolling to the page.
class LivePanelTabOrderSection extends StatelessWidget {
  const LivePanelTabOrderSection({super.key});

  static const Map<LivePanelTab, IconData> _icons = {
    LivePanelTab.danmakuList: Remix.chat_3_line,
    LivePanelTab.superChat: Remix.money_cny_circle_line,
    LivePanelTab.follow: Remix.heart_line,
    LivePanelTab.danmakuSettings: Remix.settings_3_line,
  };

  void _save(List<LivePanelTab> order) {
    SettingsService.to.theme.livePanelTabOrder.v = LivePanelTab.encode(order);
  }

  void _setShown(LivePanelTab tab, bool shown) {
    final hidden = {...SettingsService.to.theme.hiddenLivePanelTabs};
    shown ? hidden.remove(tab) : hidden.add(tab);
    SettingsService.to.theme.livePanelHiddenTabs.v = LivePanelTab.encode(
      LivePanelTab.defaultOrder.where(hidden.contains),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: context.buildGroupTitle(i18n('live_panel_tab_order'))),
            TextButton(
              key: const ValueKey('live-panel-tab-order-reset'),
              onPressed: () {
                _save(LivePanelTab.defaultOrder);
                SettingsService.to.theme.livePanelHiddenTabs.v = '';
              },
              child: Text(i18n('reset_default')),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Text(
            i18n('live_panel_tab_order_subtitle'),
            style: AppText.of(context).secondary.copyWith(color: theme.hintColor),
          ),
        ),
        Obx(() {
          final order = SettingsService.to.theme.resolvedLivePanelTabOrder;
          final hidden = SettingsService.to.theme.hiddenLivePanelTabs;
          final shownCount = order.where((tab) => !hidden.contains(tab)).length;
          return ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            buildDefaultDragHandles: false,
            itemCount: order.length,
            onReorder: (oldIndex, newIndex) {
              final next = [...order];
              if (newIndex > oldIndex) newIndex -= 1;
              next.insert(newIndex, next.removeAt(oldIndex));
              _save(next);
            },
            itemBuilder: (context, index) {
              final tab = order[index];
              final shown = !hidden.contains(tab);
              return Padding(
                key: ValueKey('live-panel-tab-${tab.id}'),
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: theme.colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: .55)),
                  ),
                  child: ListTile(
                    leading: Icon(
                      _icons[tab],
                      color: shown ? theme.colorScheme.primary : theme.disabledColor,
                    ),
                    title: Text(i18n(tab.labelKey)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // The panel keeps at least one section.
                        Switch(
                          key: ValueKey('live-panel-tab-shown-${tab.id}'),
                          value: shown,
                          onChanged: shown && shownCount <= 1 ? null : (on) => _setShown(tab, on),
                        ),
                        ReorderableDragStartListener(
                          index: index,
                          child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle_rounded)),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        }),
      ],
    );
  }
}
