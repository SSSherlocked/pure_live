import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Encryption for settings that leave the device: backups (a local file or
/// WebDAV) and LAN sync between two devices.
///
/// There is no key in this program. The source is public, so a built-in key
/// would protect nothing; every key here is either derived from a password the
/// viewer chooses ([BackupCipher]) or agreed for one sync session and then
/// thrown away ([SyncKeyPair]). The payload cipher is AES-256-GCM in both
/// cases, so a wrong key or a modified byte is detected, never decrypted into
/// garbage.

/// [length] bytes from the platform's cryptographic random source.
Uint8List secureRandomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(List<int>.generate(length, (_) => random.nextInt(256)));
}

const int _gcmTagBits = 128;
const int _gcmNonceLength = 12;

/// Thrown when a sealed payload cannot be opened: wrong key, or modified data.
class SealedDataException implements Exception {
  const SealedDataException(this.message);
  final String message;
  @override
  String toString() => 'SealedDataException: $message';
}

/// AES-256-GCM. Returns the random nonce and the ciphertext (tag appended).
({Uint8List nonce, Uint8List ciphertext}) aesGcmSeal(Uint8List key, Uint8List plaintext, {Uint8List? aad}) {
  final nonce = secureRandomBytes(_gcmNonceLength);
  final cipher = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(key), _gcmTagBits, nonce, aad ?? Uint8List(0)));
  return (nonce: nonce, ciphertext: cipher.process(plaintext));
}

/// Opens [aesGcmSeal]'s output; throws [SealedDataException] when the key is
/// wrong or the data was changed.
Uint8List aesGcmOpen(Uint8List key, Uint8List nonce, Uint8List ciphertext, {Uint8List? aad}) {
  try {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), _gcmTagBits, nonce, aad ?? Uint8List(0)));
    return cipher.process(ciphertext);
  } catch (_) {
    // A failed tag check, a truncated payload, a nonce of the wrong size: all of
    // them mean "cannot be opened with this key", never partial plaintext.
    throw const SealedDataException('authentication failed');
  }
}

Uint8List _sha256(List<int> data) => SHA256Digest().process(Uint8List.fromList(data));

// -----------------------------------------------------------------------------
// Backups: a password the viewer chooses
// -----------------------------------------------------------------------------

/// Thrown when an encrypted backup is opened with the wrong password (or the
/// file was changed).
class BackupPasswordException implements Exception {
  const BackupPasswordException();
}

/// Password-encrypted backup files.
///
/// The file is a small JSON envelope: which key derivation was used and with
/// what parameters, the salt, the GCM nonce and the ciphertext. The password is
/// never stored anywhere; without it the file cannot be opened, which is the
/// point — a backup on a WebDAV share or in a downloads folder no longer hands
/// out the account cookies inside it.
abstract final class BackupCipher {
  static const String marker = 'pure_live_encrypted_backup';
  static const int version = 1;

  /// PBKDF2-HMAC-SHA256 work factor (OWASP 2023 guidance). Stored in each file,
  /// so it can change without breaking old backups.
  static const int defaultIterations = 600000;

  static final Uint8List _aad = Uint8List.fromList(utf8.encode('$marker/v$version'));

  /// Whether [content] is an encrypted backup rather than a plain one.
  static bool isEncrypted(String content) {
    final trimmed = content.trimLeft();
    if (!trimmed.startsWith('{')) return false;
    try {
      final decoded = jsonDecode(trimmed);
      return decoded is Map && decoded['format'] == marker;
    } catch (_) {
      return false;
    }
  }

  /// Encrypts the backup [json] with [password]. The key derivation runs off the
  /// UI isolate: it is deliberately slow.
  static Future<String> encrypt(String json, String password, {int iterations = defaultIterations}) {
    final salt = secureRandomBytes(16);
    return Isolate.run(() {
      final key = deriveKey(password, salt, iterations);
      final sealed = aesGcmSeal(key, Uint8List.fromList(utf8.encode(json)), aad: _aad);
      return jsonEncode({
        'format': marker,
        'version': version,
        'kdf': 'pbkdf2-hmac-sha256',
        'iterations': iterations,
        'salt': base64Encode(salt),
        'cipher': 'aes-256-gcm',
        'nonce': base64Encode(sealed.nonce),
        'data': base64Encode(sealed.ciphertext),
      });
    });
  }

  /// Decrypts an [encrypt]ed backup; throws [BackupPasswordException] when the
  /// password is wrong and [FormatException] when the file is not one.
  static Future<String> decrypt(String content, String password) async {
    final envelope = jsonDecode(content);
    if (envelope is! Map || envelope['format'] != marker) {
      throw const FormatException('Not an encrypted backup');
    }
    if (envelope['kdf'] != 'pbkdf2-hmac-sha256' || envelope['cipher'] != 'aes-256-gcm') {
      throw const FormatException('Unsupported backup encryption');
    }
    final iterations = envelope['iterations'];
    if (iterations is! int || iterations < 1) throw const FormatException('Invalid key derivation');
    final salt = base64Decode('${envelope['salt']}');
    final nonce = base64Decode('${envelope['nonce']}');
    final data = base64Decode('${envelope['data']}');
    final plaintext = await Isolate.run(() {
      try {
        return aesGcmOpen(deriveKey(password, salt, iterations), nonce, data, aad: _aad);
      } on SealedDataException {
        return null;
      }
    });
    if (plaintext == null) throw const BackupPasswordException();
    return utf8.decode(plaintext);
  }

  /// PBKDF2-HMAC-SHA256 → 32-byte AES key.
  static Uint8List deriveKey(String password, Uint8List salt, int iterations) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(Pbkdf2Parameters(salt, iterations, 32));
    return derivator.process(Uint8List.fromList(utf8.encode(password)));
  }
}

// -----------------------------------------------------------------------------
// LAN sync: a key agreed for one session
// -----------------------------------------------------------------------------

final ECDomainParameters _curve = ECCurve_secp256r1();

/// One side's P-256 key pair for a sync session.
///
/// Each side contributes a fresh pair and both derive the same AES key (ECDH):
/// someone who only watches the network learns nothing. Someone who sits in the
/// middle and answers with their own key would end up with a different shared
/// key on each side — which is what the [SyncCipher.pairingCode] shown on both
/// screens, and the fingerprint inside the QR code, catch.
class SyncKeyPair {
  SyncKeyPair._(this._private, this.publicKey);

  factory SyncKeyPair.generate() {
    final random = FortunaRandom()..seed(KeyParameter(secureRandomBytes(32)));
    final generator = ECKeyGenerator()..init(ParametersWithRandom(ECKeyGeneratorParameters(_curve), random));
    final pair = generator.generateKeyPair();
    return SyncKeyPair._(pair.privateKey, pair.publicKey.Q!.getEncoded(false));
  }

  final ECPrivateKey _private;

  /// Uncompressed SEC1 point, 65 bytes.
  final Uint8List publicKey;

  String get publicKeyBase64 => base64UrlEncode(publicKey);

  /// The raw ECDH secret with [peerPublicKey] (32 bytes, big-endian).
  Uint8List agree(Uint8List peerPublicKey) {
    final point = _curve.curve.decodePoint(peerPublicKey);
    if (point == null || point.isInfinity) throw const SealedDataException('invalid public key');
    final agreement = ECDHBasicAgreement()..init(_private);
    final secret = agreement.calculateAgreement(ECPublicKey(point, _curve));
    return _fixedBytes(secret, 32);
  }

  static Uint8List _fixedBytes(BigInt value, int length) {
    final out = Uint8List(length);
    var remaining = value;
    for (var i = length - 1; i >= 0; i--) {
      out[i] = (remaining & BigInt.from(0xff)).toInt();
      remaining = remaining >> 8;
    }
    return out;
  }
}

/// The sync session key and what is derived from it.
abstract final class SyncCipher {
  static const int protocolVersion = 2;
  static final Uint8List _aad = Uint8List.fromList(utf8.encode('pure_live_sync/v$protocolVersion'));

  /// The AES key for one exchange, bound to both public keys so a key agreed
  /// with someone else cannot be replayed into this session.
  static Uint8List sessionKey({
    required SyncKeyPair own,
    required Uint8List peerPublicKey,
    required Uint8List serverPublicKey,
    required Uint8List clientPublicKey,
  }) {
    final secret = own.agree(peerPublicKey);
    return _sha256([
      ...utf8.encode('pure_live_sync_key/v$protocolVersion'),
      ...secret,
      ...serverPublicKey,
      ...clientPublicKey,
    ]);
  }

  /// Six digits both screens show; equal digits mean both sides hold the same
  /// key, i.e. nobody is in the middle.
  static String pairingCode(Uint8List sessionKey) {
    final digest = _sha256([...utf8.encode('pure_live_sync_code'), ...sessionKey]);
    final value = (digest[0] << 24 | digest[1] << 16 | digest[2] << 8 | digest[3]) & 0x7fffffff;
    return (value % 1000000).toString().padLeft(6, '0');
  }

  /// Short fingerprint of a server public key, carried in the QR code.
  static String fingerprint(Uint8List publicKey) {
    final digest = _sha256(publicKey);
    return digest.sublist(0, 12).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Encrypts a JSON value for the wire.
  static Map<String, String> sealJson(Uint8List key, Object? value) {
    final sealed = aesGcmSeal(key, Uint8List.fromList(utf8.encode(jsonEncode(value))), aad: _aad);
    return {'nonce': base64Encode(sealed.nonce), 'data': base64Encode(sealed.ciphertext)};
  }

  /// Opens [sealJson]'s output; throws [SealedDataException] or [FormatException].
  static Object? openJson(Uint8List key, Object? envelope) {
    if (envelope is! Map) throw const FormatException('Missing encrypted payload');
    final nonce = base64Decode('${envelope['nonce']}');
    final data = base64Decode('${envelope['data']}');
    return jsonDecode(utf8.decode(aesGcmOpen(key, nonce, data, aad: _aad)));
  }
}
