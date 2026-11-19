import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/core/database/app_database.dart';
import 'package:pennywise/features/ledger/data/ledger_store.dart';

/// Joining data made without an account into the account (sign-in merge).
void main() {
  late AppDatabase db;
  late LedgerStore store;
  late DateTime clock;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    clock = DateTime.utc(2026, 11, 20, 9);
    store = LedgerStore(
      db,
      now: () => clock = clock.add(const Duration(seconds: 1)),
    );
  });
  tearDown(() => db.close());

  /// A category that came from the account (pulled from the server).
  Future<void> accountCategory(String id, String name, {String? parentId}) => db
      .into(db.categories)
      .insert(
        CategoriesCompanion.insert(
          id: id,
          name: name,
          kind: 'expense',
          parentId: Value(parentId),
          updatedAt: DateTime.utc(2026, 11, 1),
          serverVersion: const Value(3),
        ),
      );

  Future<List<OutboxData>> outbox(String entity) =>
      (db.select(db.outbox)..where((o) => o.entity.equals(entity))).get();

  test('a same-name guest category joins the account one', () async {
    await accountCategory('acct-groceries', 'Groceries');
    final guestCat = await store.createCategory(
      name: 'groceries ', // case and spaces do not matter
      kind: 'expense',
    );
    final wallet = await store.createAccount(
      name: 'Wallet',
      type: 'cash',
      currency: 'EUR',
    );
    final tx = await store.createTransaction(
      kind: 'expense',
      accountId: wallet.id,
      amountMinor: 350,
      currency: 'EUR',
      occurredAt: DateTime(2026, 11, 19, 12),
      categoryId: guestCat.id,
    );
    final budget = await store.createBudget(
      categoryId: guestCat.id,
      amountMinor: 20000,
      period: 'monthly',
    );
    final child = await store.createCategory(
      name: 'Organic',
      kind: 'expense',
      parentId: guestCat.id,
    );

    await store.mergeGuestData(toCurrency: 'EUR');

    final moved = await store.getTransaction(tx.id);
    expect(moved!.categoryId, 'acct-groceries');
    final b = await (db.select(
      db.budgets,
    )..where((x) => x.id.equals(budget.id))).getSingle();
    expect(b.categoryId, 'acct-groceries');
    final c = await (db.select(
      db.categories,
    )..where((x) => x.id.equals(child.id))).getSingle();
    expect(c.parentId, 'acct-groceries', reason: 'follows its parent');

    // The guest copy is gone and will never be uploaded.
    final cats = await db.select(db.categories).get();
    expect(cats.where((x) => x.id == guestCat.id), isEmpty);
    expect((await outbox(Entity.category)).map((o) => o.rowId), [child.id]);

    // Changed rows are queued with their new time stamp (or the push
    // would never clear them from the outbox).
    final q = (await outbox(Entity.transaction)).single;
    expect(q.queuedUpdatedAt, moved.updatedAt);
  });

  test('different names are kept apart', () async {
    await accountCategory('acct-food', 'Food & dining');
    final guestCat = await store.createCategory(
      name: 'Coffee',
      kind: 'expense',
    );
    await store.mergeGuestData(toCurrency: 'EUR');
    final cats = await db.select(db.categories).get();
    expect(cats.map((c) => c.id), containsAll(['acct-food', guestCat.id]));
  });

  test('budgets and goals switch to the account main currency', () async {
    final budget = await store.createBudget(
      amountMinor: 10000, // 100.00 USD
      period: 'monthly',
    );
    final goal = await store.createGoal(name: 'Bike', targetMinor: 50000);
    await store.addContribution(
      goalId: goal.id,
      amountMinor: 2000,
      date: DateTime(2026, 11, 19),
    );

    await store.mergeGuestData(
      fromCurrency: 'USD',
      toCurrency: 'JPY',
      rate: '150',
    );

    final b = await (db.select(
      db.budgets,
    )..where((x) => x.id.equals(budget.id))).getSingle();
    expect(b.amountMinor, 15000, reason: '100 USD = 15,000 JPY (0 decimals)');
    final g = await (db.select(
      db.goals,
    )..where((x) => x.id.equals(goal.id))).getSingle();
    expect(g.targetMinor, 75000);
    final contribution = await db.select(db.goalContributions).getSingle();
    expect(contribution.amountMinor, 3000);
  });

  test('without a rate the amounts are kept', () async {
    final budget = await store.createBudget(
      amountMinor: 10000,
      period: 'monthly',
    );
    await store.mergeGuestData(fromCurrency: 'USD', toCurrency: 'JPY');
    final b = await (db.select(
      db.budgets,
    )..where((x) => x.id.equals(budget.id))).getSingle();
    expect(b.amountMinor, 10000);
  });
}
