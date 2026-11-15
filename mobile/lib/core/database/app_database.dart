import 'package:drift/drift.dart';

part 'app_database.g.dart';

/// Small key/value facts about the local data, e.g. the sync cursor
/// (the last server version this phone has downloaded, Milestone 3).
class LocalMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// The phone's local database. The UI reads from here (offline-first).
///
/// Tables for accounts, categories and transactions arrive in Milestone 2.
@DriftDatabase(tables: [LocalMeta])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      // Enforce foreign keys (off by default in SQLite).
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<String?> readMeta(String key) async {
    final row = await (select(
      localMeta,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> writeMeta(String key, String value) => into(
    localMeta,
  ).insertOnConflictUpdate(LocalMetaCompanion.insert(key: key, value: value));
}
