import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:pennywise/core/database/app_database.dart';
import 'package:pennywise/core/database/database_key.dart';
import 'package:pennywise/core/database/local_database.dart';

/// An in-memory LocalDatabase for widget tests (fake-async tests cannot
/// wait on real file I/O). Ownership and wipe behave like the real one.
class FakeLocalDatabase extends LocalDatabase {
  FakeLocalDatabase()
    : super(file: () async => File('unused'), keys: InMemoryDatabaseKeyStore());

  AppDatabase? _db;
  int wipeCount = 0;

  @override
  Future<AppDatabase> get database async =>
      _db ??= AppDatabase(NativeDatabase.memory() as QueryExecutor);

  @override
  Future<void> wipe() async {
    await runCloseHooks();
    wipeCount++;
    await _db?.close();
    _db = null;
  }

  @override
  Future<void> close() async {
    await runCloseHooks();
    await _db?.close();
    _db = null;
  }

  /// Who the local data belongs to, if anyone.
  Future<String?> owner() async => (await database).readMeta('owner_user_id');
}
