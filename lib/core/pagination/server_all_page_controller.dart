import 'dart:async';

import 'package:pure_live/core/index.dart';

abstract class ServerAllPageController<T> extends BasePageScrollAndStateBone<T> {
  List<T>? _rawAllData;
  Future<void>? _activeLoad;
  bool _refreshPending = false;

  /// Includes the connectivity preflight before the visible loading flag is
  /// set. Local projections must not complete this operation's indicator.
  bool get hasActiveLoad => _activeLoad != null;

  Future<List<T>> fetchAllServerData();

  @override
  Future<void> refreshData() async {
    if (isClosed) return;
    _refreshPending = true;
    final active = _activeLoad;
    if (active != null) await active;
    if (!_refreshPending || isClosed) return;
    _refreshPending = false;
    _rawAllData = null;
    currentPage = 1;
    await _startLoad();
  }

  @override
  Future<void> loadData() async {
    final active = _activeLoad;
    if (active != null) return active;
    if (isClosed) return;
    return _startLoad();
  }

  @override
  Future<void> loadMoreData() async {
    if (isClosed) return;
    await super.loadMoreData();
  }

  Future<void> _startLoad() {
    final active = _activeLoad;
    if (active != null) return active;
    late final Future<void> operation;
    operation = _performLoad().whenComplete(() {
      if (identical(_activeLoad, operation)) _activeLoad = null;
    });
    _activeLoad = operation;
    return operation;
  }

  Future<void> _performLoad() async {
    if (_rawAllData != null) {
      processLocalPaging();
      return;
    }

    final bool isNetworkSafe = await checkNetworkBeforeRequest();
    if (isClosed) return;
    if (!isNetworkSafe) {
      finishRefreshControllers(IndicatorResult.fail);
      return;
    }

    try {
      loadding.value = true;
      pageError.value = false;
      pageEmpty.value = false;
      notLogin.value = false;
      pageLoadding.value = true;

      final result = await fetchAllServerData();
      // The Future has no cancellation contract. Observe its terminal result,
      // but never publish into a route whose controllers have been disposed.
      if (isClosed) return;
      _rawAllData = result;
      processLocalPaging();
    } catch (e) {
      if (isClosed) return;
      handleError(e, showPageError: list.isEmpty);
      finishRefreshControllers(IndicatorResult.fail);
    } finally {
      if (!isClosed) {
        loadding.value = false;
        pageLoadding.value = false;
      }
    }
  }

  void processLocalPaging() {
    if (isClosed || _rawAllData == null) return;
    final allItems = _rawAllData!;
    totalCount.value = allItems.length;

    if (allItems.isEmpty) {
      list.clear();
      canLoadMore.value = false;
      pageEmpty.value = true;
      finishRefreshControllers(IndicatorResult.noMore);
      return;
    }

    list.assignAll(allItems);
    canLoadMore.value = false;
    pageEmpty.value = list.isEmpty;
    finishRefreshControllers(IndicatorResult.noMore);
  }
}
