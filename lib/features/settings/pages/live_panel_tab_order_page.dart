import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/config/live_panel_layout.dart';

/// Reorders the live room side panel sections. Applies to rooms opened after
/// the change; a room that is already open keeps its tabs.
class LivePanelTabOrderPage extends StatelessWidget {
  const LivePanelTabOrderPage({super.key});

  static const Map<LivePanelTab, IconData> _icons = {
    LivePanelTab.danmakuList: Remix.chat_3_line,
    LivePanelTab.superChat: Remix.money_cny_circle_line,
    LivePanelTab.follow: Remix.heart_line,
    LivePanelTab.danmakuSettings: Remix.settings_3_line,
  };

  void _save(List<LivePanelTab> order) {
    SettingsService.to.theme.livePanelTabOrder.v = LivePanelTab.encode(order);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(i18n('live_panel_tab_order')),
        actions: [
          TextButton(
            onPressed: () => _save(LivePanelTab.defaultOrder),
            child: Text(i18n('reset_default')),
          ),
        ],
      ),
      body: SettingsContentWidth(child: Obx(() {
        final order = SettingsService.to.theme.resolvedLivePanelTabOrder;
        return ReorderableListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  leading: Icon(_icons[tab], color: theme.colorScheme.primary),
                  title: Text(i18n(tab.labelKey)),
                  trailing: ReorderableDragStartListener(
                    index: index,
                    child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle_rounded)),
                  ),
                ),
              ),
            );
          },
        );
      })),
    );
  }
}
