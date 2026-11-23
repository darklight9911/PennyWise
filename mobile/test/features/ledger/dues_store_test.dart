import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/core/database/app_database.dart';
import 'package:pennywise/features/ledger/data/ledger_store.dart';

void main() {
  late AppDatabase db;
  late LedgerStore store;
  late Account cash, euro;
  late Category food, work;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = LedgerStore(db);
    cash = await store.createAccount(
      name: 'Cash',
      type: 'cash',
      currency: 'USD',
      openingBalanceMinor: 100000,
    );
    euro = await store.createAccount(
      name: 'Euro',
      type: 'cash',
      currency: 'EUR',
    );
    food = await store.createCategory(name: 'Food', kind: 'expense');
    work = await store.createCategory(name: 'Freelance', kind: 'income');
  });
  tearDown(() => db.close());

  Future<int> balance() async => (await store.watchBalances().first)[cash.id]!;
  Future<MonthTotals> totals() =>
      store.watchMonthTotals('2026-11', 'USD').first;
  Future<DueProgress> progress(Due d) async =>
      (await store.watchDues().first).singleWhere((p) => p.due.id == d.id);
  final nov = DateTime(2026, 11, 20, 12);

  test(
    'money lent: balances move, totals do not; part payments and overpayment',
    () async {
      final d = await store.createDue(
        direction: DueDirection.owedToMe,
        kind: DueKind.loan,
        person: '  Rahim ',
        amountMinor: 30000,
        currency: 'USD',
        startDate: '2026-11-10',
        accountId: cash.id,
        moneyMovedNow: true,
        baseCurrency: 'USD',
      );
      expect(d.person, 'Rahim');
      expect(await balance(), 70000, reason: 'the lent money left the account');
      var t = await totals();
      expect(
        (t.incomeMinor, t.expenseMinor),
        (0, 0),
        reason: 'lending is not spending',
      );

      final p1 = await store.recordDuePayment(
        d,
        amountMinor: 10000,
        accountId: cash.id,
        date: nov,
      );
      expect((p1.kind, p1.dueId, p1.note), (TxKind.loanIn, d.id, 'From Rahim'));
      var p = await progress(d);
      expect((p.paidMinor, p.leftMinor, p.settled), (10000, 20000, false));
      expect(await balance(), 80000);

      expect(
        () => store.recordDuePayment(
          d,
          amountMinor: 20001,
          accountId: cash.id,
          date: nov,
        ),
        throwsA(isA<DueException>()),
      );
      expect(
        () => store.recordDuePayment(
          d,
          amountMinor: 100,
          accountId: euro.id,
          date: nov,
        ),
        throwsA(isA<DueException>()),
        reason: 'the account must be in the due currency',
      );

      await store.settleDue(d, accountId: cash.id, date: nov);
      p = await progress(d);
      expect(
        (p.leftMinor, p.settled, p.status('2026-12-01')),
        (0, true, DueStatus.settled),
      );
      expect(await balance(), 100000);
      t = await totals();
      expect(
        (t.incomeMinor, t.expenseMinor),
        (0, 0),
        reason: 'getting a loan back is not income',
      );
      expect(
        () => store.recordDuePayment(
          d,
          amountMinor: 1,
          accountId: cash.id,
          date: nov,
        ),
        throwsA(isA<DueException>()),
      );
    },
  );

  test('money borrowed: arrives with loan_in, repaid with loan_out', () async {
    final d = await store.createDue(
      direction: DueDirection.iOwe,
      kind: DueKind.loan,
      person: 'Bank of Mum',
      amountMinor: 50000,
      currency: 'USD',
      startDate: '2026-11-01',
      accountId: cash.id,
      moneyMovedNow: true,
    );
    expect(await balance(), 150000);
    final pay = await store.recordDuePayment(
      d,
      amountMinor: 5000,
      accountId: cash.id,
      date: nov,
    );
    expect(pay.kind, TxKind.loanOut);
    expect(await balance(), 145000);
    expect((await progress(d)).leftMinor, 45000);
  });

  test(
    'bills: paying is spending, receiving is income, in their category',
    () async {
      final owe = await store.createDue(
        direction: DueDirection.iOwe,
        kind: DueKind.bill,
        person: 'Corner shop',
        amountMinor: 2500,
        currency: 'USD',
        startDate: '2026-11-02',
        categoryId: food.id,
        moneyMovedNow: true, // ignored for bills
        accountId: cash.id,
      );
      expect(
        await balance(),
        100000,
        reason: 'a bill moves no money until paid',
      );
      final paid = await store.settleDue(
        owe,
        accountId: cash.id,
        date: nov,
        baseCurrency: 'USD',
      );
      expect(
        (paid.kind, paid.categoryId, paid.amountBaseMinor),
        (TxKind.expense, food.id, 2500),
      );

      final owed = await store.createDue(
        direction: DueDirection.owedToMe,
        kind: DueKind.bill,
        person: 'Client',
        amountMinor: 80000,
        currency: 'USD',
        startDate: '2026-11-03',
        categoryId: work.id,
      );
      await store.recordDuePayment(
        owed,
        amountMinor: 30000,
        accountId: cash.id,
        date: nov,
        baseCurrency: 'USD',
      );
      final t = await totals();
      expect((t.incomeMinor, t.expenseMinor), (30000, 2500));
      expect(await balance(), 127500);
    },
  );

  test(
    'forgive and reopen; delete keeps payments; status and reminder',
    () async {
      final d = await store.createDue(
        direction: DueDirection.owedToMe,
        kind: DueKind.loan,
        person: 'Karim',
        amountMinor: 10000,
        currency: 'USD',
        startDate: '2026-11-01',
        dueDate: '2026-11-30',
        remindDaysBefore: 3,
      );
      var p = await progress(d);
      expect(p.status('2026-11-29'), DueStatus.open);
      expect(p.status('2026-12-01'), DueStatus.overdue);
      expect(p.reminderDate, '2026-11-27');

      await store.recordDuePayment(
        d,
        amountMinor: 4000,
        accountId: cash.id,
        date: nov,
      );
      final forgiven = await store.forgiveDue((await store.getDue(d.id))!);
      p = await progress(forgiven);
      expect(
        (p.leftMinor, p.settled, p.forgiven, p.reminderDate),
        (0, true, true, null),
      );
      await store.reopenDue(forgiven);
      expect((await progress(d)).leftMinor, 6000);

      await store.deleteDue(d.id);
      expect((await store.watchDues().first), isEmpty);
      final kept = await store.watchTransactions().first;
      expect(
        kept.where((t) => t.dueId == d.id),
        hasLength(1),
        reason: 'the payment really happened',
      );

      final noDate = await store.createDue(
        direction: DueDirection.iOwe,
        kind: DueKind.loan,
        person: 'Karim',
        amountMinor: 100,
        currency: 'USD',
        startDate: '2026-11-01',
        remindDaysBefore: 1,
      );
      expect(
        noDate.remindDaysBefore,
        isNull,
        reason: 'no due date, no reminder',
      );
      expect(await store.duePeople(), ['Karim']);
    },
  );

  test('a loan with money moved needs an account', () async {
    expect(
      () => store.createDue(
        direction: DueDirection.owedToMe,
        kind: DueKind.loan,
        person: 'X',
        amountMinor: 1,
        currency: 'USD',
        startDate: '2026-11-01',
        moneyMovedNow: true,
      ),
      throwsA(isA<DueException>()),
    );
  });
}
