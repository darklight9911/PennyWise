import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Scrollable;
import 'package:pennywise/app.dart';
import 'package:pennywise/features/ledger/application/ledger_providers.dart';
import 'package:pennywise/features/ledger/data/ledger_store.dart';

import '../../support/test_app.dart';
import '../../widget_test.dart' show finish, logIn, pumpApp, pw, settle, tapOn;

/// Runs [work] in simulated time, pumping frames until it completes.
Future<void> untilDone(
  WidgetTester tester,
  Future<void> Function() work,
) async {
  var done = false;
  Object? error;
  work().then(
    (_) => done = true,
    onError: (Object e) {
      error = e;
      done = true;
    },
  );
  for (var i = 0; i < 500 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  if (error != null) throw error!;
  expect(done, isTrue, reason: 'setup did not finish');
}

void main() {
  late TestHarness h;
  setUp(() {
    h = TestHarness();
    h.backend.seedUser('ann@example.com', pw); // base currency USD
  });

  testWidgets('without accounts, + leads to adding one', (tester) async {
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);
    expect(find.text('Add your first account'), findsOneWidget);
    expect(find.text('0.00'), findsWidgets);
    await tapOn(tester, find.byTooltip('Add transaction'));
    expect(find.text('New account'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('shows real totals, accounts and recent transactions', (
    tester,
  ) async {
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);
    final store = await ProviderScope.containerOf(
      tester.element(find.byType(PennyWiseApp)),
    ).read(ledgerStoreProvider.future);

    // Setup writes run in the test's simulated time, pumping frames until
    // they finish. Real-time writes (runAsync) deadlock with the live
    // queries the dashboard keeps open.
    await untilDone(tester, () async {
      final bank = await store.createAccount(
        name: 'Bank',
        type: 'bank',
        currency: 'USD',
        openingBalanceMinor: 100000,
      );
      await store.createAccount(
        name: 'Euro cash',
        type: 'cash',
        currency: 'EUR',
        openingBalanceMinor: 5000,
      );
      final food = await store.createCategory(name: 'Food', kind: 'expense');
      final salary = await store.createCategory(name: 'Salary', kind: 'income');
      final now = DateTime.now();
      await store.createTransaction(
        kind: TxKind.income,
        accountId: bank.id,
        amountMinor: 300000,
        currency: 'USD',
        occurredAt: now,
        categoryId: salary.id,
      );
      await store.createTransaction(
        kind: TxKind.expense,
        accountId: bank.id,
        amountMinor: 4550,
        currency: 'USD',
        occurredAt: now,
        categoryId: food.id,
        note: 'groceries',
      );
    });
    await settle(tester);

    expect(
      find.text('3954.50'),
      findsWidgets,
      reason: 'total: 1000 + 3000 − 45.50 (USD only)',
    );
    expect(
      find.textContaining('1 account in other currencies not included yet'),
      findsOneWidget,
    );
    expect(find.text('+3000.00'), findsWidgets, reason: 'income this month');
    expect(find.text('−45.50'), findsWidgets, reason: 'spent this month');
    expect(find.text('Euro cash'), findsOneWidget);
    expect(find.text('50.00'), findsOneWidget);
    // The recent list is below the fold; a lazy list only builds what is shown.
    await tester.scrollUntilVisible(
      find.text('Bank · groceries'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('Bank · groceries'),
      findsOneWidget,
      reason: 'recent transactions',
    );

    await tapOn(tester, find.text('See all'));
    expect(
      find.text('Today'),
      findsOneWidget,
      reason: 'on the Transactions tab',
    );
    await finish(tester);
  });
}
