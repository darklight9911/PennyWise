import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/core/database/app_database.dart';
import 'package:pennywise/features/ledger/data/ledger_store.dart';
import 'package:pennywise/features/transactions/domain/transaction_search.dart';

MoneyTransaction _tx(
  String id,
  String localDate, {
  String kind = TxKind.expense,
  int amountMinor = 1000,
  String currency = 'USD',
  int? amountBaseMinor,
  String accountId = 'a1',
  String? transferAccountId,
  String? categoryId = 'c1',
  String note = '',
}) => MoneyTransaction(
  id: id,
  updatedAt: DateTime.utc(2026, 11, 20),
  accountId: accountId,
  categoryId: categoryId,
  kind: kind,
  amountMinor: amountMinor,
  currency: currency,
  amountBaseMinor: amountBaseMinor,
  transferAccountId: transferAccountId,
  occurredAt: DateTime.parse('${localDate}T12:00:00Z'),
  localDate: localDate,
  note: note,
);

void main() {
  final now = DateTime(2026, 11, 20, 14); // Friday 20 Nov 2026

  group('TransactionDateFilter', () {
    test('builds expected preset bounds and labels', () {
      expect(
        TransactionDateFilter.forPreset(DateFilterPreset.today, now),
        const TransactionDateFilter(
          preset: DateFilterPreset.today,
          fromDate: '2026-11-20',
          toDate: '2026-11-20',
        ),
      );
      expect(
        TransactionDateFilter.forPreset(DateFilterPreset.yesterday, now),
        const TransactionDateFilter(
          preset: DateFilterPreset.yesterday,
          fromDate: '2026-11-19',
          toDate: '2026-11-19',
        ),
      );
      expect(
        TransactionDateFilter.forPreset(DateFilterPreset.thisWeek, now),
        const TransactionDateFilter(
          preset: DateFilterPreset.thisWeek,
          fromDate: '2026-11-16', // Monday
          toDate: '2026-11-22', // Sunday
        ),
      );
      expect(
        TransactionDateFilter.forPreset(DateFilterPreset.thisMonth, now),
        const TransactionDateFilter(
          preset: DateFilterPreset.thisMonth,
          fromDate: '2026-11-01',
          toDate: '2026-11-30',
        ),
      );

      final custom = TransactionDateFilter.singleDate('2025-12-05');
      expect(custom.label(now), '5 Dec 2025');

      final range = TransactionDateFilter.range('2026-11-15', '2026-11-01');
      expect((range.fromDate, range.toDate), ('2026-11-01', '2026-11-15'));
      expect(range.label(now), '1 Nov – 15 Nov');
    });
  });

  group('sliceByDateRange', () {
    test('handles empty, single, duplicate dates and open/invalid bounds', () {
      expect(sliceByDateRange(const [], fromDate: '2026-11-01'), isEmpty);

      final single = [_tx('1', '2026-11-10')];
      expect(
        sliceByDateRange(single, fromDate: '2026-11-10', toDate: '2026-11-10'),
        single,
      );
      expect(
        sliceByDateRange(single, fromDate: '2026-11-12', toDate: '2026-11-01'),
        isEmpty,
      );

      final list = [
        _tx('1', '2026-11-20'),
        _tx('2', '2026-11-19'),
        _tx('3', '2026-11-19'),
        _tx('4', '2026-11-18'),
        _tx('5', '2026-11-01'),
      ];
      expect(
        sliceByDateRange(
          list,
          fromDate: '2026-11-19',
          toDate: '2026-11-19',
        ).map((t) => t.id),
        ['2', '3'],
      );
      expect(sliceByDateRange(list, fromDate: '2026-11-19').map((t) => t.id), [
        '1',
        '2',
        '3',
      ]);
      expect(sliceByDateRange(list, toDate: '2026-11-18').map((t) => t.id), [
        '4',
        '5',
      ]);
      expect(
        sliceByDateRange(list, fromDate: '2026-12-01', toDate: '2026-12-31'),
        isEmpty,
      );
    });

    test('matches linear filter across 500 items and 20 random ranges', () {
      final rng = Random(42);
      final base = DateTime(2026, 1, 1);
      final days = [
        for (var i = 0; i < 500; i++)
          formatYmd(base.add(Duration(days: rng.nextInt(365)))),
      ]..sort((a, b) => b.compareTo(a));
      final txns = [for (var i = 0; i < days.length; i++) _tx('t$i', days[i])];

      for (var trial = 0; trial < 20; trial++) {
        final d1 = formatYmd(base.add(Duration(days: rng.nextInt(365))));
        final d2 = formatYmd(base.add(Duration(days: rng.nextInt(365))));
        final from = d1.compareTo(d2) <= 0 ? d1 : d2;
        final to = d1.compareTo(d2) <= 0 ? d2 : d1;

        final got = sliceByDateRange(txns, fromDate: from, toDate: to);
        final expected = txns
            .where(
              (t) =>
                  t.localDate.compareTo(from) >= 0 &&
                  t.localDate.compareTo(to) <= 0,
            )
            .toList();
        expect(got.map((t) => t.id), expected.map((t) => t.id));
      }
    });
  });

  group('parseDateQuery', () {
    test('parses relative, numeric and month-name date queries', () {
      expect(parseDateQuery('today', now), (
        fromDate: '2026-11-20',
        toDate: '2026-11-20',
      ));
      expect(parseDateQuery('Yesterday', now), (
        fromDate: '2026-11-19',
        toDate: '2026-11-19',
      ));
      expect(parseDateQuery('this week', now), (
        fromDate: '2026-11-16',
        toDate: '2026-11-22',
      ));
      expect(parseDateQuery('last week', now), (
        fromDate: '2026-11-09',
        toDate: '2026-11-15',
      ));
      expect(parseDateQuery('this month', now), (
        fromDate: '2026-11-01',
        toDate: '2026-11-30',
      ));
      expect(parseDateQuery('last month', now), (
        fromDate: '2026-10-01',
        toDate: '2026-10-31',
      ));

      expect(parseDateQuery('2026-11-20', now), (
        fromDate: '2026-11-20',
        toDate: '2026-11-20',
      ));
      expect(parseDateQuery('2026/11', now), (
        fromDate: '2026-11-01',
        toDate: '2026-11-30',
      ));
      expect(parseDateQuery('2026', now), (
        fromDate: '2026-01-01',
        toDate: '2026-12-31',
      ));
      expect(parseDateQuery('20/11/2026', now), (
        fromDate: '2026-11-20',
        toDate: '2026-11-20',
      ));
      expect(parseDateQuery('5-2-2026', now), (
        fromDate: '2026-02-05',
        toDate: '2026-02-05',
      ));
      expect(parseDateQuery('20 nov', now), (
        fromDate: '2026-11-20',
        toDate: '2026-11-20',
      ));
      expect(parseDateQuery('nov 20', now), (
        fromDate: '2026-11-20',
        toDate: '2026-11-20',
      ));
      expect(parseDateQuery('20 november 2025', now), (
        fromDate: '2025-11-20',
        toDate: '2025-11-20',
      ));
      expect(parseDateQuery('november', now), (
        fromDate: '2026-11-01',
        toDate: '2026-11-30',
      ));
      expect(parseDateQuery('feb 2024', now), (
        fromDate: '2024-02-01',
        toDate: '2024-02-29',
      ));
    });

    test('rejects invalid calendar dates and non-date text', () {
      expect(parseDateQuery('2026-02-30', now), isNull);
      expect(parseDateQuery('31 nov', now), isNull);
      expect(parseDateQuery('29 feb 2025', now), isNull);
      expect(parseDateQuery('coffee', now), isNull);
      expect(parseDateQuery('', now), isNull);
    });
  });

  group('filterTransactions', () {
    final stamp = DateTime.utc(2026, 11, 20);
    final categories = {
      'c1': Category(
        id: 'c1',
        updatedAt: stamp,
        name: 'Food',
        kind: 'expense',
        icon: 'restaurant',
        color: '',
        sortOrder: 0,
      ),
      'c2': Category(
        id: 'c2',
        updatedAt: stamp,
        name: 'Salary',
        kind: 'income',
        icon: 'payments',
        color: '',
        sortOrder: 1,
      ),
    };
    final accounts = {
      'a1': Account(
        id: 'a1',
        updatedAt: stamp,
        name: 'Bkash',
        type: 'mobile',
        currency: 'BDT',
        openingBalanceMinor: 0,
        icon: '',
        color: '',
        archived: false,
        sortOrder: 0,
      ),
      'a2': Account(
        id: 'a2',
        updatedAt: stamp,
        name: 'USD Card',
        type: 'card',
        currency: 'USD',
        openingBalanceMinor: 0,
        icon: '',
        color: '',
        archived: false,
        sortOrder: 1,
      ),
    };

    final txns = [
      _tx(
        't1',
        '2026-11-20',
        kind: TxKind.expense,
        amountMinor: 12000,
        currency: 'BDT',
        amountBaseMinor: 12000,
        accountId: 'a1',
        categoryId: 'c1',
        note: 'Morning coffee',
      ),
      _tx(
        't2',
        '2026-11-20',
        kind: TxKind.income,
        amountMinor: 500000,
        currency: 'BDT',
        amountBaseMinor: 500000,
        accountId: 'a1',
        categoryId: 'c2',
        note: 'Client payout',
      ),
      _tx(
        't3',
        '2026-11-20',
        kind: TxKind.transfer,
        amountMinor: 10000,
        currency: 'BDT',
        accountId: 'a1',
        transferAccountId: 'a2',
        categoryId: null,
        note: 'Top up',
      ),
      _tx(
        't4',
        '2026-11-19',
        kind: TxKind.expense,
        amountMinor: 1500,
        currency: 'USD',
        amountBaseMinor: null, // waits for FX rate
        accountId: 'a2',
        categoryId: 'c1',
        note: 'Cloud bill',
      ),
      _tx(
        't5',
        '2026-10-10',
        kind: TxKind.expense,
        amountMinor: 50000,
        currency: 'BDT',
        amountBaseMinor: 50000,
        accountId: 'a1',
        categoryId: 'c1',
        note: 'October lunch',
      ),
    ];

    test(
      'combines date filter with multi-token search and aggregates totals',
      () {
        final todayRes = filterTransactions(
          transactions: txns,
          now: now,
          baseCurrency: 'BDT',
          dateFilter: TransactionDateFilter.forPreset(
            DateFilterPreset.today,
            now,
          ),
          categories: categories,
          accounts: accounts,
        );
        expect(todayRes.items.map((t) => t.id), ['t1', 't2', 't3']);
        expect(todayRes.incomeMinor, 500000);
        expect(todayRes.expenseMinor, 12000);
        expect(todayRes.missingRate, 0);

        // Intersects This Month chip + "yesterday" typed date query -> only 2026-11-19.
        final intersect = filterTransactions(
          transactions: txns,
          now: now,
          baseCurrency: 'BDT',
          dateFilter: TransactionDateFilter.forPreset(
            DateFilterPreset.thisMonth,
            now,
          ),
          query: 'yesterday',
          categories: categories,
          accounts: accounts,
        );
        expect(intersect.matchedDateQuery, isTrue);
        expect(intersect.items.map((t) => t.id), ['t4']);
        expect(intersect.missingRate, 1);

        // Chip Today + "october" typed query -> empty intersection.
        final disjoint = filterTransactions(
          transactions: txns,
          now: now,
          baseCurrency: 'BDT',
          dateFilter: TransactionDateFilter.forPreset(
            DateFilterPreset.today,
            now,
          ),
          query: '2026-10',
          categories: categories,
          accounts: accounts,
        );
        expect(disjoint.items, isEmpty);

        // Multi-token text match across category + note.
        final textMatch = filterTransactions(
          transactions: txns,
          now: now,
          baseCurrency: 'BDT',
          query: 'food coffee',
          categories: categories,
          accounts: accounts,
        );
        expect(textMatch.items.map((t) => t.id), ['t1']);
      },
    );
  });
}
