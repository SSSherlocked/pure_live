import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bonsoir/bonsoir.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/storage/hive_pref_util.dart';
import 'package:pure_live/core/platform/platform_utils.dart';
import 'package:pure_live/core/security/settings_crypto.dart';
import 'package:pure_live/features/backup/backup_controller.dart';
import 'package:pure_live/features/remote_receiver/remote_sync_device.dart';
import 'package:pure_live/features/remote_receiver/remote_sync_protocol.dart';

class RemoteSyncService extends GetxController {
  static RemoteSyncService get to => Get.find<RemoteSyncService>();

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  final RxBool isServerRunning = false.obs;
  final RxBool isDiscovering = false.obs;
  final RxBool isSyncing = false.obs;
  final RxBool isApplying = false.obs;

  final RxString localIp = ''.obs;
  final RxInt localPort = RemoteSyncProtocol.defaultHttpPort.obs;

  final RxList<RemoteSyncDevice> devices = <RemoteSyncDevice>[].obs;

  /// Asks the user whether [remoteAddress] may read ('export') or overwrite
  /// ('import') this device's settings. Requests are refused without it.
  ///
  /// [pairingCode] is derived from the session key; the requesting device shows
  /// the same six digits, and only equal digits mean nobody is in between.
  Future<bool> Function(String action, String remoteAddress, String pairingCode)? confirmRequest;

  /// Why the last outgoing sync failed, as a translation key, when known.
  String? lastFailureKey;

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  static const String _mdnsServiceType = '_purelive-sync._tcp';

  final Set<String> _localIps = <String>{};

  String _deviceId = '';

  HttpServer? _server;

  /// This server's key pair; new for every server start, so a session key never
  /// outlives the page that showed its QR code.
  SyncKeyPair? _sessionKeys;

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;

  StreamSubscription<BonsoirDiscoveryEvent>? _discoverySubscription;

  Timer? _broadcastTimer;
  Timer? _cleanupTimer;

  bool _disposed = false;
  bool _running = false;

  /// Whether a `/settings` request is waiting for the user's answer in the
  /// confirmation dialog. Further requests are refused until it is answered.
  bool _confirmPending = false;

  /// The client of the outgoing request in flight, so [cancelOutgoing] can cut
  /// it while the other device is still deciding.
  HttpClient? _outgoingClient;

  /// How long an outgoing request may wait, mostly for the person at the other
  /// device to answer the confirmation dialog.
  static const Duration _requestTimeout = Duration(seconds: 60);

  // ---------------------------------------------------------------------------
  // Device information
  // ---------------------------------------------------------------------------

  String get deviceName {
    switch (Platform.operatingSystem) {
      case 'android':
        return 'PureLive Android';
      case 'ios':
        return 'PureLive iPhone';
      case 'windows':
        return 'PureLive Windows';
      case 'macos':
        return 'PureLive macOS';
      case 'linux':
        return 'PureLive Linux';
      default:
        return 'PureLive';
    }
  }

  String get platform {
    return Platform.operatingSystem;
  }

  String get version {
    return '1.0.0';
  }

  String get address {
    if (localIp.value.isEmpty) {
      return '';
    }

    return '${localIp.value}:${localPort.value}';
  }

  String get qrData {
    if (localIp.value.isEmpty) {
      return '';
    }

    final keys = _sessionKeys;
    return RemoteSyncProtocol.createQrUri(
      ip: localIp.value,
      port: localPort.value,
      fingerprint: keys == null ? null : SyncCipher.fingerprint(keys.publicKey),
    ).toString();
  }

  String get broadcastName {
    final id = _deviceId.length > 6 ? _deviceId.substring(_deviceId.length - 6) : _deviceId;

    return 'PureLive-$id';
  }

  bool get isMobile {
    return Platform.isAndroid || Platform.isIOS;
  }

  bool get isDesktop {
    return PlatformUtils.isDesktop;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void onInit() {
    super.onInit();
    _deviceId = _loadDeviceId();
    unawaited(start());
  }

  String _loadDeviceId() {
    const key = 'remote_sync_device_id';
    final existing = HivePrefUtil.getString(key);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final id = '${Platform.operatingSystem}-${DateTime.now().microsecondsSinceEpoch}';
    HivePrefUtil.setString(key, id);
    return id;
  }

  Future<void> start() async {
    if (_disposed || _running) {
      return;
    }

    _running = true;

    try {
      await _refreshNetworkInfo();

      if (_disposed || localIp.value.isEmpty) {
        return;
      }

      await startServer();

      if (_disposed) {
        return;
      }

      await startDiscovery();
    } finally {
      _running = false;
    }
  }

  /// Stops serving and discovery; [start] can resume. Only [onClose] disposes.
  Future<void> stop() async {
    _running = false;

    _broadcastTimer?.cancel();
    _broadcastTimer = null;

    _cleanupTimer?.cancel();
    _cleanupTimer = null;

    final discoverySubscription = _discoverySubscription;
    _discoverySubscription = null;

    if (discoverySubscription != null) {
      try {
        await discoverySubscription.cancel();
      } catch (_) {}
    }

    final discovery = _discovery;
    _discovery = null;

    if (discovery != null) {
      try {
        await discovery.stop();
      } catch (_) {}
    }

    final broadcast = _broadcast;
    _broadcast = null;

    if (broadcast != null) {
      try {
        await broadcast.stop();
      } catch (_) {}
    }

    final server = _server;
    _server = null;

    if (server != null) {
      try {
        await server.close(force: true);
      } catch (_) {}
    }

    devices.clear();

    isServerRunning.value = false;
    isDiscovering.value = false;
  }

  @override
  void onClose() {
    _disposed = true;

    unawaited(stop());

    super.onClose();
  }

  // ---------------------------------------------------------------------------
  // Network
  // ---------------------------------------------------------------------------

  Future<void> _refreshNetworkInfo() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);

      final ips = <String>{};

      String? privateIp;
      String? fallbackIp;

      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final ip = address.address.trim();

          if (ip.isEmpty) {
            continue;
          }

          if (ip.startsWith('127.') || ip.startsWith('169.254.')) {
            continue;
          }

          if (!_isValidIpv4(ip)) {
            continue;
          }

          ips.add(ip);

          fallbackIp ??= ip;

          if (_isPrivateIpv4Address(ip)) {
            if (privateIp == null || _isPreferredIpv4(ip, privateIp)) {
              privateIp = ip;
            }
          }
        }
      }

      _localIps
        ..clear()
        ..addAll(ips);

      localIp.value = privateIp ?? fallbackIp ?? '';
    } catch (_) {
      _localIps.clear();
      localIp.value = '';
    }
  }

  bool _isPreferredIpv4(String candidate, String current) {
    final candidateScore = _ipv4Priority(candidate);
    final currentScore = _ipv4Priority(current);

    return candidateScore > currentScore;
  }

  int _ipv4Priority(String ip) {
    if (ip.startsWith('192.168.')) {
      return 3;
    }

    if (ip.startsWith('10.')) {
      return 2;
    }

    final parts = ip.split('.');
    if (parts.length == 4) {
      final second = int.tryParse(parts[1]);

      if (parts[0] == '172' && second != null && second >= 16 && second <= 31) {
        return 1;
      }
    }

    return 0;
  }

  bool _isPrivateIpv4Address(String ip) {
    final parts = ip.split('.');

    if (parts.length != 4) {
      return false;
    }

    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);

    if (a == null || b == null) {
      return false;
    }

    if (a == 10) {
      return true;
    }

    if (a == 172 && b >= 16 && b <= 31) {
      return true;
    }

    if (a == 192 && b == 168) {
      return true;
    }

    return false;
  }

  bool _isValidIpv4(String ip) {
    final parts = ip.split('.');

    if (parts.length != 4) {
      return false;
    }

    for (final part in parts) {
      final value = int.tryParse(part);

      if (value == null || value < 0 || value > 255) {
        return false;
      }
    }

    return true;
  }

  String? _ipv4Prefix(String ip) {
    final parts = ip.split('.');

    if (parts.length != 4) {
      return null;
    }

    return '${parts[0]}.${parts[1]}.${parts[2]}';
  }

  // ---------------------------------------------------------------------------
  // HTTP Server
  // ---------------------------------------------------------------------------

  Future<void> startServer() async {
    if (_disposed || isServerRunning.value) {
      return;
    }

    await _refreshNetworkInfo();

    if (_disposed) {
      return;
    }

    HttpServer? server;
    _sessionKeys = SyncKeyPair.generate();

    var port = RemoteSyncProtocol.defaultHttpPort;

    for (var i = 0; i < 100; i++) {
      try {
        server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);

        break;
      } catch (_) {
        port++;
      }
    }

    if (server == null || _disposed) {
      try {
        await server?.close(force: true);
      } catch (_) {}

      isServerRunning.value = false;
      return;
    }

    _server = server;
    localPort.value = port;
    isServerRunning.value = true;

    server.listen(
      handleRequest,
      onError: (_) {
        if (!_disposed) {
          isServerRunning.value = false;
        }
      },
    );

    _startCleanupTimer();
  }

  @visibleForTesting
  Future<void> handleRequest(HttpRequest request) async {
    if (_disposed) {
      try {
        await request.response.close();
      } catch (_) {}

      return;
    }

    final response = request.response;

    // No CORS headers: a web page in a browser on the network must not be
    // able to read this device's settings.
    response.headers.contentType = ContentType('application', 'json', charset: 'utf-8');

    try {
      switch (request.uri.path) {
        case RemoteSyncProtocol.apiStatus:
          await _handleStatus(request);
          return;

        case RemoteSyncProtocol.apiSettings:
          await _handleSettings(request);
          return;

        default:
          response.statusCode = HttpStatus.notFound;

          await _writeResponse(response, {'code': 404, 'msg': 'Not Found', 'data': false});
      }
    } catch (_) {
      try {
        response.statusCode = HttpStatus.internalServerError;

        await _writeResponse(response, {'code': 500, 'msg': 'Internal Server Error', 'data': false});
      } catch (_) {
        // Response may already be closed.
      }
    }
  }

  // ---------------------------------------------------------------------------
  // GET /status
  //
  // Only returns device information.
  // ---------------------------------------------------------------------------

  Future<void> _handleStatus(HttpRequest request) async {
    if (request.method != 'GET') {
      await _writeMethodNotAllowed(request.response);
      return;
    }

    await _writeResponse(request.response, {
      'code': 200,
      'msg': 'ok',
      'data': {
        'id': _deviceId,
        'name': deviceName,
        'platform': platform,
        'version': version,
        'ip': localIp.value,
        'port': localPort.value,
        'protocol': RemoteSyncProtocol.protocolVersion,
        // The other half of the key agreement. Public on purpose: it only lets
        // a client agree a key with this server, and the QR fingerprint and the
        // pairing code tell a substituted one apart.
        'publicKey': _sessionKeys?.publicKeyBase64,
      },
    });
  }

  // ---------------------------------------------------------------------------
  // /settings
  //
  // GET  -> export local settings
  // POST -> import remote settings
  // ---------------------------------------------------------------------------

  Future<void> _handleSettings(HttpRequest request) async {
    final action = switch (request.method) {
      'GET' => 'export',
      'POST' => 'import',
      _ => null,
    };
    if (action == null) {
      await _writeMethodNotAllowed(request.response);
      return;
    }

    // Settings carry account cookies, so they only travel encrypted: a request
    // without a session key is an older version, and gets nothing.
    final key = _sessionKeyFor(request);
    if (key == null) {
      request.response.statusCode = HttpStatus.upgradeRequired;
      await _writeResponse(request.response, {'code': 426, 'msg': 'Encrypted sync required', 'data': false});
      return;
    }

    // One confirmation dialog at a time: a request that arrives while the user
    // is still deciding on another is refused instead of stacking a dialog.
    if (_confirmPending) {
      request.response.statusCode = HttpStatus.tooManyRequests;
      await _writeResponse(request.response, {'code': 429, 'msg': 'Awaiting another confirmation', 'data': false});
      return;
    }

    // Whoever can reach this port still has to be approved on this device, and
    // the dialog shows the pairing code to compare with the other screen.
    if (!await _confirm(action, request, SyncCipher.pairingCode(key))) {
      request.response.statusCode = HttpStatus.forbidden;
      await _writeResponse(request.response, {'code': 403, 'msg': 'Rejected on the device', 'data': false});
      return;
    }
    if (action == 'export') {
      await _handleGetSettings(request, key);
    } else {
      await _handlePostSettings(request, key);
    }
  }

  /// The session key agreed with the client's public key, or null.
  Uint8List? _sessionKeyFor(HttpRequest request) {
    final keys = _sessionKeys;
    final header = request.headers.value(RemoteSyncProtocol.clientKeyHeader)?.trim();
    if (keys == null || header == null || header.isEmpty) return null;
    try {
      final clientPublic = Uint8List.fromList(base64Url.decode(base64Url.normalize(header)));
      return SyncCipher.sessionKey(
        own: keys,
        peerPublicKey: clientPublic,
        serverPublicKey: keys.publicKey,
        clientPublicKey: clientPublic,
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // GET /settings
  //
  // Used when this device receives settings from another device.
  // ---------------------------------------------------------------------------

  Future<void> _handleGetSettings(HttpRequest request, Uint8List key) async {
    try {
      final backup = Get.find<BackupController>();

      final settings = backup.exportAllSettings();

      await _writeResponse(request.response, {
        'code': 200,
        'msg': 'ok',
        'protocol': RemoteSyncProtocol.protocolVersion,
        'enc': SyncCipher.sealJson(key, settings),
      });
    } catch (_) {
      request.response.statusCode = HttpStatus.internalServerError;

      await _writeResponse(request.response, {'code': 500, 'msg': 'Export settings failed', 'data': false});
    }
  }

  // ---------------------------------------------------------------------------
  // POST /settings
  //
  // Used when another device sends settings to this device.
  // ---------------------------------------------------------------------------

  Future<void> _handlePostSettings(HttpRequest request, Uint8List key) async {
    try {
      final content = await utf8.decoder.bind(request).join();

      if (content.trim().isEmpty) {
        request.response.statusCode = HttpStatus.badRequest;

        await _writeResponse(request.response, {'code': 400, 'msg': 'Empty request', 'data': false});

        return;
      }

      final outer = jsonDecode(content);
      // The packet itself travels sealed; a wrong key or a changed byte fails here.
      Object? body;
      try {
        body = outer is Map ? SyncCipher.openJson(key, outer['enc']) : null;
      } catch (_) {
        body = null;
      }

      if (body is! Map<String, dynamic>) {
        request.response.statusCode = HttpStatus.badRequest;

        await _writeResponse(request.response, {'code': 400, 'msg': 'Invalid request', 'data': false});

        return;
      }

      final type = body['type']?.toString();

      if (type != RemoteSyncProtocol.syncType) {
        request.response.statusCode = HttpStatus.badRequest;

        await _writeResponse(request.response, {'code': 400, 'msg': 'Invalid sync type', 'data': false});

        return;
      }

      final settings = body['settings'];

      if (settings is! Map) {
        request.response.statusCode = HttpStatus.badRequest;

        await _writeResponse(request.response, {'code': 400, 'msg': 'Settings is empty', 'data': false});

        return;
      }

      isSyncing.value = true;

      final success = await applyRemoteSettings(Map<String, dynamic>.from(settings));

      isSyncing.value = false;

      await _writeResponse(request.response, {
        'code': success ? 200 : 500,
        'msg': success ? 'ok' : 'apply settings failed',
        'data': success,
      });
    } catch (_) {
      isSyncing.value = false;

      try {
        request.response.statusCode = HttpStatus.internalServerError;

        await _writeResponse(request.response, {'code': 500, 'msg': 'Internal Server Error', 'data': false});
      } catch (_) {}
    }
  }

  Future<bool> _confirm(String action, HttpRequest request, String pairingCode) async {
    final ask = confirmRequest;
    if (ask == null || _disposed) return false;
    final remote = request.connectionInfo?.remoteAddress.address ?? '';
    _confirmPending = true;
    try {
      return await ask(action, remote, pairingCode);
    } catch (_) {
      return false;
    } finally {
      _confirmPending = false;
    }
  }

  /// Applies the received payload, narrowed to [sections] when the receiver
  /// ticked a subset on the module page.
  Future<bool> applyRemoteSettings(Map<String, dynamic> settings, {Iterable<String>? sections}) async {
    return _applyRemoteSettings(BackupController.filterBackupSections(settings, sections));
  }

  Future<bool> _applyRemoteSettings(Map<String, dynamic> settings) async {
    try {
      final backup = Get.find<BackupController>();

      backup.importAllSettings(settings);

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _writeMethodNotAllowed(HttpResponse response) async {
    response.statusCode = HttpStatus.methodNotAllowed;

    await _writeResponse(response, {'code': 405, 'msg': 'Method Not Allowed', 'data': false});
  }

  Future<void> _writeResponse(HttpResponse response, Map<String, dynamic> data) async {
    response.write(jsonEncode(data));
    await response.close();
  }

  // ---------------------------------------------------------------------------
  // Bonsoir Discovery
  // ---------------------------------------------------------------------------

  Future<bool> startDiscovery() async {
    if (_disposed) {
      return false;
    }

    if (isDiscovering.value) {
      return true;
    }

    await _refreshNetworkInfo();

    if (_disposed || localIp.value.isEmpty) {
      return false;
    }

    try {
      await _discoverySubscription?.cancel();
      _discoverySubscription = null;

      final oldDiscovery = _discovery;
      _discovery = null;

      if (oldDiscovery != null) {
        try {
          await oldDiscovery.stop();
        } catch (_) {}
      }

      final discovery = BonsoirDiscovery(type: _mdnsServiceType);

      _discovery = discovery;

      await discovery.initialize();

      if (_disposed) {
        await discovery.stop();
        return false;
      }

      final eventStream = discovery.eventStream;

      if (eventStream == null) {
        isDiscovering.value = false;
        return false;
      }

      _discoverySubscription = eventStream.listen(
        (event) {
          if (_disposed) {
            return;
          }

          unawaited(_handleDiscoveryEvent(event, discovery));
        },
        onError: (_) {
          if (!_disposed) {
            isDiscovering.value = false;
          }
        },
      );

      await discovery.start();

      if (_disposed) {
        try {
          await discovery.stop();
        } catch (_) {}

        return false;
      }

      isDiscovering.value = true;

      await _startServiceBroadcast();

      return true;
    } catch (_) {
      isDiscovering.value = false;
      return false;
    }
  }

  Future<void> _handleDiscoveryEvent(BonsoirDiscoveryEvent event, BonsoirDiscovery discovery) async {
    if (_disposed) {
      return;
    }

    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent():
        final service = event.service;

        if (_isSelfService(service)) {
          return;
        }
        _addOrUpdateDevice(service);
        try {
          service.resolve(discovery.serviceResolver);
        } catch (_) {
          _addOrUpdateDevice(service);
        }

      case BonsoirDiscoveryServiceResolvedEvent():
        final service = event.service;

        if (_isSelfService(service)) {
          return;
        }

        _addOrUpdateDevice(service);

      case BonsoirDiscoveryServiceUpdatedEvent():
        final service = event.service;

        if (_isSelfService(service)) {
          return;
        }

        _addOrUpdateDevice(service);

      case BonsoirDiscoveryServiceLostEvent():
        final service = event.service;

        _removeDevice(service);

      default:
        break;
    }
  }

  bool _isSelfService(BonsoirService service) {
    final id = service.attributes['id']?.trim();

    if (id == _deviceId) {
      return true;
    }

    final ip = service.attributes['ip']?.trim();

    return ip != null && ip.isNotEmpty && _localIps.contains(ip);
  }

  void _addOrUpdateDevice(BonsoirService service) {
    if (_disposed) return;

    final attributes = service.attributes;

    final id = attributes['id']?.trim() ?? '';

    if (id.isEmpty || id == _deviceId) {
      return;
    }

    final name = attributes['name']?.trim().isNotEmpty == true ? attributes['name']!.trim() : service.name;

    final devicePlatform = attributes['platform'] ?? '';
    final deviceVersion = attributes['version'] ?? '';

    final ip = _selectServiceIp(service) ?? attributes['ip']?.trim();

    if (ip == null || !_isValidIpv4(ip)) {
      return;
    }

    final port = service.port > 0 ? service.port : RemoteSyncProtocol.defaultHttpPort;

    final device = RemoteSyncDevice(
      id: id,
      name: name,
      platform: devicePlatform,
      version: deviceVersion,
      ip: ip,
      port: port,
      lastSeen: DateTime.now(),
      bonsoirName: service.name,
    );

    final indexById = devices.indexWhere((item) => item.id == device.id);

    if (indexById >= 0) {
      devices[indexById] = device;
      return;
    }

    final indexByIp = devices.indexWhere((item) => item.ip.trim() == device.ip.trim());

    if (indexByIp >= 0) {
      devices[indexByIp] = device;
      return;
    }

    devices.add(device);
  }

  void _removeDevice(BonsoirService service) {
    if (_disposed) return;

    final id = service.attributes['id']?.trim();

    if (id != null && id.isNotEmpty) {
      devices.removeWhere((device) => device.id == id);
    } else {
      devices.removeWhere((device) => device.bonsoirName == service.name);
    }
  }

  String? _selectServiceIp(BonsoirService service) {
    final addresses = service.hostAddresses;

    final ipv4 = addresses.where(_isValidIpv4).toList();

    if (ipv4.isNotEmpty) {
      if (localIp.value.isNotEmpty) {
        final localPrefix = _ipv4Prefix(localIp.value);

        if (localPrefix != null) {
          for (final ip in ipv4) {
            if (_ipv4Prefix(ip) == localPrefix) {
              return ip;
            }
          }
        }
      }

      for (final ip in ipv4) {
        if (_isPrivateIpv4Address(ip)) {
          return ip;
        }
      }

      return ipv4.first;
    }

    final advertisedIp = service.attributes['ip']?.trim();

    if (advertisedIp != null && _isValidIpv4(advertisedIp)) {
      return advertisedIp;
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Bonsoir Broadcast
  // ---------------------------------------------------------------------------

  Future<void> _startServiceBroadcast() async {
    if (_disposed || localPort.value <= 0) {
      return;
    }

    final oldBroadcast = _broadcast;
    _broadcast = null;

    if (oldBroadcast != null) {
      try {
        await oldBroadcast.stop();
      } catch (_) {}
    }

    if (_disposed) {
      return;
    }

    final service = BonsoirService(
      name: broadcastName,
      type: _mdnsServiceType,
      port: localPort.value,
      attributes: {'id': _deviceId, 'name': deviceName, 'platform': platform, 'version': version, 'ip': localIp.value},
    );

    final broadcast = BonsoirBroadcast(service: service);

    _broadcast = broadcast;

    await broadcast.initialize();

    if (_disposed || !identical(_broadcast, broadcast)) {
      try {
        await broadcast.stop();
      } catch (_) {}

      return;
    }

    await broadcast.start();

    // stop() may have run while start() was in flight: it cleared _broadcast and
    // stopped a broadcast that had not started yet, so this one must stop here.
    if (_disposed || !identical(_broadcast, broadcast)) {
      try {
        await broadcast.stop();
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // Device cleanup
  // ---------------------------------------------------------------------------

  void _startCleanupTimer() {
    _cleanupTimer?.cancel();

    _cleanupTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_disposed) {
        return;
      }

      final now = DateTime.now();

      devices.removeWhere((device) {
        return now.difference(device.lastSeen).inSeconds > 120;
      });
    });
  }

  // ---------------------------------------------------------------------------
  // Send settings
  // ---------------------------------------------------------------------------

  Future<bool> syncToDevice(
    RemoteSyncDevice device, {
    List<String>? sections,
    ValueChanged<String>? onPairingCode,
  }) {
    return syncToAddress(device.ip, device.port, sections: sections, onPairingCode: onPairingCode);
  }

  /// Top-level section names of a local backup, for the picker UI.
  List<String> exportSectionNames() {
    return BackupController.sectionNames;
  }

  /// Agrees a session key with the device at [ip]:[port].
  ///
  /// Reads the server's public key from its status endpoint. When the address
  /// came from a QR code, [fingerprint] is the key that QR promised, and any
  /// other key is refused: it would be someone in between. Otherwise the
  /// pairing code, shown here through [onPairingCode] and on the other device in
  /// its confirmation dialog, is how the viewer checks the same thing.
  Future<({Uint8List key, String clientPublicKey})?> _openSession(
    String ip,
    int port, {
    String? fingerprint,
    ValueChanged<String>? onPairingCode,
  }) async {
    final statusUri = Uri.parse('http://$ip:$port${RemoteSyncProtocol.apiStatus}');
    final reply = await _exchange((client) => client.getUrl(statusUri));
    if (reply == null || reply.status != HttpStatus.ok) return null;
    try {
      final status = jsonDecode(reply.body);
      final data = status is Map ? status['data'] : null;
      final encoded = data is Map ? data['publicKey'] : null;
      if (encoded is! String || encoded.isEmpty) {
        lastFailureKey = 'remote_sync_peer_outdated';
        return null;
      }
      final serverPublic = Uint8List.fromList(base64Url.decode(base64Url.normalize(encoded)));
      if (fingerprint != null && SyncCipher.fingerprint(serverPublic) != fingerprint) {
        lastFailureKey = 'remote_sync_key_mismatch';
        return null;
      }

      final own = SyncKeyPair.generate();
      final key = SyncCipher.sessionKey(
        own: own,
        peerPublicKey: serverPublic,
        serverPublicKey: serverPublic,
        clientPublicKey: own.publicKey,
      );
      onPairingCode?.call(SyncCipher.pairingCode(key));
      return (key: key, clientPublicKey: own.publicKeyBase64);
    } catch (_) {
      return null;
    }
  }

  /// Sends the request built by [send] and reads the whole reply, within
  /// [_requestTimeout] and on a client that [cancelOutgoing] can close. An
  /// unreachable device, a cancelled client and a timeout all yield null.
  Future<({int status, String body})?> _exchange(Future<HttpClientRequest> Function(HttpClient client) send) async {
    final client = HttpClient();
    _outgoingClient = client;
    try {
      return await _roundTrip(client, send).timeout(_requestTimeout);
    } catch (_) {
      return null;
    } finally {
      if (identical(_outgoingClient, client)) _outgoingClient = null;
      client.close(force: true);
    }
  }

  static Future<({int status, String body})> _roundTrip(
    HttpClient client,
    Future<HttpClientRequest> Function(HttpClient client) send,
  ) async {
    final request = await send(client);
    final response = await request.close();
    return (status: response.statusCode, body: await utf8.decoder.bind(response).join());
  }

  /// Cuts the outgoing request in flight, if any; the sync it belongs to then
  /// fails and returns. For the user who gives up waiting for the other device.
  void cancelOutgoing() {
    final client = _outgoingClient;
    _outgoingClient = null;
    client?.close(force: true);
  }

  Future<bool> syncToAddress(
    String ip,
    int port, {
    List<String>? sections,
    String? fingerprint,
    ValueChanged<String>? onPairingCode,
  }) async {
    if (_disposed || isSyncing.value) {
      return false;
    }

    isSyncing.value = true;
    lastFailureKey = null;

    try {
      final session = await _openSession(ip, port, fingerprint: fingerprint, onPairingCode: onPairingCode);
      if (session == null) return false;

      final backup = Get.find<BackupController>();

      final payload = backup.exportAllSettings(sections: sections);
      final packet = RemoteSyncProtocol.settingsPacket(settings: payload, sections: sections);
      final body = jsonEncode(RemoteSyncProtocol.encryptedPacket(SyncCipher.sealJson(session.key, packet)));

      final reply = await _exchange((client) async {
        final request = await client.postUrl(Uri.parse('http://$ip:$port${RemoteSyncProtocol.apiSettings}'));
        request.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
        request.headers.set(RemoteSyncProtocol.clientKeyHeader, session.clientPublicKey);
        request.write(body);
        return request;
      });
      if (reply == null) return false;

      if (reply.status == HttpStatus.upgradeRequired) lastFailureKey = 'remote_sync_peer_outdated';
      if (reply.status != HttpStatus.ok) {
        return false;
      }

      final result = jsonDecode(reply.body);

      return result is Map && result['data'] == true;
    } catch (_) {
      return false;
    } finally {
      isSyncing.value = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Check remote device
  //
  // NOTE:
  // This method only checks whether the remote device is reachable.
  // It does NOT receive settings.
  // ---------------------------------------------------------------------------

  Future<bool> receiveFromAddress(String ip, int port) async {
    if (_disposed || isApplying.value) {
      return false;
    }

    isApplying.value = true;

    try {
      final client = HttpClient();

      try {
        final request = await client.getUrl(
          Uri.parse(
            'http://$ip:$port'
            '${RemoteSyncProtocol.apiStatus}',
          ),
        );

        final response = await request.close();

        return response.statusCode == HttpStatus.ok;
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      return false;
    } finally {
      isApplying.value = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Get remote settings
  //
  // IMPORTANT:
  // This uses GET /settings, not GET /status.
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>?> getRemoteSettings(
    String ip,
    int port, {
    String? fingerprint,
    ValueChanged<String>? onPairingCode,
  }) async {
    // The same flag as sending: one outgoing sync at a time, and the page's
    // buttons stay disabled while this one waits for the other device.
    if (_disposed || isSyncing.value) {
      return null;
    }

    isSyncing.value = true;
    lastFailureKey = null;

    try {
      final session = await _openSession(ip, port, fingerprint: fingerprint, onPairingCode: onPairingCode);
      if (session == null) return null;

      final reply = await _exchange((client) async {
        final request = await client.getUrl(Uri.parse('http://$ip:$port${RemoteSyncProtocol.apiSettings}'));
        request.headers.set(RemoteSyncProtocol.clientKeyHeader, session.clientPublicKey);
        return request;
      });
      if (reply == null) return null;

      if (reply.status == HttpStatus.upgradeRequired) lastFailureKey = 'remote_sync_peer_outdated';
      if (reply.status != HttpStatus.ok) {
        return null;
      }

      final result = jsonDecode(reply.body);

      if (result is! Map) {
        return null;
      }

      if (result['code'] != 200) {
        return null;
      }

      // A wrong key or a changed byte throws here, and the sync fails.
      final data = SyncCipher.openJson(session.key, result['enc']);

      if (data is! Map) {
        return null;
      }

      return Map<String, dynamic>.from(data);
    } catch (_) {
      return null;
    } finally {
      isSyncing.value = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Address / QR
  // ---------------------------------------------------------------------------

  Future<bool> syncByAddress(String value) async {
    final parsed = RemoteSyncProtocol.parseHttpAddress(value);
    if (parsed == null) return false;
    return syncToAddress(parsed.ip, parsed.port);
  }
}
