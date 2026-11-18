import 'package:drift/drift.dart';

import 'tables.dart';

export 'tables.dart';

part 'app_database.g.dart';

/// Small key/value facts about the local data, e.g. the sync cursor
/// (the last server version this phone has downloaded).
class LocalMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// The phone's local database. The UI reads from here (offline-first).
@DriftDatabase(
  tables: [
    LocalMeta,
    Accounts,
    Categories,
    Transactions,
    Outbox,
    Budgets,
    Goals,
    GoalContributions,
    RecurringRules,
    Receipts,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// v1: local_meta. v2: accounts, categories, transactions, outbox.
  /// v3: budgets. v4: goals, contributions, recurring rules, and the
  /// recurring fields on transactions. v5: transactions.fx_rate_source.
  /// v6: receipts.
  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createIndexes();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(accounts);
        await m.createTable(categories);
        await m.createTable(transactions);
        await m.createTable(outbox);
        // Indexes are created at the end of the v4 step (all tables exist then).
      }
      if (from < 3) {
        await m.createTable(budgets);
      }
      if (from < 4) {
        await m.createTable(goals);
        await m.createTable(goalContributions);
        await m.createTable(recurringRules);
        if (from >= 2) {
          // Fresh v2/v3 tables created above already have these columns.
          await m.addColumn(transactions, transactions.recurringId);
          await m.addColumn(transactions, transactions.occurrenceDate);
        }
        await _createIndexes();
      }
      if (from < 5 && from >= 2) {
        // Tables created fresh above already have the column.
        await m.addColumn(transactions, transactions.fxRateSource);
      }
      if (from < 6) {
        await m.createTable(receipts);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _createIndexes() async {
    for (final sql in [
      'CREATE INDEX IF NOT EXISTS transactions_date_idx ON transactions (local_date DESC, occurred_at DESC)',
      'CREATE INDEX IF NOT EXISTS transactions_account_idx ON transactions (account_id)',
      'CREATE INDEX IF NOT EXISTS transactions_transfer_idx ON transactions (transfer_account_id)',
      'CREATE INDEX IF NOT EXISTS transactions_category_idx ON transactions (category_id, local_date)',
      // One row per bill occurrence, like on the server.
      'CREATE UNIQUE INDEX IF NOT EXISTS transactions_occurrence_key ON transactions (recurring_id, occurrence_date) WHERE recurring_id IS NOT NULL',
      'CREATE INDEX IF NOT EXISTS goal_contributions_goal_idx ON goal_contributions (goal_id)',
    ]) {
      await customStatement(sql);
    }
  }

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
