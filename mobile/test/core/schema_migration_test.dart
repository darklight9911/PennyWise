import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/core/database/app_database.dart';
import 'package:pennywise/features/ledger/data/ledger_store.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('a version-1 database (Milestone 1 build) upgrades to the current version and keeps its data', () async {
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
    expect(
      raw.select('PRAGMA user_version').single.values.single,
      db.schemaVersion,
    );

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

  test(
    'a version-2 database upgrades to version 3 (budgets) and keeps its data',
    () async {
      final raw = sqlite3.openInMemory();
      // Create a real v2 database, then pretend the app was upgraded.
      final v2 = AppDatabase(
        NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
      );
      final store = LedgerStore(v2);
      final a = await store.createAccount(
        name: 'Bank',
        type: 'bank',
        currency: 'USD',
      );
      raw.execute('DROP TABLE budgets');
      // ...and without the v4 additions, so it really is a v2 database.
      raw.execute('DROP TABLE goals');
      raw.execute('DROP TABLE goal_contributions');
      raw.execute('DROP TABLE recurring_rules');
      raw.execute('DROP INDEX transactions_occurrence_key');
      raw.execute('ALTER TABLE transactions DROP COLUMN recurring_id');
      raw.execute('ALTER TABLE transactions DROP COLUMN occurrence_date');
      raw.execute('ALTER TABLE transactions DROP COLUMN fx_rate_source');
      raw.execute('DROP TABLE receipts');
      raw.execute('DROP INDEX transactions_due_idx');
      raw.execute('ALTER TABLE transactions DROP COLUMN due_id');
      raw.execute('DROP TABLE dues');
      raw.execute('PRAGMA user_version = 2');
      await v2.close();

      final v3 = AppDatabase(NativeDatabase.opened(raw));
      addTearDown(v3.close);
      final store3 = LedgerStore(v3);
      expect((await store3.watchAccounts().first).single.id, a.id);
      final b = await store3.createBudget(amountMinor: 100, period: 'weekly');
      expect((await store3.watchBudgets().first).single.id, b.id);
      expect(
        raw.select('PRAGMA user_version').single.values.single,
        v3.schemaVersion,
      );
    },
  );

  test('a version-3 database upgrades to version 4 (goals, recurring) and keeps its data', () async {
    final raw = sqlite3.openInMemory();
    final v3 = AppDatabase(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
    );
    final store = LedgerStore(v3);
    final a = await store.createAccount(
      name: 'Bank',
      type: 'bank',
      currency: 'USD',
    );
    final food = await store.createCategory(name: 'Food', kind: 'expense');
    final t = await store.createTransaction(
      kind: 'expense',
      accountId: a.id,
      amountMinor: 1,
      currency: 'USD',
      occurredAt: DateTime(2026, 11, 1),
      categoryId: food.id,
    );
    // Make it look exactly like a v3 database.
    raw.execute('DROP TABLE goals');
    raw.execute('DROP TABLE goal_contributions');
    raw.execute('DROP TABLE recurring_rules');
    raw.execute('DROP INDEX transactions_occurrence_key');
    raw.execute('ALTER TABLE transactions DROP COLUMN recurring_id');
    raw.execute('ALTER TABLE transactions DROP COLUMN occurrence_date');
    raw.execute('ALTER TABLE transactions DROP COLUMN fx_rate_source');
    raw.execute('DROP TABLE receipts');
    raw.execute('DROP INDEX transactions_due_idx');
    raw.execute('ALTER TABLE transactions DROP COLUMN due_id');
    raw.execute('DROP TABLE dues');
    raw.execute('PRAGMA user_version = 3');
    await v3.close();

    final v4 = AppDatabase(NativeDatabase.opened(raw));
    addTearDown(v4.close);
    final store4 = LedgerStore(v4);
    final old = await store4.getTransaction(t.id);
    expect(old!.recurringId, isNull, reason: 'old rows keep working');
    final g = await store4.createGoal(name: 'Trip', targetMinor: 100);
    expect((await store4.watchGoalProgress().first).single.goal.id, g.id);
    expect(
      raw.select('PRAGMA user_version').single.values.single,
      v4.schemaVersion,
    );
  });

  test('a version-4 database gets fx_rate_source and receipts', () async {
    final raw = sqlite3.openInMemory();
    final v4 = AppDatabase(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
    );
    final store = LedgerStore(v4);
    final a = await store.createAccount(
      name: 'Wallet',
      type: 'cash',
      currency: 'EUR',
    );
    final food = await store.createCategory(name: 'Food', kind: 'expense');
    final t = await store.createTransaction(
      kind: 'expense',
      accountId: a.id,
      amountMinor: 1000,
      currency: 'EUR',
      occurredAt: DateTime(2026, 11, 1),
      categoryId: food.id,
    );
    raw.execute('ALTER TABLE transactions DROP COLUMN fx_rate_source');
    raw.execute('DROP TABLE receipts');
    raw.execute('DROP INDEX transactions_due_idx');
    raw.execute('ALTER TABLE transactions DROP COLUMN due_id');
    raw.execute('DROP TABLE dues');
    raw.execute('PRAGMA user_version = 4');
    await v4.close();

    final v5 = AppDatabase(NativeDatabase.opened(raw));
    addTearDown(v5.close);
    final store5 = LedgerStore(v5);
    expect((await store5.getTransaction(t.id))!.fxRateSource, isNull);
    final typed = await store5.createTransaction(
      kind: 'expense',
      accountId: a.id,
      amountMinor: 1000,
      currency: 'EUR',
      occurredAt: DateTime(2026, 11, 2),
      categoryId: food.id,
      baseCurrency: 'USD',
      manualRate: '1.1',
    );
    expect(typed.fxRateSource, 'manual');
    expect(
      await v5.select(v5.receipts).get(),
      isEmpty,
      reason: 'v6 table exists',
    );
    expect(typed.amountBaseMinor, 1100);
    expect(
      raw.select('PRAGMA user_version').single.values.single,
      v5.schemaVersion,
    );
  });

  test('a version-6 database gets dues and transactions.due_id', () async {
    final raw = sqlite3.openInMemory();
    final v6 = AppDatabase(
      NativeDatabase.opened(raw, closeUnderlyingOnClose: false),
    );
    final store = LedgerStore(v6);
    final a = await store.createAccount(
      name: 'Cash',
      type: 'cash',
      currency: 'USD',
    );
    final food = await store.createCategory(name: 'Food', kind: 'expense');
    final t = await store.createTransaction(
      kind: 'expense',
      accountId: a.id,
      amountMinor: 500,
      currency: 'USD',
      occurredAt: DateTime(2026, 11, 1),
      categoryId: food.id,
    );
    raw.execute('DROP INDEX transactions_due_idx');
    raw.execute('ALTER TABLE transactions DROP COLUMN due_id');
    raw.execute('DROP TABLE dues');
    raw.execute('PRAGMA user_version = 6');
    await v6.close();

    final v7 = AppDatabase(NativeDatabase.opened(raw));
    addTearDown(v7.close);
    final old = await LedgerStore(v7).getTransaction(t.id);
    expect(old!.dueId, isNull, reason: 'old rows keep working');
    expect(await v7.select(v7.dues).get(), isEmpty);
    expect(
      raw.select(
        "SELECT name FROM sqlite_master WHERE name = 'transactions_due_idx'",
      ),
      hasLength(1),
    );
    expect(
      raw.select('PRAGMA user_version').single.values.single,
      v7.schemaVersion,
    );
  });
}
