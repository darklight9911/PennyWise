import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/core/database/app_database.dart';
import 'package:pennywise/features/ledger/data/ledger_store.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('a version-1 database (Milestone 1 build) upgrades to version 2 and keeps its data', () async {
    // Build exactly what schema v1 created.
    final raw = sqlite3.openInMemory()
      ..execute(
        'CREATE TABLE "local_meta" ("key" TEXT NOT NULL, "value" TEXT NOT NULL, PRIMARY KEY ("key"))',
      )
      ..execute("INSERT INTO local_meta VALUES ('owner_user_id', 'user-1')")
      ..execute('PRAGMA user_version = 1');

    final db = AppDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    expect(
      await db.readMeta('owner_user_id'),
      'user-1',
      reason: 'old data kept',
    );
    final store = LedgerStore(db);
    final a = await store.createAccount(
      name: 'Bank',
      type: 'bank',
      currency: 'USD',
    );
    expect((await store.watchAccounts().first).single.id, a.id);
    expect(raw.select('PRAGMA user_version').single.values.single, 2);

    final indexes = raw
        .select(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'transactions_%'",
        )
        .map((r) => r['name'])
        .toSet();
    expect(
      indexes,
      containsAll(['transactions_date_idx', 'transactions_account_idx']),
    );
  });
}
