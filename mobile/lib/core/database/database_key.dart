import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps the key of the local database in the Android Keystore / iOS Keychain.
///
/// The key is random (256 bits) and never leaves the phone. It is not a
/// password the user types, and the server never sees it.
abstract class DatabaseKeyStore {
  /// The stored key, or null if there is none yet.
  Future<String?> read();

  /// Creates and stores a new random key, replacing any old one.
  Future<String> create();

  Future<void> delete();
}

String generateHexKey([Random? random]) {
  final r = random ?? Random.secure();
  final bytes = List<int>.generate(32, (_) => r.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

class SecureDatabaseKeyStore implements DatabaseKeyStore {
  SecureDatabaseKeyStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              // Never synced to iCloud or restored onto another phone.
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;
  static const _key = 'local_db_key';

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<String> create() async {
    final key = generateHexKey();
    await _storage.write(key: _key, value: key);
    return key;
  }

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// For tests.
class InMemoryDatabaseKeyStore implements DatabaseKeyStore {
  String? key;

  @override
  Future<String?> read() async => key;

  @override
  Future<String> create() async => key = generateHexKey();

  @override
  Future<void> delete() async => key = null;
}
