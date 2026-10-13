import 'dart:async';

import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/pagination/base_controller.dart';

abstract class BasePageScrollAndStateBone<T> extends BaseController {
  final ScrollController _ownedScrollController = createPureLiveScrollController();
  ScrollController? _boundScrollController;

  /// Scroll position used by the jump buttons and their visibility flags.
  ///
  /// A tabbed view can bind one dedicated controller for its active tab. This
  /// keeps every PageView child on a unique ScrollController while preserving
  /// the shared paging actions.
  ScrollController get scrollController => _boundScrollController ?? _ownedScrollController;
  final EasyRefreshController easyRefreshController = EasyRefreshController(
    controlFinishRefresh: true,
    controlFinishLoad: true,
  );

  int currentPage = 1;
  final pageSize = 20.obs;
  final canLoadMore = false.obs;
  final list = <T>[].obs;
  final totalCount = Rxn<int>();

  final showBackToTop = false.obs;
  final showBackToBottom = false.obs;

  BasePageScrollAndStateBone() {
    _ownedScrollController.addListener(_scrollListener);
    // Content changes the scroll extent without a scroll event; re-evaluate
    // the jump buttons once the new list has been laid out.
    ever<List<T>>(
      list,
      (_) => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (isClosed) return;
        _syncScrollFlags();
        _loadMoreNearEnd();
      }),
    );
  }

  void bindActiveScrollController(ScrollController? externalController) {
    if (isClosed) return;
    final previous = scrollController;
    if (identical(previous, externalController) ||
        (externalController == null && identical(previous, _ownedScrollController))) {
      return;
    }
    previous.removeListener(_scrollListener);
    _boundScrollController = externalController;
    scrollController.addListener(_scrollListener);
    _syncScrollFlags();
  }

  void _scrollListener() {
    _syncScrollFlags();
    _loadMoreNearEnd();
  }

  /// Every list scrolls on without end: the next page loads once less than
  /// [loadMoreLead] viewports remain below, so it is usually in before the
  /// end is reached. It runs on scrolling and after each page is laid out,
  /// so a page that does not fill a tall window keeps loading until the list
  /// overflows it. It stops when the source runs out or a request fails (a
  /// failure leaves its retry to the user). The list views' refresh footers
  /// never carried a load callback, so this is what loads pages.
  void _loadMoreNearEnd() {
    if (!canLoadMore.value || loadding.value || pageError.value || notLogin.value) return;
    // A failed page is not retried on every scroll tick.
    final failedAt = _lastLoadFailure;
    if (failedAt != null && DateTime.now().difference(failedAt) < loadMoreRetryDelay) return;
    final controller = scrollController;
    if (!controller.hasClients || controller.positions.length != 1) return;
    final position = controller.position;
    if (!position.hasContentDimensions || !position.hasViewportDimension) return;
    if (position.extentAfter > position.viewportDimension * loadMoreLead) return;
    unawaited(loadMoreData());
  }

  /// How many viewports from the end the next page starts loading.
  static const double loadMoreLead = 1;

  /// How long scrolling waits before loading again after a failed load.
  static const Duration loadMoreRetryDelay = Duration(seconds: 5);

  DateTime? _lastLoadFailure;

  void _syncScrollFlags() {
    if (!scrollController.hasClients) {
      // Empty and error states have no scroll view: nothing to jump through.
      if (showBackToTop.value) showBackToTop.value = false;
      if (showBackToBottom.value) showBackToBottom.value = false;
      return;
    }
    final offset = scrollController.offset;
    final position = scrollController.position;
    final maxScroll = position.maxScrollExtent;

    if (offset > 400 && !showBackToTop.value) {
      showBackToTop.value = true;
    } else if (offset <= 400 && showBackToTop.value) {
      showBackToTop.value = false;
    }

    if (position.atEdge && offset > 0) {
      showBackToBottom.value = false;
    } else {
      if (maxScroll - offset > 400) {
        if (!showBackToBottom.value) showBackToBottom.value = true;
      } else {
        if (showBackToBottom.value) showBackToBottom.value = false;
      }
    }
  }

  @override
  void onClose() {
    scrollController.removeListener(_scrollListener);
    _boundScrollController = null;
    _ownedScrollController.dispose();
    easyRefreshController.dispose();
    super.onClose();
  }

  void scrollToTopImmediate() {
    if (scrollController.hasClients) {
      scrollController.jumpTo(0);
    }
  }

  void finishRefreshControllers(IndicatorResult result) {
    _lastLoadFailure = result == IndicatorResult.fail ? DateTime.now() : null;
    easyRefreshController.finishRefresh(
      result == IndicatorResult.fail ? IndicatorResult.fail : IndicatorResult.success,
    );
    easyRefreshController.finishLoad(result);
  }

  void scrollToBottom() {
    if (!scrollController.hasClients) return;
    final distance = (scrollController.position.maxScrollExtent - scrollController.offset).abs();
    scrollController.animateTo(
      scrollController.position.maxScrollExtent,
      duration: _scrollAnimationDuration(distance),
      curve: Curves.easeOutCubic,
    );
  }

  void scrollToTopOrRefresh() {
    if (!scrollController.hasClients) return;
    if (scrollController.offset > 0) {
      scrollController.animateTo(
        0,
        duration: _scrollAnimationDuration(scrollController.offset),
        curve: Curves.easeOutCubic,
      );
    } else {
      easyRefreshController.callRefresh();
    }
  }

  Duration _scrollAnimationDuration(double distance) {
    return Duration(milliseconds: (180 + distance / 8).round().clamp(220, 520));
  }

  Future<void> loadMoreData() async {
    if (loadding.value) return;
    if (!canLoadMore.value) {
      // A footer that fires after the end (once a pull-to-refresh reset its
      // no-more state) must be settled: with controlFinishLoad it would spin
      // forever and also block the pull header.
      easyRefreshController.finishLoad(IndicatorResult.noMore);
      return;
    }
    currentPage++;
    await loadData();
  }

  Future<void> loadData();

  /// Default retry retains the legacy refresh behavior. Native-cursor pagers
  /// can resume the failed action without restarting already consumed pages.
  Future<void> retryData() => refreshData();
  String get retryActionLabel => i18n('retry');
  bool get showInlineError => false;
  String? get pageNotice => null;
  Future<void> refreshData();

  /// True while a pull-to-refresh runs: its header is the one spinner shown,
  /// so the page's own reload spinner stays hidden (see BasePageView).
  final pullRefreshing = false.obs;

  /// The refresh behind every pull-to-refresh header.
  Future<void> pullToRefresh() async {
    pullRefreshing.value = true;
    try {
      await refreshData();
    } finally {
      if (!isClosed) pullRefreshing.value = false;
    }
  }
}
