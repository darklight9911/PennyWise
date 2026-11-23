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

  test("a guest bill follows its joined category", () async {
    await accountCategory('acct-groceries', 'Groceries');
    final guestCat = await store.createCategory(
      name: 'Groceries',
      kind: 'expense',
    );
    final due = await store.createDue(
      direction: DueDirection.iOwe,
      kind: DueKind.bill,
      person: 'Corner shop',
      amountMinor: 1200,
      currency: 'EUR',
      startDate: '2026-11-19',
      categoryId: guestCat.id,
    );
    await store.mergeGuestData(toCurrency: 'EUR');
    final moved = (await store.getDue(due.id))!;
    expect(moved.categoryId, 'acct-groceries');
    expect(moved.amountMinor, 1200, reason: 'dues keep their own currency');
    expect((await outbox(Entity.due)).single.queuedUpdatedAt, moved.updatedAt);
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

  group('main currency without an account', () {
    // Today's rates for 1 EUR (like GET /v1/fx/rates?base=EUR).
    const eurRates = {'USD': '1.25', 'JPY': '160'};

    Future<String> account(String currency) async => (await store.createAccount(
      name: 'A $currency',
      type: 'cash',
      currency: currency,
    )).id;

    test('missing amounts are filled with today\'s rate', () async {
      final usd = await account('USD');
      final tx = await store.createTransaction(
        kind: 'expense',
        accountId: usd,
        amountMinor: 1000, // 10.00 USD, no rate known when saved
        currency: 'USD',
        occurredAt: DateTime(2026, 11, 19),
        baseCurrency: 'EUR',
      );
      expect(tx.amountBaseMinor, isNull);
      expect(await store.hasMissingBaseAmounts('EUR'), isTrue);

      expect(await store.fillMissingBaseAmounts('EUR', eurRates), 1);
      final filled = await store.getTransaction(tx.id);
      expect(filled!.amountBaseMinor, 800, reason: '10 USD / 1.25 = 8 EUR');
      expect(filled.fxRateSource, 'auto');
      expect(await store.hasMissingBaseAmounts('EUR'), isFalse);
    });

    test('changing it converts everything, typed rates included', () async {
      final usd = await account('USD');
      final jpy = await account('JPY');
      // In USD (the old main currency): 20.00 USD.
      final a = await store.createTransaction(
        kind: 'expense',
        accountId: usd,
        amountMinor: 2000,
        currency: 'USD',
        occurredAt: DateTime(2026, 11, 19),
        baseCurrency: 'USD',
      );
      // In JPY with a typed rate: 1 JPY = 0.007 USD.
      final b = await store.createTransaction(
        kind: 'expense',
        accountId: jpy,
        amountMinor: 1000,
        currency: 'JPY',
        occurredAt: DateTime(2026, 11, 19),
        baseCurrency: 'USD',
        manualRate: '0.007',
      );
      final budget = await store.createBudget(
        amountMinor: 10000, // 100.00 USD
        period: 'monthly',
      );

      await store.rebaseLocally(
        oldBase: 'USD',
        newBase: 'EUR',
        rates: eurRates,
      );

      final a2 = await store.getTransaction(a.id);
      expect(a2!.amountBaseMinor, 1600, reason: '20 USD / 1.25');
      final b2 = await store.getTransaction(b.id);
      expect(b2!.fxRateSource, 'manual', reason: 'the typed rate is kept');
      expect(b2.fxRateToBase, '0.0056', reason: '0.007 USD x 0.8 EUR/USD');
      expect(b2.amountBaseMinor, 560, reason: '1000 JPY = 5.60 EUR');
      final bud = await (db.select(
        db.budgets,
      )..where((x) => x.id.equals(budget.id))).getSingle();
      expect(bud.amountMinor, 8000);
    });

    test('no rate for the old currency: nothing changes', () async {
      final usd = await account('USD');
      await store.createTransaction(
        kind: 'expense',
        accountId: usd,
        amountMinor: 2000,
        currency: 'USD',
        occurredAt: DateTime(2026, 11, 19),
        baseCurrency: 'USD',
      );
      await expectLater(
        store.rebaseLocally(oldBase: 'USD', newBase: 'EUR', rates: const {}),
        throwsStateError,
      );
      final rows = await db.select(db.transactions).get();
      expect(rows.single.amountBaseMinor, 2000);
    });
  });
}
