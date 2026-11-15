import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/core/database/app_database.dart';
import 'package:pennywise/features/ledger/data/ledger_store.dart';

void main() {
  late AppDatabase db;
  late LedgerStore store;
  late DateTime clock;
  var writes = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    clock = DateTime.utc(2026, 11, 15, 9);
    store = LedgerStore(
      db,
      now: () => clock = clock.add(const Duration(seconds: 1)),
    )..onLocalWrite = () => writes++;
    writes = 0;
  });
  tearDown(() => db.close());

  Future<List<OutboxData>> outbox() => db.select(db.outbox).get();

  test(
    'every write is queued in the outbox, in the same transaction',
    () async {
      final a = await store.createAccount(
        name: ' Wallet ',
        type: 'cash',
        currency: 'USD',
      );
      expect(a.name, 'Wallet', reason: 'trimmed');
      final o = await outbox();
      expect(o.single.entity, Entity.account);
      expect(o.single.rowId, a.id);
      expect(o.single.queuedUpdatedAt, a.updatedAt);
      expect(writes, 1, reason: 'sync is told about the write');
    },
  );

  test(
    'many offline edits of one row leave ONE outbox entry (the latest)',
    () async {
      var a = await store.createAccount(
        name: 'Wallet',
        type: 'cash',
        currency: 'USD',
      );
      a = await store.updateAccount(a.copyWith(name: 'Cash'));
      a = await store.updateAccount(a.copyWith(name: 'Cash wallet'));
      final o = await outbox();
      expect(o, hasLength(1));
      expect(o.single.queuedUpdatedAt, a.updatedAt);
    },
  );

  test('ids are UUID v7 and edit times always move forward', () async {
    final a = await store.createAccount(
      name: 'A',
      type: 'bank',
      currency: 'USD',
    );
    expect(
      a.id,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    final b = await store.updateAccount(a.copyWith(name: 'B'));
    expect(b.updatedAt.isAfter(a.updatedAt), isTrue);
  });

  test(
    'balances: opening + income − expense − transfers out + transfers in',
    () async {
      final bank = await store.createAccount(
        name: 'Bank',
        type: 'bank',
        currency: 'USD',
        openingBalanceMinor: 100000,
      );
      final cash = await store.createAccount(
        name: 'Cash',
        type: 'cash',
        currency: 'USD',
      );
      final food = await store.createCategory(name: 'Food', kind: 'expense');
      final salary = await store.createCategory(name: 'Salary', kind: 'income');
      final when = DateTime.utc(2026, 11, 10, 12);

      await store.createTransaction(
        kind: TxKind.income,
        accountId: bank.id,
        amountMinor: 250000,
        currency: 'USD',
        occurredAt: when,
        categoryId: salary.id,
      );
      await store.createTransaction(
        kind: TxKind.expense,
        accountId: bank.id,
        amountMinor: 1250,
        currency: 'USD',
        occurredAt: when,
        categoryId: food.id,
      );
      await store.createTransaction(
        kind: TxKind.transfer,
        accountId: bank.id,
        amountMinor: 20000,
        currency: 'USD',
        occurredAt: when,
        transferAccountId: cash.id,
        transferAmountMinor: 20000,
      );
      await store.createTransaction(
        kind: TxKind.expense,
        accountId: cash.id,
        amountMinor: 350,
        currency: 'USD',
        occurredAt: when,
        categoryId: food.id,
      );

      final balances = await store.watchBalances().first;
      expect(balances[bank.id], 100000 + 250000 - 1250 - 20000);
      expect(balances[cash.id], 20000 - 350);
    },
  );

  test(
    'month totals count income and expenses, not transfers, by local date',
    () async {
      final bank = await store.createAccount(
        name: 'Bank',
        type: 'bank',
        currency: 'USD',
      );
      final cash = await store.createAccount(
        name: 'Cash',
        type: 'cash',
        currency: 'USD',
      );
      final food = await store.createCategory(name: 'Food', kind: 'expense');
      final salary = await store.createCategory(name: 'Salary', kind: 'income');
      final nov = DateTime(2026, 11, 20, 12); // local time
      final oct = DateTime(2026, 10, 31, 12);

      await store.createTransaction(
        kind: TxKind.income,
        accountId: bank.id,
        amountMinor: 5000,
        currency: 'USD',
        occurredAt: nov,
        categoryId: salary.id,
      );
      await store.createTransaction(
        kind: TxKind.expense,
        accountId: bank.id,
        amountMinor: 700,
        currency: 'USD',
        occurredAt: nov,
        categoryId: food.id,
      );
      await store.createTransaction(
        kind: TxKind.expense,
        accountId: bank.id,
        amountMinor: 999,
        currency: 'USD',
        occurredAt: oct,
        categoryId: food.id,
      );
      await store.createTransaction(
        kind: TxKind.transfer,
        accountId: bank.id,
        amountMinor: 100,
        currency: 'USD',
        occurredAt: nov,
        transferAccountId: cash.id,
        transferAmountMinor: 100,
      );

      final totals = await store.watchMonthTotals('2026-11', 'USD').first;
      expect(totals.incomeMinor, 5000);
      expect(totals.expenseMinor, 700);
      expect(
        (await store.watchMonthTotals('2026-11', 'EUR').first).expenseMinor,
        0,
      );
    },
  );

  test(
    'deleting an account deletes its transactions too, and queues all of them',
    () async {
      final bank = await store.createAccount(
        name: 'Bank',
        type: 'bank',
        currency: 'USD',
      );
      final cash = await store.createAccount(
        name: 'Cash',
        type: 'cash',
        currency: 'USD',
      );
      final food = await store.createCategory(name: 'Food', kind: 'expense');
      final when = DateTime.utc(2026, 11, 10);
      final t1 = await store.createTransaction(
        kind: TxKind.expense,
        accountId: bank.id,
        amountMinor: 1,
        currency: 'USD',
        occurredAt: when,
        categoryId: food.id,
      );
      final t2 = await store.createTransaction(
        kind: TxKind.transfer,
        accountId: cash.id,
        amountMinor: 5,
        currency: 'USD',
        occurredAt: when,
        transferAccountId: bank.id,
        transferAmountMinor: 5,
      );
      final keep = await store.createTransaction(
        kind: TxKind.expense,
        accountId: cash.id,
        amountMinor: 2,
        currency: 'USD',
        occurredAt: when,
        categoryId: food.id,
      );

      await store.deleteAccount(bank.id);

      expect((await store.watchAccounts().first).map((a) => a.id), [cash.id]);
      expect((await store.watchTransactions().first).map((t) => t.id), [
        keep.id,
      ]);
      final queued = {for (final o in await outbox()) o.rowId: o};
      for (final id in [bank.id, t1.id, t2.id]) {
        expect(queued[id], isNotNull, reason: '$id must sync its deletion');
      }
      final deleted = await store.getTransaction(t1.id);
      expect(
        deleted!.deletedAt,
        isNotNull,
        reason: 'soft delete keeps the row',
      );
    },
  );

  test('deleting a category also deletes its sub-categories', () async {
    final food = await store.createCategory(name: 'Food', kind: 'expense');
    final snacks = await store.createCategory(
      name: 'Snacks',
      kind: 'expense',
      parentId: food.id,
    );
    await store.deleteCategory(food.id);
    expect(await store.watchCategories().first, isEmpty);
    final index = await store.watchCategoryIndex().first;
    expect(index[snacks.id]!.deletedAt, isNotNull);
    expect(
      index[food.id]!.name,
      'Food',
      reason: 'old transactions can still show the name',
    );
  });

  test('editing a transaction stores its local date and clears server-computed amounts', () async {
    final bank = await store.createAccount(
      name: 'Bank',
      type: 'bank',
      currency: 'USD',
    );
    final food = await store.createCategory(name: 'Food', kind: 'expense');
    var t = await store.createTransaction(
      kind: TxKind.expense,
      accountId: bank.id,
      amountMinor: 100,
      currency: 'USD',
      occurredAt: DateTime(2026, 11, 3, 23, 30),
      categoryId: food.id,
    );
    expect(t.localDate, '2026-11-03');

    // Pretend the server filled the base amount, then the user edits.
    await (db.update(db.transactions)..where((x) => x.id.equals(t.id))).write(
      const TransactionsCompanion(
        amountBaseMinor: Value(100),
        fxRateToBase: Value('1'),
      ),
    );
    t = (await store.getTransaction(t.id))!;
    t = await store.updateTransaction(
      t.copyWith(amountMinor: 250, occurredAt: DateTime(2026, 11, 4, 8)),
    );
    expect(t.localDate, '2026-11-04');
    expect(t.amountBaseMinor, isNull, reason: 'the server recomputes it');
  });

  test('editing a rejected row re-queues it for another try', () async {
    final a = await store.createAccount(
      name: 'A',
      type: 'bank',
      currency: 'USD',
    );
    await (db.update(db.outbox)..where((o) => o.rowId.equals(a.id))).write(
      const OutboxCompanion(
        rejectedCode: Value('invalid'),
        rejectedMessage: Value('bad'),
      ),
    );
    expect(await store.watchPendingCount().first, 0);
    expect(await store.watchRejected().first, hasLength(1));

    await store.updateAccount(a.copyWith(name: 'Fixed'));
    expect(await store.watchPendingCount().first, 1);
    expect(await store.watchRejected().first, isEmpty);
  });

  test('localDateOf uses the phone time zone', () {
    expect(localDateOf(DateTime(2026, 3, 31, 23, 30)), '2026-03-31');
  });
}
