import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/core/storage/hive_pref_util.dart';
import 'package:pure_live/core/storage/secure_credential_store.dart';

class _FakeBackend implements SecureKeyValueBackend {
  final Map<String, String> values = <String, String>{};
  bool failReads = false;
  bool failWrites = false;

  /// Writes succeed but store something else, so verification must catch it.
  bool corruptWrites = false;

  @override
  Future<Map<String, String>> readAll() async {
    if (failReads) throw StateError('no keyring');
    return Map<String, String>.of(values);
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('keychain refused');
    values[key] = corruptWrites ? 'garbled' : value;
  }

  @override
  Future<void> delete(String key) async {
    if (failWrites) throw StateError('keychain refused');
    values.remove(key);
  }
}

/// Credentials move from the settings database into the secure store without
/// ever being lost, and stay usable where there is no secure store.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const keys = <String>['douyuCookie', 'douyuLtp0'];

  setUpAll(() async {
    await Hive.openBox<dynamic>('app_settings', bytes: Uint8List(0));
    await HivePrefUtil.init();
  });

  tearDownAll(() async {
    await Hive.close();
  });

  setUp(() async {
    SecureCredentialStore.resetForTest();
    for (final key in keys) {
      await HivePrefUtil.remove(key);
    }
  });

  test('moves plaintext values over, then removes them from the settings database', () async {
    await HivePrefUtil.setString('douyuCookie', 'dy_auth=secret');
    await HivePrefUtil.setString('douyuLtp0', 'long-term');
    final backend = _FakeBackend();

    await SecureCredentialStore.initialize(keys: keys, backend: backend);

    expect(SecureCredentialStore.isAvailable, isTrue);
    expect(backend.values, {'douyuCookie': 'dy_auth=secret', 'douyuLtp0': 'long-term'});
    expect(SecureCredentialStore.read('douyuCookie'), 'dy_auth=secret');
    expect(HivePrefUtil.containsKey('douyuCookie'), isFalse);
    expect(HivePrefUtil.containsKey('douyuLtp0'), isFalse);
  });

  test('writes and deletes go to the secure store only', () async {
    final backend = _FakeBackend();
    await SecureCredentialStore.initialize(keys: keys, backend: backend);

    SecureCredentialStore.write('douyuCookie', 'dy_auth=new');
    await SecureCredentialStore.flush();
    expect(backend.values['douyuCookie'], 'dy_auth=new');
    expect(HivePrefUtil.getString('douyuCookie'), isNull);

    SecureCredentialStore.write('douyuCookie', '');
    await SecureCredentialStore.flush();
    expect(backend.values.containsKey('douyuCookie'), isFalse);
    expect(SecureCredentialStore.read('douyuCookie'), isNull);
  });

  test('without a secure store everything stays in the settings database', () async {
    await HivePrefUtil.setString('douyuCookie', 'dy_auth=secret');
    final backend = _FakeBackend()..failReads = true;

    await SecureCredentialStore.initialize(keys: keys, backend: backend);

    expect(SecureCredentialStore.isAvailable, isFalse);
    expect(SecureCredentialStore.read('douyuCookie'), 'dy_auth=secret');
    SecureCredentialStore.write('douyuLtp0', 'long-term');
    await Future<void>.delayed(Duration.zero);
    expect(HivePrefUtil.getString('douyuLtp0'), 'long-term');
  });

  test('a copy that does not verify keeps the plaintext and the old storage', () async {
    await HivePrefUtil.setString('douyuCookie', 'dy_auth=secret');
    final backend = _FakeBackend()..corruptWrites = true;

    await SecureCredentialStore.initialize(keys: keys, backend: backend);

    expect(SecureCredentialStore.isAvailable, isFalse);
    expect(HivePrefUtil.getString('douyuCookie'), 'dy_auth=secret');
    expect(SecureCredentialStore.read('douyuCookie'), 'dy_auth=secret');
  });

  test('a later failed write is kept in the settings database for the next start', () async {
    final backend = _FakeBackend();
    await SecureCredentialStore.initialize(keys: keys, backend: backend);

    backend.failWrites = true;
    SecureCredentialStore.write('douyuCookie', 'dy_auth=renewed');
    await SecureCredentialStore.flush();
    expect(HivePrefUtil.getString('douyuCookie'), 'dy_auth=renewed');

    // Next start: the fallback copy is the newer value and moves over.
    backend.failWrites = false;
    SecureCredentialStore.resetForTest();
    await SecureCredentialStore.initialize(keys: keys, backend: backend);
    expect(backend.values['douyuCookie'], 'dy_auth=renewed');
    expect(HivePrefUtil.containsKey('douyuCookie'), isFalse);
  });
}
