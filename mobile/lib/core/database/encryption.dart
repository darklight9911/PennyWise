import 'package:sqlite3/sqlite3.dart';

/// Thrown when the database would NOT be encrypted, e.g. because a build
/// without sqlite3mc was used. The app refuses to store finance data then.
class EncryptionUnavailableError extends StateError {
  EncryptionUnavailableError()
    : super(
        'SQLite was built without encryption support (expected sqlite3mc). '
        'Check hooks.user_defines.sqlite3.source in pubspec.yaml.',
      );
}

/// Thrown when the file exists but cannot be read with this key
/// (wrong key, or not a database at all).
class WrongDatabaseKeyError extends StateError {
  WrongDatabaseKeyError() : super('The local database key does not match.');
}

/// A 256-bit key as 64 hex characters.
final _hexKey = RegExp(r'^[0-9a-f]{64}$');

/// Unlocks [db] with [hexKey]. Must run first on every new connection.
///
/// Fails closed: if this SQLite build cannot encrypt, `PRAGMA key` would be
/// silently ignored and data written in plain text, so we check first.
void unlockDatabase(Database db, String hexKey) {
  if (!_hexKey.hasMatch(hexKey)) {
    throw ArgumentError('database key must be 64 lowercase hex characters');
  }
  final cipher = db.select('PRAGMA cipher');
  if (cipher.isEmpty) throw EncryptionUnavailableError();

  // Raw 256-bit key, so no slow password-based key derivation is needed.
  db.execute("PRAGMA hexkey = '$hexKey'");

  // Reading the schema is the first real read; with a wrong key it fails.
  try {
    db.select('SELECT count(*) FROM sqlite_master');
  } on SqliteException {
    throw WrongDatabaseKeyError();
  }
}
