import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/core/database/app_database.dart';
import 'package:pennywise/features/ledger/data/ledger_store.dart';
import 'package:pennywise/features/recurring/domain/recurrence.dart';

void main() {
  late AppDatabase db;
  late LedgerStore store;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = LedgerStore(db);
  });
  tearDown(() => db.close());

  test(
    'goal progress sums contributions; deleting a goal removes them',
    () async {
      final g = await store.createGoal(
        name: ' Laptop ',
        targetMinor: 150000,
        deadline: '2027-06-30',
      );
      expect(g.name, 'Laptop');
      await store.addContribution(
        goalId: g.id,
        amountMinor: 50000,
        date: DateTime(2026, 11, 1),
      );
      final out = await store.addContribution(
        goalId: g.id,
        amountMinor: -5000,
        date: DateTime(2026, 11, 2),
        note: 'oops',
      );
      var p = (await store.watchGoalProgress().first).single;
      expect(p.savedMinor, 45000);
      expect(p.leftMinor, 105000);
      expect(p.fraction, closeTo(0.3, 1e-9));

      await store.deleteContribution(out.id);
      p = (await store.watchGoalProgress().first).single;
      expect(p.savedMinor, 50000);

      await store.deleteGoal(g.id);
      expect(await store.watchGoalProgress().first, isEmpty);
      final queued = {
        for (final o in await db.select(db.outbox).get()) o.entity,
      };
      expect(queued, containsAll([Entity.goal, Entity.goalContribution]));
    },
  );

  group('bill generator', () {
    late Account bank;
    late Category rent;
    setUp(() async {
      bank = await store.createAccount(
        name: 'Bank',
        type: 'bank',
        currency: 'USD',
      );
      rent = await store.createCategory(name: 'Rent', kind: 'expense');
    });

    Future<RecurringRule> rule({String start = '2026-09-30', String? end}) =>
        store.createRecurringRule(
          kind: 'expense',
          accountId: bank.id,
          categoryId: rent.id,
          amountMinor: 120000,
          currency: 'USD',
          frequency: 'monthly',
          startDate: start,
          endDate: end,
          note: 'Rent',
        );

    Future<List<MoneyTransaction>> bills(String ruleId) => (db.select(
      db.transactions,
    )..where((t) => t.recurringId.equals(ruleId))).get();

    test('creates due bills with the server ids, once', () async {
      final r = await rule();
      expect(await store.generateDueBills(DateTime(2026, 11, 18)), 2);
      final made = {for (final t in await bills(r.id)) t.occurrenceDate: t};
      expect(made.keys, unorderedEquals(['2026-09-30', '2026-10-30']));
      final oct = made['2026-10-30']!;
      expect(oct.id, occurrenceId(r.id, DateTime(2026, 10, 30)));
      expect(oct.localDate, '2026-10-30');
      expect(oct.note, 'Rent');
      expect(
        await store.generateDueBills(DateTime(2026, 11, 18)),
        0,
        reason: 'idempotent',
      );
      final outbox = await db.select(db.outbox).get();
      expect(
        outbox.where((o) => o.rowId == oct.id),
        hasLength(1),
        reason: 'queued for sync',
      );
    });

    test('a deleted bill is never created again', () async {
      final r = await rule();
      await store.generateDueBills(DateTime(2026, 11, 18));
      final sep = occurrenceId(r.id, DateTime(2026, 9, 30));
      await store.deleteTransaction(sep);
      expect(await store.generateDueBills(DateTime(2026, 11, 18)), 0);
      final live = (await bills(r.id))
          .where((t) => t.deletedAt == null)
          .map((t) => t.occurrenceDate);
      expect(live, ['2026-10-30']);
    });

    test('paused, ended and deleted-account rules', () async {
      final ended = await rule(end: '2026-10-15');
      final paused = await rule();
      await store.updateRecurringRule(paused.copyWith(active: false));
      expect(
        await store.generateDueBills(DateTime(2026, 11, 18)),
        1,
        reason: 'only September of the ended rule',
      );
      expect((await bills(ended.id)).single.occurrenceDate, '2026-09-30');

      await store.deleteAccount(bank.id);
      final again = await rule(start: '2026-11-01');
      expect(await store.generateDueBills(DateTime(2026, 11, 18)), 0);
      expect(await bills(again.id), isEmpty);
    });

    test(
      'a bill already pulled from the server is not created again',
      () async {
        final r = await rule();
        final day = DateTime(2026, 9, 30);
        // As if the server's worker made it and sync downloaded it.
        await db
            .into(db.transactions)
            .insert(
              TransactionsCompanion.insert(
                id: occurrenceId(r.id, day),
                kind: 'expense',
                accountId: bank.id,
                categoryId: Value(rent.id),
                amountMinor: 120000,
                currency: 'USD',
                occurredAt: DateTime.utc(2026, 9, 30, 6),
                localDate: '2026-09-30',
                recurringId: Value(r.id),
                occurrenceDate: const Value('2026-09-30'),
                updatedAt: DateTime.utc(2026, 9, 30),
              ),
            );
        expect(
          await store.generateDueBills(DateTime(2026, 11, 18)),
          1,
          reason: 'only October',
        );
      },
    );
  });
}
