import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pennywise/app.dart';
import 'package:pennywise/core/database/app_database.dart';
import 'package:pennywise/features/ledger/application/ledger_providers.dart';
import 'package:pennywise/features/reports/presentation/charts.dart';
import 'package:pennywise/features/reports/presentation/reports_screen.dart';

import '../../support/test_app.dart';
import '../../widget_test.dart' show finish, logIn, pumpApp, pw, tapOn;
import '../dashboard/dashboard_flow_test.dart' show untilDone;

void main() {
  late TestHarness h;
  setUp(() {
    h = TestHarness();
    h.backend.seedUser('ann@example.com', pw); // main currency USD
  });

  test('periods end this month', () {
    final now = DateTime(2026, 2, 14);
    expect(periodRange(ReportPeriod.month, now).from, '2026-02-01');
    expect(periodRange(ReportPeriod.month, now).to, '2026-02-28');
    expect(periodRange(ReportPeriod.quarter, now).from, '2025-12-01');
    expect(periodRange(ReportPeriod.year, now).to, '2026-12-31');
  });

  testWidgets('empty, then spending by category and money in and out', (
    tester,
  ) async {
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);
    await tapOn(tester, find.text('Reports'));
    expect(find.text('Nothing to show yet'), findsOneWidget);

    final store = await ProviderScope.containerOf(
      tester.element(find.byType(PennyWiseApp)),
    ).read(ledgerStoreProvider.future);
    await untilDone(tester, () async {
      final bank = await store.createAccount(
        name: 'Bank',
        type: 'bank',
        currency: 'USD',
      );
      final food = await store.createCategory(name: 'Food', kind: 'expense');
      final cafe = await store.createCategory(
        name: 'Cafe',
        kind: 'expense',
        parentId: food.id,
      );
      final rent = await store.createCategory(name: 'Rent', kind: 'expense');
      final pay = await store.createCategory(name: 'Pay', kind: 'income');
      Future<void> add(Category c, int amount) => store.createTransaction(
        kind: c.kind,
        accountId: bank.id,
        amountMinor: amount,
        currency: 'USD',
        occurredAt: DateTime.now(),
        categoryId: c.id,
        baseCurrency: 'USD',
      );
      await add(rent, 100000);
      await add(food, 2000);
      await add(cafe, 500);
      await add(pay, 300000);
    });
    await tester.pumpAndSettle();

    expect(find.text('Spending by category'), findsOneWidget);
    expect(find.text('1025.00'), findsOneWidget, reason: 'total in the ring');
    for (final row in [('Rent', '1000.00', '98%'), ('Food', '25.00', '2%')]) {
      final line = find
          .ancestor(of: find.text(row.$1), matching: find.byType(Row))
          .first;
      expect(
        find.descendant(of: line, matching: find.text(row.$2)),
        findsOneWidget,
        reason: row.$1,
      );
      expect(
        find.descendant(of: line, matching: find.text(row.$3)),
        findsOneWidget,
        reason: row.$1,
      );
    }
    final donut = tester.widget<DonutChart>(find.byType(DonutChart));
    expect(donut.values, [100000, 2500]);
    expect(donut.semanticsLabel, contains('Rent 98%, Food 2%'));

    await tester.scrollUntilVisible(
      find.text('Money in and out'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    final bars = tester.widget<PairedBarChart>(find.byType(PairedBarChart));
    expect(bars.labels.length, 6);
    expect(
      (bars.first.last, bars.second.last),
      (300000, 102500),
      reason: 'this month',
    );

    await tester.scrollUntilVisible(
      find.text('Year'),
      -200,
      scrollable: find.byType(Scrollable).last,
    );
    await tapOn(tester, find.text('Year'));
    expect(find.text('Spending by category'), findsOneWidget);
    await finish(tester);
  });
}
