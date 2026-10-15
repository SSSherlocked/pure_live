import 'package:remixicon/remixicon.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/config/room_card_settings_controller.dart';
import 'package:pure_live/domains/live/presentation/widgets/room_card_rows.dart';

class PopularGridView extends StatelessWidget {
  final String tag;
  const PopularGridView(this.tag, {super.key});

  BasePageScrollAndStateBone<LiveRoom> get controller => Get.find<BasePageScrollAndStateBone<LiveRoom>>(tag: tag);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraint) {
        final width = constraint.maxWidth;
        return BasePageView<BasePageScrollAndStateBone<LiveRoom>, LiveRoom>(
          controller: controller,
          // Desktop's floating refresh sits under the scroll buttons.
          wideBottomPadding: AppLayout.of(context).refreshByButton ? FloatingRefreshButton.clearance : null,
          emptyBuilder: (c) => AppStatusView(
            type: AppStatusType.empty,
            icon: RemixIcons.fire_fill,
            title: i18n("empty_live_title"),
            subtitle: i18n("empty_live_subtitle"),
            buttonText: i18n('refresh'),
            onButtonPressed: () => controller.refreshData(),
          ),
          // The rooms in the layout chosen for 热门.
          contentBuilder: (context, list, scrollController) => CustomScrollView(
            controller: scrollController,
            scrollCacheExtent: ScrollCacheExtent.pixels(width > 680 ? 480 : 320),
            semanticChildCount: list.length,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [RoomCardRows(page: RoomListPage.popular, width: width, rooms: list)],
          ),
        );
      },
    );
  }
}
