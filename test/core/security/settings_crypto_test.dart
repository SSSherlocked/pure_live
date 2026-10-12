import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/security/settings_crypto.dart';
import 'package:pure_live/features/backup/backup_password_dialog.dart';
import 'package:pure_live/features/remote_receiver/remote_sync_protocol.dart';

void main() {
  group('AES-256-GCM', () {
    test('round-trips, and a changed byte or wrong key is refused', () {
      final key = secureRandomBytes(32);
      final plaintext = Uint8List.fromList(utf8.encode('dy_auth=secret'));
      final sealed = aesGcmSeal(key, plaintext);

      expect(aesGcmOpen(key, sealed.nonce, sealed.ciphertext), plaintext);

      final tampered = Uint8List.fromList(sealed.ciphertext)..[0] ^= 1;
      expect(() => aesGcmOpen(key, sealed.nonce, tampered), throwsA(isA<SealedDataException>()));
      expect(
        () => aesGcmOpen(secureRandomBytes(32), sealed.nonce, sealed.ciphertext),
        throwsA(isA<SealedDataException>()),
      );
    });
  });

  group('BackupCipher', () {
    test('encrypts with a password and refuses a wrong one', () async {
      const json = '{"cookie":{"douyuCookie":"dy_auth=secret"}}';
      final sealed = await BackupCipher.encrypt(json, 'correct horse', iterations: 1000);

      expect(BackupCipher.isEncrypted(sealed), isTrue);
      expect(sealed, isNot(contains('dy_auth')));
      expect(await BackupCipher.decrypt(sealed, 'correct horse'), json);
      await expectLater(BackupCipher.decrypt(sealed, 'wrong'), throwsA(isA<BackupPasswordException>()));
    });

    test('a plain backup is not mistaken for an encrypted one', () {
      expect(BackupCipher.isEncrypted('{"backupVersion": 3}'), isFalse);
      expect(BackupCipher.isEncrypted('not json'), isFalse);
    });

    test('openBackupContent reads plain files and asks again after a wrong password', () async {
      final plain = await openBackupContent('{"a": 1}', askPassword: ({required bool retry}) async => fail('asked'));
      expect(plain, {'a': 1});

      final sealed = await BackupCipher.encrypt('{"a": 2}', 'right password', iterations: 1000);
      final answers = ['wrong password', 'right password'];
      final retries = <bool>[];
      final opened = await openBackupContent(
        sealed,
        askPassword: ({required bool retry}) async {
          retries.add(retry);
          return answers.removeAt(0);
        },
      );
      expect(opened, {'a': 2});
      expect(retries, [false, true]);

      await expectLater(
        openBackupContent(sealed, askPassword: ({required bool retry}) async => null),
        throwsA(isA<BackupDecryptionCancelled>()),
      );
    });
  });

  group('LAN sync key agreement', () {
    test('both sides agree on the key and the pairing code; a third key does not', () {
      final server = SyncKeyPair.generate();
      final client = SyncKeyPair.generate();
      final intruder = SyncKeyPair.generate();

      final serverKey = SyncCipher.sessionKey(
        own: server,
        peerPublicKey: client.publicKey,
        serverPublicKey: server.publicKey,
        clientPublicKey: client.publicKey,
      );
      final clientKey = SyncCipher.sessionKey(
        own: client,
        peerPublicKey: server.publicKey,
        serverPublicKey: server.publicKey,
        clientPublicKey: client.publicKey,
      );
      expect(clientKey, serverKey);
      expect(SyncCipher.pairingCode(clientKey), SyncCipher.pairingCode(serverKey));
      expect(SyncCipher.pairingCode(serverKey), matches(RegExp(r'^\d{6}$')));

      // Someone answering with their own key ends up with a different key, which
      // the pairing code exposes.
      final interceptedKey = SyncCipher.sessionKey(
        own: client,
        peerPublicKey: intruder.publicKey,
        serverPublicKey: intruder.publicKey,
        clientPublicKey: client.publicKey,
      );
      expect(interceptedKey, isNot(serverKey));

      final payload = SyncCipher.sealJson(serverKey, {'cookie': 'secret'});
      expect(jsonEncode(payload), isNot(contains('secret')));
      expect(SyncCipher.openJson(clientKey, payload), {'cookie': 'secret'});
      expect(() => SyncCipher.openJson(interceptedKey, payload), throwsA(isA<SealedDataException>()));
    });

    test('the QR code carries the key fingerprint', () {
      final server = SyncKeyPair.generate();
      final fingerprint = SyncCipher.fingerprint(server.publicKey);
      final uri = RemoteSyncProtocol.createQrUri(ip: '192.168.1.5', port: 39888, fingerprint: fingerprint);

      final parsed = RemoteSyncProtocol.parseQr(uri.toString());
      expect(parsed?.ip, '192.168.1.5');
      expect(parsed?.port, 39888);
      expect(parsed?.fingerprint, fingerprint);
      expect(fingerprint, matches(RegExp(r'^[0-9a-f]{24}$')));

      // An older QR (no fingerprint) and a typed address still parse.
      expect(RemoteSyncProtocol.parseQr('purelive://192.168.1.5:39888/sync')?.fingerprint, isNull);
      expect(RemoteSyncProtocol.parseQr('192.168.1.5:39888')?.port, 39888);
    });
  });
}
