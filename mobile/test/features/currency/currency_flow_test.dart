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
    h.backend.seedUser('ann@example.com', pw);
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

  testWidgets('main currency sheet searches by name, country and symbol', (
    tester,
  ) async {
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);

    await tapOn(tester, find.text('Settings'));
    expect(find.text('USD · US Dollar'), findsOneWidget);
    await tapOn(tester, find.text('Main currency'));

    final searchBox = find.byType(TextField);
    expect(searchBox, findsOneWidget);

    await tester.enterText(searchBox, 'taka');
    await settle(tester);
    expect(find.text('BDT'), findsOneWidget);
    expect(find.text('Bangladeshi Taka'), findsOneWidget);
    expect(find.text('EUR'), findsNothing);

    await tapOn(tester, find.byTooltip('Clear search'));
    expect(find.text('EUR'), findsOneWidget);

    await tester.enterText(searchBox, 'bangladesh');
    await settle(tester);
    expect(find.text('BDT'), findsOneWidget);

    await tapOn(tester, find.byTooltip('Clear search'));
    await tester.enterText(searchBox, '৳');
    await settle(tester);
    expect(find.text('BDT'), findsOneWidget);

    await tapOn(tester, find.text('BDT'));
    expect(
      find.text(
        'No automatic daily rate for BDT. You can type rates by hand on foreign transactions.',
      ),
      findsOneWidget,
    );

    await tapOn(tester, find.widgetWithText(FilledButton, 'Change'));
    expect(find.text('BDT · converting totals…'), findsOneWidget);
    await finish(tester);
  });

  testWidgets(
    'main currency sheet pins account currencies and previews total',
    (tester) async {
      h.backend.fxRates.addAll({'USD': '1.25', 'GBP': '0.80'});
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
          name: 'Travel',
          type: 'cash',
          currency: 'GBP',
          openingBalanceMinor: 0,
        );
      });

      await tapOn(tester, find.text('Settings'));
      await tapOn(tester, find.text('Main currency'));

      expect(find.text('Suggested'), findsOneWidget);
      expect(find.text('Current · US Dollar'), findsOneWidget);
      expect(find.text('In your accounts · British Pound'), findsOneWidget);

      await tapOn(tester, find.text('EUR'));
      expect(find.text('Est. total: 100.00 USD → ≈ 80.00 EUR'), findsOneWidget);
      expect(
        find.text(
          "Daily rates update automatically for EUR. Past transactions convert using each day's rate.",
        ),
        findsOneWidget,
      );

      await tapOn(tester, find.widgetWithText(TextButton, 'Cancel'));
      await finish(tester);
    },
  );

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('main currency sheet passes accessibility (${mode.name})', (
      tester,
    ) async {
      h.prefs.values['theme_mode'] = mode.name;
      final handle = tester.ensureSemantics();
      await pumpApp(tester, h);
      await logIn(tester, 'ann@example.com', pw);

      await tapOn(tester, find.text('Settings'));
      await tapOn(tester, find.text('Main currency'));

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      handle.dispose();
      await finish(tester);
    });
  }

  testWidgets('main currency sheet works at double text size', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);
    await tapOn(tester, find.text('Settings'));
    await tester.scrollUntilVisible(
      find.text('Main currency'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tapOn(tester, find.text('Main currency'));

    await tester.enterText(find.byType(TextField), 'euro');
    await settle(tester);
    await tapOn(tester, find.text('EUR'));
    await tapOn(tester, find.widgetWithText(TextButton, 'Cancel'));
    await finish(tester);
  });

  testWidgets('main currency sheet stays usable with keyboard open', (
    tester,
  ) async {
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);
    await tapOn(tester, find.text('Settings'));
    await tapOn(tester, find.text('Main currency'));

    tester.view.viewInsets = const FakeViewPadding(bottom: 880);
    await tester.enterText(find.byType(TextField), 'taka');
    await settle(tester);
    expect(find.text('BDT'), findsOneWidget);
    await tapOn(tester, find.text('BDT'));
    await tapOn(tester, find.widgetWithText(TextButton, 'Cancel'));
    await finish(tester);
  });
}
