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

      final fresh = <T>[];

      final seen = replaceSnapshot ? <T>{} : <T>{...list};

      final int target = pageSize.value;

      var exhausted = false;
      var requestCount = 0;
      var noProgressCount = 0;

      // Every new item of each server page is kept: taking part of a page and
      // then moving past its tail dropped rooms. The list ends only when the
      // source does - an empty page, or two pages in a row with nothing new
      // (an API that ignores the page number or wraps around) - not when a
      // page is shorter than the requested size.
      while (fresh.length < target && requestCount < 20) {
        late final List<T> result;

        try {
          // Always the full page size, so page N covers the same rooms
          // however many this load still needs.
          result = await fetchNetworkData(_virtualNetworkPage, target);

          if (isClosed) return;
        } catch (_) {
          if (isClosed) return;

          // A later page may fail without erasing what this load already
          // fetched; that page is retried on the next scroll, since
          // _virtualNetworkPage has not advanced. A first failure still
          // takes the normal error path.
          if (fresh.isEmpty) rethrow;

          break;
        }

        requestCount++;

        if (result.isEmpty) {
          exhausted = true;
          break;
        }

        _virtualNetworkPage++;

        final before = fresh.length;

        for (final item in result) {
          if (seen.add(item)) fresh.add(item);
        }

        if (fresh.length > before) {
          noProgressCount = 0;
        } else if (++noProgressCount >= 2) {
          exhausted = true;
          break;
        }
      }

      canLoadMore.value = !exhausted;

      if (replaceSnapshot) {
        list.assignAll(fresh);
      } else if (fresh.isNotEmpty) {
        list.addAll(fresh);
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
