import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pure_live/core/storage/hive_pref_util.dart';

/// Where credentials are kept: the platform's secure store.
abstract interface class SecureKeyValueBackend {
  Future<Map<String, String>> readAll();
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// [FlutterSecureStorage]: Android Keystore-backed encryption, the Apple
/// keychain, Windows DPAPI and libsecret on Linux.
class FlutterSecureBackend implements SecureKeyValueBackend {
  const FlutterSecureBackend();

  // The legacy macOS keychain: the data-protection keychain needs a signed
  // keychain-access-groups entitlement that unsigned and ad-hoc builds lack.
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  @override
  Future<Map<String, String>> readAll() => _storage.readAll();

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Account credentials (cookies, Douyu's renewal pair) in the system's secure
/// store instead of the plain settings database.
///
/// The settings code reads credentials synchronously all over the app, so the
/// store is read once at startup into memory; writes go to the secure store in
/// the order they were made.
///
/// Nothing is ever lost on the way:
///
/// - On first start, each value still in the settings database is copied into
///   the secure store and read back; only when every copy checks out are the
///   plaintext ones removed.
/// - Where there is no usable secure store (Linux without a keyring service, a
///   keychain that refuses, a test), values stay in the settings database as
///   before.
/// - A secure write that fails later keeps the value in the settings database,
///   and the next start moves it over again.
abstract final class SecureCredentialStore {
  static SecureKeyValueBackend? _backend;
  static final Map<String, String> _cache = <String, String>{};
  static Future<void> _tail = Future<void>.value();

  /// Whether credentials currently live in the secure store.
  static bool get isAvailable => _backend != null;

  /// Opens the secure store and moves the credentials named [keys] into it.
  static Future<void> initialize({required Iterable<String> keys, SecureKeyValueBackend? backend}) async {
    final candidate = backend ?? const FlutterSecureBackend();
    final keyList = keys.toList(growable: false);

    Map<String, String> stored;
    try {
      stored = await candidate.readAll();
    } catch (error) {
      _log('Secure storage unavailable; credentials stay in the settings database: $error');
      _backend = null;
      return;
    }

    // Phase 1: copy every plaintext value over and verify it, without removing
    // anything yet. A value still in the settings database is the newer one: it
    // is either not migrated yet, or was written there while the secure store
    // was failing.
    final pending = <String, String>{};
    for (final key in keyList) {
      final legacy = HivePrefUtil.getString(key);
      if (legacy != null && legacy.isNotEmpty && stored[key] != legacy) pending[key] = legacy;
    }
    if (pending.isNotEmpty) {
      try {
        for (final entry in pending.entries) {
          await candidate.write(entry.key, entry.value);
        }
        final check = await candidate.readAll();
        for (final entry in pending.entries) {
          if (check[entry.key] != entry.value) throw StateError('verification failed for ${entry.key}');
        }
        stored = check;
      } catch (error) {
        _log('Moving credentials to secure storage failed; keeping them in the settings database: $error');
        _backend = null;
        return;
      }
    }

    _cache
      ..clear()
      ..addAll({
        for (final key in keyList)
          if ((stored[key] ?? '').isNotEmpty) key: stored[key]!,
      });
    _backend = candidate;

    // Phase 2: everything is safely in the secure store; drop the plaintext.
    for (final key in keyList) {
      if (HivePrefUtil.containsKey(key)) await HivePrefUtil.remove(key);
    }
  }

  /// The stored value, or null.
  static String? read(String key) {
    if (_backend != null) return _cache[key];
    return HivePrefUtil.getString(key);
  }

  /// Stores [value]; an empty value removes the credential.
  static void write(String key, String value) {
    final backend = _backend;
    if (backend == null) {
      unawaited(HivePrefUtil.setString(key, value));
      return;
    }
    if (value.isEmpty) {
      _cache.remove(key);
    } else {
      _cache[key] = value;
    }
    _tail = _tail.then((_) async {
      try {
        if (value.isEmpty) {
          await backend.delete(key);
        } else {
          await backend.write(key, value);
        }
        // A fallback copy from an earlier failed write is stale now.
        if (HivePrefUtil.containsKey(key)) await HivePrefUtil.remove(key);
      } catch (error) {
        _log('Secure write failed for $key; kept in the settings database until the next start: $error');
        await HivePrefUtil.setString(key, value);
      }
    });
  }

  /// Completes when every write made so far has reached storage.
  @visibleForTesting
  static Future<void> flush() => _tail;

  @visibleForTesting
  static void resetForTest() {
    _backend = null;
    _cache.clear();
    _tail = Future<void>.value();
  }

  static void _log(String message) => developer.log(message, name: 'SecureCredentialStore');
}
