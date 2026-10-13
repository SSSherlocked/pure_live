import 'dart:async';
import 'dart:convert';

import 'package:pure_live/core/logging/core_log.dart';
import 'package:pure_live/core/models/live_message.dart';
import 'package:pure_live/core/network/http_client.dart';
import 'package:pure_live/core/network/web_socket_util.dart';
import 'package:pure_live/shared/platforms/live_danmaku.dart';

class ChzzkDanmakuArgs {
  const ChzzkDanmakuArgs({required this.chatChannelId, this.channelId = ''});

  final String chatChannelId;
  final String channelId;
}

class ChzzkDanmaku extends LiveDanmaku {
  ChzzkDanmaku();

  static const String _tokenUrl = 'https://comm-api.game.naver.com/nng_main/v1/chats/access-token';
  static const String _routingUrl = 'https://routing.chat.naver.com/routing/getRouting';
  static const Duration _pingInterval = Duration(seconds: 20);
  static const int _maxRefusals = 3;

  ChzzkDanmakuArgs? _args;
  WebScoketUtils? _socket;

  /// Completes with `true` when the server refused the join.
  Completer<bool>? _ended;
  var _generation = 0;
  var _running = false;
  var _joined = false;
  var _refusals = 0;
  var _tid = 1;
  Timer? _pingTimer;

  @override
  Future start(dynamic args) async {
    if (args is! ChzzkDanmakuArgs || args.chatChannelId.trim().isEmpty) {
      onClose?.call('CHZZK：没有可用的聊天频道');
      return;
    }
    _args = args;
    _generation++;
    final generation = _generation;
    _running = true;
    _refusals = 0;
    unawaited(_loop(generation));
  }

  @override
  Future stop() async {
    _running = false;
    _generation++;
    _pingTimer?.cancel();
    final socket = _socket;
    final ended = _ended;
    _socket = null;
    _ended = null;
    markDisconnected();
    await socket?.close();
    if (ended != null && !ended.isCompleted) ended.complete(false);
  }

  Future<void> _loop(int generation) async {
    var attempt = 0;
    while (_running && generation == _generation) {
      try {
        final token = await _accessToken(generation);
        if (!_running || generation != _generation) return;
        if (token == null) {
          onClose?.call('CHZZK：拿不到聊天访问令牌');
          return;
        }
        final servers = await _sessionServers(generation);
        if (!_running || generation != _generation) return;
        if (servers.isEmpty) throw StateError('CHZZK：没有可用的会话服务器');
        final server = servers[attempt % servers.length];
        final refused = await _runSocket(server, token, generation);
        if (!_running || generation != _generation) return;
        if (!refused) {
          attempt = 0;
        } else if (++_refusals > _maxRefusals) {
          onClose?.call('CHZZK：加入被拒');
          return;
        } else {
          markDisconnected();
          onReconnect?.call('CHZZK 加入被拒，正在重试');
          attempt++;
        }
      } catch (error) {
        if (generation != _generation) return;
        CoreLog.error('CHZZK chat failed: $error');
        onReconnect?.call('CHZZK 弹幕连接失败，正在重试');
        attempt++;
      }
      if (!_running || generation != _generation) return;
      await Future<void>.delayed(Duration(seconds: attempt.clamp(1, 8)));
    }
  }

  Future<String?> _accessToken(int generation) async {
    final chatChannelId = _args?.chatChannelId ?? '';
    for (var round = 0; round < 3; round++) {
      if (round > 0) {
        await Future<void>.delayed(round == 1 ? const Duration(milliseconds: 500) : const Duration(seconds: 1));
        if (!_running || generation != _generation) return null;
      }
      try {
        final response = await HttpClient.instance.getJson(
          _tokenUrl,
          queryParameters: <String, String>{'channelId': chatChannelId, 'chatType': 'STREAMING'},
          header: const <String, String>{'Origin': 'https://chzzk.naver.com'},
        );
        if (generation != _generation) return null;
        final content = response is Map ? response['content'] : null;
        final token = content is Map ? content['accessToken']?.toString().trim() ?? '' : '';
        if (token.isNotEmpty) return token;
      } catch (error) {
        CoreLog.error('CHZZK access token failed: $error');
      }
    }
    return null;
  }

  Future<List<String>> _sessionServers(int generation) async {
    final response = await HttpClient.instance.getJson(
      _routingUrl,
      queryParameters: <String, String>{'serviceId': 'game'},
      header: const <String, String>{'Origin': 'https://chzzk.naver.com'},
    );
    if (generation != _generation) return const <String>[];
    final result = response is Map ? response['result'] : null;
    final list = result is Map ? result['sessionServerList'] : null;
    if (list is! List) return const <String>[];
    final servers = <String>[];
    for (final entry in list) {
      final host = entry?.toString().trim().toLowerCase() ?? '';
      if (host.isEmpty || servers.length >= 16) continue;
      if (!host.endsWith('.chat.naver.com')) continue;
      if (!RegExp(r'^[a-z0-9-]+$').hasMatch(host.split('.').first)) continue;
      if (servers.contains(host)) continue;
      servers.add(host);
    }
    return servers;
  }

  Future<bool> _runSocket(String server, String token, int generation) async {
    final ended = Completer<bool>();
    _ended = ended;
    _joined = false;
    _tid = 1;
    final socket = WebScoketUtils(
      url: 'wss://$server/chat',
      heartBeatTime: 0,
      headers: const <String, String>{'origin': 'https://chzzk.naver.com'},
      onReady: () {
        if (generation != _generation) return;
        _socket?.sendMessage(json.encode(<String, Object?>{
          'ver': '3',
          'cmd': 100,
          'svcid': 'game',
          'cid': _args?.chatChannelId ?? '',
          'bdy': <String, Object?>{
            'uid': null,
            'devType': 2001,
            'accTkn': token,
            'auth': 'READ',
          },
          'tid': _tid++,
        }));
        _pingTimer?.cancel();
        _pingTimer = Timer.periodic(_pingInterval, (_) {
          _socket?.sendMessage(json.encode(<String, Object?>{'ver': '3', 'cmd': 0, 'tid': _tid++}));
        });
      },
      onMessage: (event) {
        if (generation != _generation) return;
        _handleFrame(event is String ? event : utf8.decode(event as List<int>, allowMalformed: true));
      },
      onReconnect: () {
        if (generation != _generation) return;
        markDisconnected();
        onReconnect?.call('与服务器断开连接，正在尝试重连');
      },
      onClose: (error) {
        if (generation != _generation) return;
        markDisconnected();
        if (!ended.isCompleted) ended.complete(false);
      },
    );
    _socket = socket;
    try {
      await socket.connect();
      return await ended.future;
    } finally {
      // `ended` may have been completed by a protocol frame while the socket
      // is still open; close it here so the next round does not run alongside
      // an orphaned connection. `stop()` has already cancelled the timer when
      // the generation moved on.
      if (generation == _generation) _pingTimer?.cancel();
      if (identical(_ended, ended)) _ended = null;
      if (identical(_socket, socket)) _socket = null;
      await socket.close();
    }
  }

  void _handleFrame(String data) {
    final text = data.trim();
    if (text.isEmpty) return;
    final Object? decoded;
    try {
      decoded = json.decode(text);
    } catch (_) {
      return;
    }
    if (decoded is! Map) return;
    final cmd = int.tryParse(decoded['cmd']?.toString() ?? '') ?? 0;
    if (cmd == 100 && !_joined) {
      _joined = true;
      _refusals = 0;
      markConnected();
      onReady?.call();
      return;
    }
    // `onMessage` runs inside the socket's stream listener: a throw here would
    // never reach `_loop`, so rejections end the round through `_ended`.
    final ended = _ended;
    if (cmd >= 302 && cmd <= 304) {
      CoreLog.error('CHZZK join refused: cmd $cmd');
      if (ended != null && !ended.isCompleted) ended.complete(true);
      return;
    }
    if (cmd == 90102) {
      // The server asks us to reconnect; a manual `_socket?.close()` would
      // never report back through `onClose`, so end the round instead.
      if (ended != null && !ended.isCompleted) ended.complete(false);
      return;
    }
    if (cmd == 93101 || cmd == 93102) {
      final chat = _chatMessage(decoded['bdy']);
      if (chat != null) onMessage?.call(chat);
    }
  }

  LiveMessage? _chatMessage(Object? body) {
    if (body is! Map) return null;
    final type = int.tryParse((body['msgTypeCode'] ?? body['messageTypeCode'])?.toString() ?? '') ?? 1;
    if (type != 1 && type != 10 && type != 11) return null;
    final status = (body['msgStatusType'] ?? body['messageStatusType'])?.toString() ?? '';
    if (status.isNotEmpty && status != 'NORMAL') return null;
    final raw = body['msg'] ?? body['content'];
    final message = switch (raw) {
      String value => value.trim(),
      int value => '$value',
      _ => '',
    };
    if (message.isEmpty) return null;
    final profile = _jsonObject(body['profile']);
    final createdAt = int.tryParse(body['msgTime']?.toString() ?? body['messageTime']?.toString() ?? '');
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: profile?['nickname']?.toString().trim() ?? '',
      userId: (body['uid'] ?? body['userId'])?.toString() ?? '',
      message: message,
      sentAt: createdAt == null || createdAt <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(createdAt),
      color: LiveMessageColor.white,
    );
  }

  static Map<String, dynamic>? _jsonObject(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.trim().startsWith('{')) {
      try {
        final decoded = json.decode(value);
        return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
