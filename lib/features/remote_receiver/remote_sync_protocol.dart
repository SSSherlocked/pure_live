class RemoteSyncProtocol {
  static const int defaultHttpPort = 39888;
  static const int discoveryPort = 39889;

  static const String discoveryType = 'pure_live_discovery';
  static const String syncType = 'pure_live_sync';

  static const String apiStatus = '/api/remote-sync/status';
  static const String apiSettings = '/api/remote-sync/settings';

  /// Settings travel encrypted from this version on; see [SyncCipher].
  static const int protocolVersion = 2;

  /// Request header carrying the client's public key for the session.
  static const String clientKeyHeader = 'x-purelive-key';

  /// QR code for this device's sync endpoint: address, port, and the
  /// fingerprint of this session's public key.
  ///
  /// The device that owns the settings still authorizes each request on its own
  /// screen (see `RemoteSyncService.confirmRequest`). The fingerprint lets the
  /// scanning device check, by itself, that the key it is handed really is this
  /// device's — scanning is face to face, the network is not.
  static Uri createQrUri({required String ip, required int port, String? fingerprint}) {
    return Uri(
      scheme: 'purelive',
      host: ip,
      port: port,
      path: '/sync',
      queryParameters: fingerprint == null || fingerprint.isEmpty ? null : {'fp': fingerprint},
    );
  }

  static Map<String, dynamic> discoveryPacket({
    required String id,
    required String name,
    required String ip,
    required int port,
    required String platform,
    required String version,
  }) {
    return {
      'type': discoveryType,
      'id': id,
      'name': name,
      'ip': ip,
      'port': port,
      'platform': platform,
      'version': version,
    };
  }

  static Map<String, dynamic> settingsPacket({required Map<String, dynamic> settings, List<String>? sections}) {
    return {'type': syncType, 'version': 1, 'settings': settings, 'sections': ?sections};
  }

  /// The wire form of a settings packet: [settingsPacket], encrypted.
  static Map<String, dynamic> encryptedPacket(Map<String, String> sealed) {
    return {'type': syncType, 'version': protocolVersion, 'enc': sealed};
  }

  static ({String ip, int port})? parseHttpAddress(String value) {
    var text = value.trim();
    if (text.isEmpty) return null;
    if (!text.startsWith('http://') && !text.startsWith('https://')) text = 'http://$text';
    try {
      final uri = Uri.parse(text);
      final host = uri.host.trim();
      // IPv4 addresses and host names only; free text is not an address.
      if (!RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$').hasMatch(host)) return null;
      final port = uri.hasPort ? uri.port : defaultHttpPort;
      if (port < 1 || port > 65535) return null;
      return (ip: host, port: port);
    } catch (_) {
      return null;
    }
  }

  /// Parses a sync QR code, or a bare `host:port` as an address.
  ///
  /// A QR produced by an older version carries an extra `code` query parameter;
  /// it is ignored. A current one also carries the key fingerprint (`fp`).
  static ({String ip, int port, String? fingerprint})? parseQr(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('purelive:')) {
      final uri = Uri.tryParse(text);
      if (uri == null || uri.host.isEmpty || !uri.hasPort) return null;
      final fingerprint = uri.queryParameters['fp']?.trim();
      return (
        ip: uri.host,
        port: uri.port,
        fingerprint: fingerprint == null || fingerprint.isEmpty ? null : fingerprint,
      );
    }
    // A bare "host:port" is not a valid URI on its own; read it as an address.
    final address = parseHttpAddress(text);
    return address == null ? null : (ip: address.ip, port: address.port, fingerprint: null);
  }
}
