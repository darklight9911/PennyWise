import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/core/database/app_database.dart';
import 'package:pennywise/features/ledger/data/ledger_store.dart';

void main() {
  late AppDatabase db;
  late LedgerStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = LedgerStore(db);
  });
  tearDown(() => db.close());

  final today = DateTime(2026, 11, 18); // a Wednesday

  test('period starts: Monday for weeks, the 1st for months', () {
    String ymd(DateTime d) => d.toIso8601String().substring(0, 10);
    expect(ymd(budgetPeriodStart('weekly', today)), '2026-11-16');
    expect(
      ymd(budgetPeriodStart('weekly', DateTime(2026, 11, 22))),
      '2026-11-16',
      reason: 'Sunday',
    );
    expect(ymd(budgetPeriodStart('monthly', today)), '2026-11-01');
    expect(
      ymd(budgetPeriodEnd('monthly', DateTime.utc(2026, 12))),
      '2027-01-01',
    );
  });

  test(
    'create, update and delete are queued for sync; levels are cleaned',
    () async {
      final b = await store.createBudget(
        amountMinor: 50000,
        period: 'monthly',
        alertThresholds: [100, 80, 80, 0],
      );
      expect(b.alertThresholds, '80,100');
      final updated = await store.updateBudget(b.copyWith(amountMinor: 60000));
      expect(updated.amountMinor, 60000);
      final queued = await db.select(db.outbox).get();
      expect(queued.single.entity, Entity.budget);
      await store.deleteBudget(b.id);
      expect(await store.watchBudgets().first, isEmpty);
      expect(parseLevels('80, 100,x'), [80, 100]);
    },
  );

  test(
    'spending counts this period, sub-categories, base currency only',
    () async {
      final usd = await store.createAccount(
        name: 'Bank',
        type: 'bank',
        currency: 'USD',
      );
      final eur = await store.createAccount(
        name: 'Euro',
        type: 'bank',
        currency: 'EUR',
      );
      final food = await store.createCategory(name: 'Food', kind: 'expense');
      final snacks = await store.createCategory(
        name: 'Snacks',
        kind: 'expense',
        parentId: food.id,
      );
      final fun = await store.createCategory(name: 'Fun', kind: 'expense');
      final salary = await store.createCategory(name: 'Salary', kind: 'income');

      final foodBudget = await store.createBudget(
        categoryId: food.id,
        amountMinor: 10000,
        period: 'monthly',
      );
      final weekBudget = await store.createBudget(
        amountMinor: 5000,
        period: 'weekly',
      );

      Future<void> spend(
        String acct,
        String cur,
        String? cat,
        int amount,
        DateTime when, {
        String kind = TxKind.expense,
      }) => store.createTransaction(
        kind: kind,
        accountId: acct,
        amountMinor: amount,
        currency: cur,
        occurredAt: when,
        categoryId: cat,
      );

      await spend(
        usd.id,
        'USD',
        food.id,
        2000,
        DateTime(2026, 11, 3),
      ); // month: yes, week: no
      await spend(
        usd.id,
        'USD',
        snacks.id,
        1000,
        DateTime(2026, 11, 17),
      ); // child: yes; week: yes
      await spend(
        usd.id,
        'USD',
        fun.id,
        700,
        DateTime(2026, 11, 18),
      ); // food: no; week: yes
      await spend(
        usd.id,
        'USD',
        food.id,
        9999,
        DateTime(2026, 10, 31),
      ); // last month: no
      await spend(
        eur.id,
        'EUR',
        food.id,
        500,
        DateTime(2026, 11, 18),
      ); // other currency, no base yet: no
      await spend(
        usd.id,
        'USD',
        salary.id,
        9000,
        DateTime(2026, 11, 18),
        kind: TxKind.income,
      ); // income: no
      final gone = await store.createTransaction(
        kind: TxKind.expense,
        accountId: usd.id,
        amountMinor: 4444,
        currency: 'USD',
        occurredAt: DateTime(2026, 11, 18),
        categoryId: food.id,
      );
      await store.deleteTransaction(gone.id); // deleted: no

      final progress = {
        for (final p in await store.watchBudgetProgress('USD', today).first)
          p.budget.id: p,
      };
      expect(progress[foodBudget.id]!.spentMinor, 3000);
      expect(progress[foodBudget.id]!.periodStart, '2026-11-01');
      expect(progress[weekBudget.id]!.spentMinor, 1700);
      expect(progress[weekBudget.id]!.periodStart, '2026-11-16');
      expect(progress[weekBudget.id]!.fraction, closeTo(0.34, 1e-9));
      expect(progress[foodBudget.id]!.leftMinor, 7000);

      // Once the server fills the base amount, the EUR expense counts too.
      final eurTx = (await store.watchTransactions().first).firstWhere(
        (t) => t.currency == 'EUR',
      );
      await (db.update(db.transactions)..where((t) => t.id.equals(eurTx.id)))
          .write(const TransactionsCompanion(amountBaseMinor: Value(540)));
      final after = {
        for (final p in await store.watchBudgetProgress('USD', today).first)
          p.budget.id: p,
      };
      expect(after[foodBudget.id]!.spentMinor, 3540);
    },
  );
}
