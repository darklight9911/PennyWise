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
    : super(
        file: () async => File('unused'),
        keys: InMemoryDatabaseKeyStore(),
      ) {
    // Every fake has its own in-memory database (its own executor), which is
    // safe. Widget tests cannot always close them (closing waits on live
    // queries, and time only moves while a test pumps), so silence drift's
    // "created multiple times" warning for these test-only databases.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  }

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
