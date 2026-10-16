import 'dart:async';
import 'dart:math' as math;

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
    ever<bool>(loadding, _onLoadingChanged);
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

  /// How far from the top (or the end) the back-to-top (to-bottom) button
  /// appears. It was 400 with the home page's 80 px bottom bar; the bar is
  /// gone, the lists are that much taller and scroll that much less, so the
  /// buttons kept to 400 showed only on a forced overscroll.
  static const double jumpButtonDistance = 320;

  void _syncScrollFlags() {
    if (!scrollController.hasClients) {
      // Empty and error states have no scroll view: nothing to jump through.
      if (showBackToTop.value) showBackToTop.value = false;
      if (showBackToBottom.value) showBackToBottom.value = false;
      return;
    }
    if (scrollController.positions.length != 1) return;
    onScrollMetrics(scrollController.position);
  }

  /// The vertical list last seen scrolling (see [onScrollNotification]): the
  /// one the jump buttons move.
  ScrollPosition? _seenPosition;

  /// BasePageView reports each scroll of the list on screen here, with the
  /// scrollable's [context].
  void onScrollNotification(ScrollMetrics metrics, BuildContext? context) {
    if (metrics.axis != Axis.vertical) return;
    final scrollable = context == null ? null : Scrollable.maybeOf(context);
    if (scrollable != null && scrollable.position.axis == Axis.vertical) _seenPosition = scrollable.position;
    onScrollMetrics(metrics);
  }

  /// The list the jump buttons act on: the one last seen scrolling while it
  /// is still on screen, else the bound controller's.
  ScrollPosition? get _jumpTarget {
    final seen = _seenPosition;
    if (seen != null && seen.context.storageContext.mounted && seen.hasContentDimensions) return seen;
    final controller = scrollController;
    if (controller.hasClients && controller.positions.length == 1) return controller.position;
    return null;
  }

  /// Sets the jump buttons from a vertical list's [metrics].
  void onScrollMetrics(ScrollMetrics metrics) {
    if (isClosed || metrics.axis != Axis.vertical || !metrics.hasContentDimensions) return;
    final maxScroll = metrics.maxScrollExtent;
    // An overscroll bounce is not a scroll position: it alone used to pass
    // the distance on a short list, so the button showed only while the
    // list was pulled hard past its end.
    final offset = math.max(metrics.minScrollExtent, math.min(metrics.pixels, maxScroll));
    final atEdge = metrics.atEdge;
    // A list that scrolls less than twice the distance shows the buttons
    // halfway through instead of never.
    final reach = math.min(jumpButtonDistance, maxScroll / 2);
    final showTop = maxScroll > 0 && offset > reach;

    if (showTop != showBackToTop.value) showBackToTop.value = showTop;

    if (atEdge && offset > 0) {
      showBackToBottom.value = false;
    } else {
      if (maxScroll - offset > reach) {
        if (!showBackToBottom.value) showBackToBottom.value = true;
      } else {
        if (showBackToBottom.value) showBackToBottom.value = false;
      }
    }
  }

  @override
  void onClose() {
    _headerRetry?.cancel();
    scrollController.removeListener(_scrollListener);
    _boundScrollController = null;
    _seenPosition = null;
    _ownedScrollController.dispose();
    easyRefreshController.dispose();
    super.onClose();
  }

  void finishRefreshControllers(IndicatorResult result) {
    _lastLoadFailure = result == IndicatorResult.fail ? DateTime.now() : null;
    easyRefreshController.finishRefresh(
      result == IndicatorResult.fail ? IndicatorResult.fail : IndicatorResult.success,
    );
    easyRefreshController.finishLoad(result);
  }

  void scrollToBottom() {
    final position = _jumpTarget;
    if (position == null) return;
    final distance = (position.maxScrollExtent - position.pixels).abs();
    position.animateTo(
      position.maxScrollExtent,
      duration: _scrollAnimationDuration(distance),
      curve: Curves.easeOutCubic,
    );
  }

  void scrollToTopOrRefresh() {
    final position = _jumpTarget;
    if (position == null) return;
    if (position.pixels > 0) {
      position.animateTo(
        0,
        duration: _scrollAnimationDuration(position.pixels),
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

  /// True while the pull header shows a refresh, pulled or not: the page's
  /// reload spinner stays hidden (see BasePageView).
  final pullRefreshing = false.obs;

  /// Set by the page: where lists refresh by pulling, every reload shows in
  /// the pull header, pulled or not, and it is the only indicator. Where a
  /// floating refresh button takes the pull's place (desktop), the page's
  /// reload spinner is the only one.
  bool reloadInPullHeader = false;

  /// A refresh already running that a new request joins instead of starting
  /// a second one: pages whose refreshes run outside [loadding] (silent
  /// background passes) report theirs here.
  Future<void>? get runningRefresh => null;

  Timer? _headerRetry;

  int _pullsRunning = 0;

  /// A reload asked the header to drop in; its refresh callback then joins
  /// that reload instead of starting another.
  bool _headerReloadPending = false;

  bool get _reloadRunning => loadding.value && currentPage <= 1;

  void _onLoadingChanged(bool loading) {
    _headerRetry?.cancel();
    _headerRetry = null;
    if (!loading || isClosed || !reloadInPullHeader || pullRefreshing.value || currentPage > 1) return;
    final header = easyRefreshController.headerState;
    if (header == null || header.mode != IndicatorMode.inactive) {
      // The header is still retracting from a pull, being dragged, or not
      // attached yet: wait for it rather than showing a second indicator.
      _headerRetry = Timer(const Duration(milliseconds: 200), () {
        _headerRetry = null;
        if (!isClosed && loadding.value) _onLoadingChanged(true);
      });
      return;
    }
    // A header that pulls the list down would scroll a list read part-way
    // back to the top; the floating ball sits over the list and never does.
    final atTop = scrollController.hasClients && scrollController.offset <= 0;
    if (!header.indicator.clamping && !atTop) return;
    _headerReloadPending = true;
    pullRefreshing.value = true;
    unawaited(
      easyRefreshController.callRefresh().whenComplete(() {
        if (isClosed || _pullsRunning > 0) return;
        final mode = easyRefreshController.headerState?.mode;
        if (mode == IndicatorMode.ready || mode == IndicatorMode.processing) return;
        // The header could not drop in; the reload runs without one.
        _headerReloadPending = false;
        pullRefreshing.value = false;
      }),
    );
  }

  Future<void> _untilLoaded() {
    if (!loadding.value) return Future<void>.value();
    final done = Completer<void>();
    late final Worker worker;
    worker = ever<bool>(loadding, (loading) {
      if (loading || done.isCompleted) return;
      worker.dispose();
      done.complete();
    });
    return done.future;
  }

  /// The refresh behind every pull-to-refresh header. A pull during a
  /// reload joins it: the header spins until that reload ends, then
  /// retracts; no second refresh starts.
  Future<void> pullToRefresh() async {
    final running = runningRefresh;
    final joins = _headerReloadPending || _reloadRunning;
    _headerReloadPending = false;
    _pullsRunning++;
    pullRefreshing.value = true;
    try {
      if (running != null) {
        // One channel: a pull during any refresh, visible or silent, waits
        // for it instead of queueing another.
        await running.catchError((Object _) {});
      } else if (joins) {
        await _untilLoaded();
      } else {
        await refreshData();
      }
    } finally {
      _pullsRunning--;
      if (!isClosed) {
        if (_pullsRunning == 0) pullRefreshing.value = false;
        // Pages whose refresh does not finish the header themselves.
        if (easyRefreshController.headerState?.mode == IndicatorMode.processing) {
          easyRefreshController.finishRefresh();
        }
      }
    }
  }
}
