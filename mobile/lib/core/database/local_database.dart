import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'app_database.dart';
import 'database_key.dart';
import 'encryption.dart';

/// Opens the encrypted local database and wipes it on logout.
///
/// Rules:
/// - One random key per login. Logging out deletes the database AND its key,
///   so the next person on this phone never sees the old data.
/// - If the key is gone (app data restored onto a new phone, Keychain reset)
///   or does not match, the old file cannot be read by anyone. It is deleted
///   and a fresh, empty database is created; data comes back from the server
///   with sync (Milestone 3).
class LocalDatabase {
  LocalDatabase({
    required Future<File> Function() file,
    required DatabaseKeyStore keys,
    QueryExecutor Function(File file, String hexKey)? openExecutor,
  }) : _file = file, // ignore: prefer_initializing_formals
       _keys = keys, // ignore: prefer_initializing_formals
       _openExecutor = openExecutor ?? _backgroundExecutor;

  final Future<File> Function() _file;
  final DatabaseKeyStore _keys;
  final QueryExecutor Function(File, String) _openExecutor;

  Future<AppDatabase>? _opening;
  final _closeHooks = <Future<void> Function()>[];

  /// Runs [hook] before the database is closed or wiped, e.g. so a running
  /// sync can stop first. Returns a function that removes the hook.
  void Function() addCloseHook(Future<void> Function() hook) {
    _closeHooks.add(hook);
    return () => _closeHooks.remove(hook);
  }

  /// Lets everything that uses the database stop. Subclasses call it too.
  @protected
  Future<void> runCloseHooks() async {
    for (final hook in List.of(_closeHooks)) {
      try {
        await hook();
      } on Object catch (e) {
        debugPrint('close hook failed: $e');
      }
    }
  }

  /// The open database (opened on first use).
  Future<AppDatabase> get database =>
      _opening ??= _open().catchError((Object e, StackTrace st) {
        _opening = null;
        Error.throwWithStackTrace(e, st);
      });

  Future<AppDatabase> _open() async {
    final file = await _file();
    var key = await _keys.read();
    if (key == null) {
      await _deleteFiles(file); // unreadable without its key
      key = await _keys.create();
    }
    try {
      _checkKey(file, key);
    } on WrongDatabaseKeyError {
      debugPrint(
        'Local database key mismatch: starting with an empty database.',
      );
      await _deleteFiles(file);
      key = await _keys.create();
      _checkKey(file, key);
    }
    final db = AppDatabase(_openExecutor(file, key));
    await db.customSelect('SELECT 1').get(); // runs migrations now, not later
    return db;
  }

  static const _ownerKey = 'owner_user_id';

  /// Makes sure the local data belongs to [userId]. If another user's data
  /// is on this phone, it is wiped first, so nobody sees someone else's money.
  /// (The same user logging back in after a session expiry keeps their data,
  /// including changes not yet synced.)
  Future<AppDatabase> claimFor(String userId) async {
    var db = await database;
    final owner = await db.readMeta(_ownerKey);
    if (owner != null && owner != userId) {
      await wipe();
      db = await database;
    }
    if (owner != userId) await db.writeMeta(_ownerKey, userId);
    return db;
  }

  /// Deletes all local data and its key (on logout).
  Future<void> wipe() async {
    await runCloseHooks();
    final opening = _opening;
    _opening = null;
    if (opening != null) {
      try {
        await (await opening).close();
      } on Object {
        // It never opened; nothing to close.
      }
    }
    final file = await _file();
    await _deleteFiles(file);
    final photos = Directory(p.join(file.parent.path, 'receipts'));
    if (await photos.exists()) await photos.delete(recursive: true);
    await _keys.delete();
  }

  /// Folder for receipt photos, next to the database (deleted by [wipe]).
  Future<Directory> receiptsDir() async =>
      Directory(p.join((await _file()).parent.path, 'receipts'));

  Future<void> close() async {
    await runCloseHooks();
    final opening = _opening;
    _opening = null;
    if (opening != null) await (await opening).close();
  }

  /// Opens the file once on this isolate to make sure the key works,
  /// so key problems surface as clear errors (not from a background isolate).
  static void _checkKey(File file, String key) {
    file.parent.createSync(recursive: true);
    final raw = sqlite3.open(file.path);
    try {
      unlockDatabase(raw, key);
    } finally {
      raw.close();
    }
  }

  static QueryExecutor _backgroundExecutor(File file, String key) =>
      NativeDatabase.createInBackground(
        file,
        // Runs on every connection of the background isolate.
        setup: (db) => unlockDatabase(db, key),
      );

  static Future<void> _deleteFiles(File file) async {
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final f = File('${file.path}$suffix');
      if (await f.exists()) await f.delete();
    }
  }
}

Future<File> _defaultFile() async {
  // App-private storage, not visible to the user or other apps.
  final dir = await getApplicationSupportDirectory();
  return File(p.join(dir.path, 'pennywise.db'));
}

final localDatabaseProvider = Provider<LocalDatabase>((ref) {
  final local = LocalDatabase(
    file: _defaultFile,
    keys: SecureDatabaseKeyStore(),
  );
  ref.onDispose(() => unawaited(local.close()));
  return local;
});
