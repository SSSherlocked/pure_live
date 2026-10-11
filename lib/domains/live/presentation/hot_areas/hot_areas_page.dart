import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/domains/live/presentation/hot_areas/hot_areas_controller.dart';
import 'package:pure_live/domains/live/data/favorite_room_controller.dart';

class HotAreasPage extends GetView<HotAreasController> {
  const HotAreasPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(i18n('platform_display'))),
      body: SettingsContentWidth(child: ListView(
        physics: const PureLiveScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          context.buildGroupTitle(i18n('platform_display')),
          Obx(() {
            if (controller.sites.isEmpty) return const SizedBox.shrink();
            final visibleCount = FavoriteRoomController.to.hotAreasList.length;

            return Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: theme.dividerColor.withValues(alpha: 0.05), width: 0.5),
              ),
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: controller.sites.length,
                onReorderItem: (oldIndex, newIndex) => controller.onReorder(oldIndex, newIndex),
                itemBuilder: (context, index) {
                  final item = controller.sites[index];
                  final bool isShow = controller.isSiteVisible(item.id);

                  Widget buildControls() => Row(
                    key: ValueKey('platform-controls-${item.id}'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        key: ValueKey('platform-switch-${item.id}'),
                        value: isShow,
                        activeThumbColor: theme.colorScheme.primary,
                        onChanged: (bool value) => controller.onChanged(item.id, value),
                      ),
                      if (isShow && visibleCount > 1) ...[
                        const SizedBox(width: 8),
                        Tooltip(
                          message: i18n('drag_to_sort_tip'),
                          child: ReorderableDragStartListener(
                            key: ValueKey('platform-drag-${item.id}'),
                            index: index,
                            child: const SizedBox.square(
                              dimension: kMinInteractiveDimension,
                              child: Center(child: Icon(RemixIcons.sort_asc, size: 20)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  );

                  return Material(
                    key: ValueKey(item.id),
                    color: Colors.transparent,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final title = Text(
                          item.name,
                          key: ValueKey('platform-title-${item.id}'),
                          style: AppTextStyles.t15.copyWith(fontWeight: FontWeight.w600),
                        );
                        final controls = buildControls();
                        final stackControls =
                            constraints.maxWidth < 360 || MediaQuery.textScalerOf(context).scale(1) > 1.5;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          title: stackControls
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [title, const SizedBox(height: 6), controls],
                                )
                              : title,
                          leading: Image.asset(item.logo, width: 24, height: 24),
                          trailing: stackControls ? null : controls,
                        );
                      },
                    ),
                  );
                },
              ),
            );
          }),
          const SizedBox(height: 32),
        ],
      )),
    );
  }
}
