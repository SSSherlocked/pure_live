import 'dart:async';

import 'package:pure_live/core/index.dart';

abstract class ServerRemotePageController<T> extends BasePageScrollAndStateBone<T> {
  int _virtualNetworkPage = 1;
  Future<void>? _activeLoad;
  bool _refreshPending = false;

  ServerRemotePageController() : super();

  Future<List<T>> fetchNetworkData(int page, int pageSize);

  @override
  Future<void> refreshData() async {
    if (isClosed) return;

    _refreshPending = true;

    while (_activeLoad != null && !isClosed) {
      await _activeLoad;
    }

    if (!_refreshPending || isClosed) {
      // Another caller already took this refresh request and started the load:
      // wait for that load instead of returning while it runs, so a pull's
      // header spins until the page is fresh and the page's own reload
      // spinner never shows beside it.
      final joined = _activeLoad;
      if (joined != null && !isClosed) await joined;
      return;
    }

    _refreshPending = false;
    currentPage = 1;
    _virtualNetworkPage = 1;

    await _startLoad(replaceSnapshot: true);
  }

  @override
  Future<void> loadData() async {
    final active = _activeLoad;

    if (active != null) {
      return active;
    }

    if (isClosed) return;

    return _startLoad();
  }

  @override
  Future<void> loadMoreData() async {
    if (isClosed) return;

    final active = _activeLoad;

    if (active != null) {
      return active;
    }

    await super.loadMoreData();
  }

  Future<void> _startLoad({bool replaceSnapshot = false}) {
    final active = _activeLoad;

    if (active != null) {
      return active;
    }

    late final Future<void> operation;

    operation = _performLoad(replaceSnapshot: replaceSnapshot).whenComplete(() {
      if (identical(_activeLoad, operation)) {
        _activeLoad = null;
      }
    });

    _activeLoad = operation;

    return operation;
  }

  Future<void> _performLoad({required bool replaceSnapshot}) async {
    final bool isNetworkSafe = await checkNetworkBeforeRequest();

    if (isClosed) return;

    if (!isNetworkSafe) {
      finishRefreshControllers(IndicatorResult.fail);
      return;
    }

    final int previousPageSnapshot = currentPage;

    try {
      loadding.value = true;
      pageError.value = false;
      pageEmpty.value = false;
      notLogin.value = false;

      if (list.isEmpty) {
        pageLoadding.value = true;
      }

      final combinedResult = <T>[];

      final seen = replaceSnapshot ? <T>{} : <T>{...list};

      final int sizeToFetch = pageSize.value;

      var requestCount = 0;
      var noProgressCount = 0;

      while (combinedResult.length < sizeToFetch && requestCount < 20 && noProgressCount < 2) {
        final int neededCount = sizeToFetch - combinedResult.length;

        late final List<T> result;

        try {
          result = await fetchNetworkData(_virtualNetworkPage, neededCount);

          if (isClosed) return;
        } catch (_) {
          if (isClosed) return;

          // A later cursor/page is allowed to fail without erasing items that
          // the same transaction has already fetched successfully. This is
          // common with APIs that protect deeper pagination more aggressively
          // than their first page and with transient mobile network changes.
          // The partial page is committed below with canLoadMore=false; an
          // initial request failure still follows the normal error path.
          if (combinedResult.isEmpty) {
            rethrow;
          }

          break;
        }

        requestCount++;

        if (result.isEmpty) {
          break;
        }

        final previousLength = combinedResult.length;

        for (final item in result) {
          if (seen.add(item)) {
            combinedResult.add(item);
          }

          if (combinedResult.length >= sizeToFetch) {
            break;
          }
        }

        noProgressCount = combinedResult.length == previousLength ? noProgressCount + 1 : 0;

        _virtualNetworkPage++;
      }

      if (combinedResult.isEmpty && currentPage > 1) {
        canLoadMore.value = false;

        finishRefreshControllers(IndicatorResult.noMore);

        return;
      }

      canLoadMore.value = combinedResult.length >= pageSize.value;

      if (replaceSnapshot) {
        list.assignAll(combinedResult);
      } else {
        list.addAll(combinedResult);
      }

      pageEmpty.value = list.isEmpty;

      finishRefreshControllers(canLoadMore.value ? IndicatorResult.success : IndicatorResult.noMore);
    } catch (e) {
      if (isClosed) return;

      currentPage = previousPageSnapshot;

      handleError(e, showPageError: list.isEmpty);

      finishRefreshControllers(IndicatorResult.fail);
    } finally {
      if (!isClosed) {
        loadding.value = false;
        pageLoadding.value = false;
      }
    }
  }
}
