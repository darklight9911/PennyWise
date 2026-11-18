import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pennywise/app.dart';
import 'package:pennywise/features/ledger/application/ledger_providers.dart';
import 'package:pennywise/features/ledger/data/ledger_store.dart';

import '../../support/test_app.dart';
import '../../widget_test.dart'
    show field, finish, logIn, pumpApp, pw, settle, tapOn;
import '../dashboard/dashboard_flow_test.dart' show untilDone;

void main() {
  late TestHarness h;
  setUp(() {
    h = TestHarness();
    h.backend.seedUser('ann@example.com', pw); // main currency USD
  });

  Future<LedgerStore> storeOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(PennyWiseApp)))
          .read(ledgerStoreProvider.future);

  testWidgets('a typed rate counts a euro expense in dollars', (tester) async {
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);
    final store = await storeOf(tester);
    await untilDone(tester, () async {
      await store.createAccount(
        name: 'Euro cash',
        type: 'cash',
        currency: 'EUR',
      );
      await store.createCategory(name: 'Snacks', kind: 'expense');
    });

    await tapOn(tester, find.byTooltip('Add transaction'));
    await tester.enterText(field('Amount'), '10');
    expect(field('Exchange rate (optional)'), findsOneWidget);
    await tester.enterText(field('Exchange rate (optional)'), '0');
    await tapOn(tester, find.text('Snacks'));
    await tapOn(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.text('Use a number above zero, like 1.08'), findsOneWidget);

    await tester.enterText(field('Exchange rate (optional)'), '1,1');
    await tapOn(tester, find.widgetWithText(FilledButton, 'Save'));

    final t = (await tester.runAsync(() => store.watchTransactions().first))!
        .single;
    expect(
      (t.amountBaseMinor, t.fxRateToBase, t.fxRateSource),
      (1100, '1.1', 'manual'),
    );
    expect(
      find.text('−11.00'),
      findsWidgets,
      reason: 'spent this month, in USD',
    );
    await finish(tester);
  });

  testWidgets('the total converts other accounts at today\'s rate', (
    tester,
  ) async {
    h.backend.fxRates.addAll({'USD': '1.25'}); // 1 EUR = 1.25 USD
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);
    final store = await storeOf(tester);
    await untilDone(tester, () async {
      await store.createAccount(
        name: 'Bank',
        type: 'bank',
        currency: 'USD',
        openingBalanceMinor: 10000,
      );
      await store.createAccount(
        name: 'Euro',
        type: 'cash',
        currency: 'EUR',
        openingBalanceMinor: 8000,
      );
    });
    await settle(tester);
    expect(
      find.text('200.00'),
      findsOneWidget,
      reason: '100 USD + 80 EUR x 1.25',
    );
    expect(find.text("1 account converted at today's rate."), findsOneWidget);
    await finish(tester);
  });

  testWidgets('changing the main currency shows a banner until it is done', (
    tester,
  ) async {
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);

    await tapOn(tester, find.text('Settings'));
    await tapOn(tester, find.text('Main currency'));
    await tapOn(tester, find.text('EUR'));
    await tapOn(tester, find.widgetWithText(FilledButton, 'Change'));
    expect(find.text('EUR · converting totals…'), findsOneWidget);

    // The banner's spinner never settles: pump frames by hand.
    await tester.tap(find.text('Home'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      find.text('Recalculating totals in EUR… This takes a moment.'),
      findsOneWidget,
    );
    expect(find.text('Total balance'), findsNothing);

    // The server finishes; the banner notices on its next check.
    h.backend.users['ann@example.com']!['base_currency_status'] = 'ok';
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await settle(tester);
    expect(find.textContaining('Recalculating'), findsNothing);
    expect(find.text('Total balance'), findsOneWidget);
    await finish(tester);
  });
}
