import 'package:pure_live/core/widgets/refresh_indicators.dart';
import 'package:pure_live/core/index.dart';

extension BasePageViewContentExtension<C extends BasePageScrollAndStateBone<T>, T> on BasePageView<C, T> {
  Widget buildActualContent(BuildContext context) {
    // The pull header and the load-more footer serve every layout: the footer
    // loads the next page as the end of the list scrolls into view, wheel
    // scrolling included, and a mouse can drag the pull header.
    if (wrapMobileRefresh) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final indicators = appRefreshIndicators(context, maxWidth: constraints.maxWidth);
          return Obx(
            () => EasyRefresh(
              header: indicators.header,
              footer: indicators.footer,
              controller: controller.easyRefreshController,
              onRefresh: enableRefresh ? controller.pullRefreshCallback : null,
              // Always wired: the controller ends the list with
              // finishLoad(IndicatorResult.noMore). canLoadMore read here, at
              // layout time, is tracked by no Obx and went stale, leaving the
              // footer without a load callback after the first page.
              onLoad: enableLoadMore ? controller.loadMoreData : null,
              child: contentBuilder(context, controller.list, controller.scrollController),
            ),
          );
        },
      );
    }
    return contentBuilder(context, controller.list, controller.scrollController);
  }

  Widget buildFloatingButtons(BuildContext context) {
    return Obx(() {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: controller.showBackToTop.value ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: FloatingActionButton(
                heroTag: "base_page_view_to_top_${controller.hashCode}",
                mini: true,
                elevation: 3,
                backgroundColor: Theme.of(context).cardColor,
                onPressed: controller.scrollToTopOrRefresh,
                child: const Icon(Icons.arrow_upward_rounded),
              ),
            ),
          ),
          AnimatedScale(
            scale: controller.showBackToBottom.value ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: FloatingActionButton(
              heroTag: "base_page_view_to_bottom_${controller.hashCode}",
              mini: true,
              elevation: 3,
              backgroundColor: Theme.of(context).cardColor,
              onPressed: controller.scrollToBottom,
              child: const Icon(Icons.arrow_downward_rounded),
            ),
          ),
        ],
      );
    });
  }
}
