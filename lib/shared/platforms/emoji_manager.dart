import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart' show CancelToken;
import 'package:flame_barrage/flame_barrage.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/core/logging/core_log.dart';
import 'package:pure_live/core/network/core_error.dart';
import 'package:pure_live/core/network/http_client.dart';
import 'package:pure_live/core/platform/app_path_manager.dart';
import 'package:pure_live/core/storage/hive_pref_util.dart';
import 'package:pure_live/shared/platforms/danmaku_emoji.dart';
import 'package:pure_live/shared/platforms/danmaku_emoji_cache.dart';

/// Fills [EmojiAtlas] with the danmaku emoji of one platform.
///
/// Only the emoji lists ship with the app (`assets/emo/json/<platform>.json`);
/// the images are fetched from the CDN URL in the list the first time they are
/// needed and kept under `EMOJI_CACHE/<platform>/`, so a later visit to the
/// same platform only decodes local files. The list itself is refreshed from
/// the repository at most once a week and the refreshed copy, when there is
/// one, replaces the bundled seed on the next load.
///
/// [preload] returns as soon as the list is parsed; images are decoded and
/// registered in the background in small batches, so danmaku shows an emoji
/// as soon as it is ready and the text code until then.
class EmojiManager {
  static final EmojiManager instance = EmojiManager._internal();
  factory EmojiManager() => instance;
  EmojiManager._internal();

  static const int _emojiSize = 24;
  static const int _maxInFlight = 6;
  static const int _registerBatchSize = 8;
  static const int _maxFailedUrls = 1024;
  static const int _maxConsecutiveFailures = 12;
  static const Duration _downloadTimeout = Duration(seconds: 15);
  static const Duration _listRefreshInterval = Duration(days: 7);
  static const String _listCheckedPrefKey = 'danmaku_emoji_list_checked_at_';

  String? _loadedPlatform;
  String? _loadingPlatform;
  int _loadGeneration = 0;

  /// URLs that answered with an error or with bytes that are not an image. They
  /// are skipped for the rest of the session instead of being retried in every
  /// room; connection failures and timeouts are not remembered.
  final Set<String> _failedUrls = <String>{};
  final Set<String> _refreshingLists = <String>{};

  /// Clears the atlas and starts loading [platform]'s emoji into it.
  ///
  /// A platform that is already loaded, or still loading, is left alone.
  /// [onAtlasChanged] runs after the atlas is cleared and after every batch of
  /// emoji is registered, so a caller can drop anything it derived from the
  /// previous atlas contents.
  Future<void> preload(String platform, DanmakuEmojiParser? parser, {void Function()? onAtlasChanged}) async {
    if (_loadedPlatform == platform || _loadingPlatform == platform) return;
    final generation = ++_loadGeneration;
    _loadingPlatform = platform;
    _loadedPlatform = null;

    EmojiAtlas.instance.clear();
    onAtlasChanged?.call();
    if (parser == null) {
      _loadingPlatform = null;
      return;
    }

    try {
      final cacheDir = await AppPathManager().emojiCacheDir;
      if (generation != _loadGeneration) return;
      final list = await _loadList(platform, parser, cacheDir);
      if (generation != _loadGeneration) return;
      unawaited(_loadImages(platform, list, cacheDir, generation, onAtlasChanged));
      unawaited(_refreshList(platform, parser, cacheDir));
    } catch (_) {
      // Most platforms have no emoji list at all; that is not worth a log line.
      if (generation == _loadGeneration) _loadingPlatform = null;
    }
  }

  void release() {
    _loadGeneration++;
    _loadingPlatform = null;
    _loadedPlatform = null;
    EmojiAtlas.instance.clear();
  }

  /// The refreshed list from the cache directory when it is present and still
  /// parses to something, else the seed bundled with the app.
  Future<List<UnifiedEmojiModel>> _loadList(String platform, DanmakuEmojiParser parser, Directory cacheDir) async {
    final refreshed = File(p.join(cacheDir.path, '$platform.json'));
    try {
      if (await refreshed.exists()) {
        final list = parseDanmakuEmojiList(await refreshed.readAsString(), parser);
        if (list.isNotEmpty) return list;
      }
    } catch (error) {
      CoreLog.w('danmaku emoji list in cache unusable ($platform): $error');
    }
    return parseDanmakuEmojiList(await rootBundle.loadString('assets/emo/json/$platform.json'), parser);
  }

  Future<void> _loadImages(
    String platform,
    List<UnifiedEmojiModel> list,
    Directory cacheDir,
    int generation,
    void Function()? onAtlasChanged,
  ) async {
    final pending = <_LoadedEmoji>[];
    try {
      // One image can stand behind several codes; fetch and decode it once.
      final byUrl = <String, List<UnifiedEmojiModel>>{};
      for (final model in list) {
        if (model.url.isEmpty || model.keys.isEmpty) continue;
        byUrl.putIfAbsent(model.url, () => <UnifiedEmojiModel>[]).add(model);
      }
      final entries = byUrl.entries.toList(growable: false);
      final platformDir = Directory(p.join(cacheDir.path, platform));
      try {
        await platformDir.create(recursive: true);
      } catch (error) {
        // Downloads still work, they just cannot be kept for the next visit.
        CoreLog.w('danmaku emoji cache directory unavailable ($platform): $error');
      }
      if (generation != _loadGeneration) return;

      var next = 0;
      var consecutiveFailures = 0;
      var aborted = false;

      Future<void> worker() async {
        while (next < entries.length && !aborted) {
          if (generation != _loadGeneration) return;
          final entry = entries[next++];
          final file = File(p.join(platformDir.path, danmakuEmojiCacheFileName(entry.value.first)));
          final image = await _loadImage(platform, file, entry.key, generation);
          if (generation != _loadGeneration) {
            image?.dispose();
            return;
          }
          if (image == null) {
            // A URL remembered as dead says nothing about the network; a run of
            // other failures means it is down, so stop hammering it and let
            // the next room on this platform try again.
            if (!_failedUrls.contains(entry.key) && ++consecutiveFailures >= _maxConsecutiveFailures) {
              aborted = true;
            }
            continue;
          }
          consecutiveFailures = 0;
          pending.add(_LoadedEmoji(file: file, models: entry.value, image: image));
          if (pending.length >= _registerBatchSize) {
            _register(pending, onAtlasChanged);
            // Yield between small groups instead of saturating every core and
            // starving route/scroll frames.
            await Future<void>.delayed(Duration.zero);
          }
        }
      }

      await Future.wait(List<Future<void>>.generate(_maxInFlight, (_) => worker()));
      if (generation != _loadGeneration) return;
      if (pending.isNotEmpty) _register(pending, onAtlasChanged);
      if (aborted) {
        CoreLog.w('danmaku emoji download for $platform stopped after repeated network failures');
      } else {
        _loadedPlatform = platform;
      }
      _loadingPlatform = null;
    } catch (error, stackTrace) {
      CoreLog.e('danmaku emoji load failed ($platform): $error', stackTrace);
      if (generation == _loadGeneration) _loadingPlatform = null;
    } finally {
      // Whatever was decoded but never handed to the atlas belongs to nobody.
      for (final item in pending) {
        item.image.dispose();
      }
      pending.clear();
    }
  }

  /// Registers [loaded] with the atlas in one go and hands over the images;
  /// [loaded] is emptied because the atlas now owns them.
  void _register(List<_LoadedEmoji> loaded, void Function()? onAtlasChanged) {
    final atlas = EmojiAtlas.instance;
    final infos = <EmojiInfo>[
      for (final item in loaded)
        EmojiInfo(
          id: p.basenameWithoutExtension(item.file.path),
          asset: item.file.path,
          keys: <String>[for (final model in item.models) ...model.keys],
          sourceType: EmojiSourceType.asset,
          width: item.image.width.toDouble(),
          height: item.image.height.toDouble(),
        ),
    ];
    // One regex rebuild per batch; registering emoji one by one was quadratic.
    atlas.registerAll(infos);
    for (var index = 0; index < infos.length; index++) {
      atlas.resolveLoadedImage(infos[index], loaded[index].image);
    }
    loaded.clear();
    onAtlasChanged?.call();
  }

  /// The decoded emoji, from [file] when it is there and else from [url] (the
  /// bytes are kept in [file] for next time). `null` when neither worked.
  Future<ui.Image?> _loadImage(String platform, File file, String url, int generation) async {
    final cached = await _readQuietly(file);
    if (generation != _loadGeneration) return null;
    if (cached != null) {
      final image = await _decode(cached);
      if (image != null) return image;
      // Truncated or otherwise unreadable: fetch it again.
      await _deleteQuietly(file);
      if (generation != _loadGeneration) return null;
    }

    if (_failedUrls.contains(url)) return null;
    final bytes = await _download(url, platform);
    if (bytes == null || generation != _loadGeneration) return null;
    final image = await _decode(bytes);
    if (image == null) {
      _rememberFailure(url);
      return null;
    }
    if (generation != _loadGeneration) {
      image.dispose();
      return null;
    }
    try {
      await _writeAtomically(file, bytes);
    } catch (error) {
      CoreLog.w('danmaku emoji cache write failed (${file.path}): $error');
    }
    return image;
  }

  Future<Uint8List?> _download(String url, String platform) async {
    final cancel = CancelToken();
    try {
      final bytes = await HttpClient.instance
          .getBytes(url, header: danmakuEmojiDownloadHeaders(platform), cancel: cancel)
          .timeout(_downloadTimeout);
      if (bytes.isNotEmpty) return bytes;
      _rememberFailure(url);
      return null;
    } on TimeoutException {
      cancel.cancel();
      return null;
    } on HttpError catch (error) {
      // A status code is the server's verdict on this URL; anything else is the
      // connection and may well work next time.
      if (error.statusCode != 0) _rememberFailure(url);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<ui.Image?> _decode(Uint8List bytes) async {
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(bytes, targetWidth: _emojiSize, targetHeight: _emojiSize);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    } finally {
      codec?.dispose();
    }
  }

  void _rememberFailure(String url) {
    while (_failedUrls.length >= _maxFailedUrls) {
      _failedUrls.remove(_failedUrls.first);
    }
    _failedUrls.add(url);
  }

  /// Once a week per platform, fetches the list from the repository and keeps
  /// it beside the images when it parses to a non-empty list. Never blocks a
  /// load: the refreshed list is picked up by the next [preload].
  Future<void> _refreshList(String platform, DanmakuEmojiParser parser, Directory cacheDir) async {
    if (!_refreshingLists.add(platform)) return;
    try {
      final key = '$_listCheckedPrefKey$platform';
      final now = DateTime.now().millisecondsSinceEpoch;
      final lastChecked = HivePrefUtil.getInt(key) ?? 0;
      if (now - lastChecked < _listRefreshInterval.inMilliseconds) return;
      // Recorded before the request so an unreachable repository is not asked
      // again in every room for the rest of the week.
      await HivePrefUtil.setInt(key, now);

      final body = await HttpClient.instance.getText(danmakuEmojiListUrl(platform));
      if (parseDanmakuEmojiList(body, parser).isEmpty) {
        throw const FormatException('the refreshed list holds no emoji');
      }
      await _writeAtomically(File(p.join(cacheDir.path, '$platform.json')), utf8.encode(body));
      CoreLog.i('danmaku emoji list refreshed ($platform)');
    } catch (error) {
      CoreLog.w('danmaku emoji list refresh skipped ($platform): $error');
    } finally {
      _refreshingLists.remove(platform);
    }
  }

  Future<Uint8List?> _readQuietly(File file) async {
    try {
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Writes to a temporary name first so a reader never sees a half-written
  /// file; a crash mid-write leaves only a `.part` file behind.
  Future<void> _writeAtomically(File file, List<int> bytes) async {
    final temp = File('${file.path}.${DateTime.now().microsecondsSinceEpoch}.part');
    await file.parent.create(recursive: true);
    await temp.writeAsBytes(bytes, flush: true);
    try {
      await temp.rename(file.path);
    } catch (_) {
      await _deleteQuietly(temp);
      rethrow;
    }
  }
}

class _LoadedEmoji {
  const _LoadedEmoji({required this.file, required this.models, required this.image});

  final File file;
  final List<UnifiedEmojiModel> models;
  final ui.Image image;
}
