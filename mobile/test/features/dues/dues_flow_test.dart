import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pennywise/app.dart';
import 'package:pennywise/features/ledger/application/ledger_providers.dart';
import 'package:pennywise/features/ledger/data/ledger_store.dart';

import '../../support/test_app.dart';
import '../../widget_test.dart' show field, finish, pumpApp, settle, tapOn;
import '../dashboard/dashboard_flow_test.dart' show untilDone;

void main() {
  late TestHarness h;
  setUp(() {
    h = TestHarness();
    // A guest with USD as main currency: dues work without an account.
    h.store.guestProfile = {
      'name': '',
      'base_currency': 'USD',
      'timezone': 'UTC',
      'locale': 'en',
    };
  });

  Future<LedgerStore> start(WidgetTester tester) async {
    await pumpApp(tester, h);
    final store = await ProviderScope.containerOf(
      tester.element(find.byType(PennyWiseApp)),
    ).read(ledgerStoreProvider.future);
    await untilDone(tester, () async {
      await store.createAccount(
        name: 'Cash',
        type: 'cash',
        currency: 'USD',
        openingBalanceMinor: 100000,
      );
    });
    return store;
  }

  Future<void> openDues(WidgetTester tester) async {
    await tapOn(tester, find.text('Settings').last);
    final dues = find.text('Dues');
    await tester.scrollUntilVisible(
      dues,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tapOn(tester, dues);
  }

  Future<void> scrollTo(WidgetTester tester, Finder f) => tester
      .scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).last);

  Future<int> cashBalance(WidgetTester tester, LedgerStore store) async {
    final b = (await tester.runAsync(() => store.watchBalances().first))!;
    final cash = (await tester.runAsync(() => store.watchAccounts().first))!
        .single;
    return b[cash.id]!;
  }

  testWidgets('lend money, get part back, then the rest', (tester) async {
    final store = await start(tester);
    await openDues(tester);
    expect(find.text('Nobody owes you'), findsOneWidget);

    await tapOn(tester, find.text('Add due'));
    expect(
      find.text('Money you lent. Getting it back is not income.'),
      findsOneWidget,
    );
    await tester.enterText(field('Who owes you?'), 'Rahim');
    await tester.enterText(field('Amount'), '300');
    await tapOn(
      tester,
      find.widgetWithText(DropdownButtonFormField<String?>, 'Account'),
    );
    await tapOn(tester, find.text('Cash').last);
    final add = find.widgetWithText(FilledButton, 'Add due');
    await scrollTo(tester, add);
    await tapOn(tester, add);

    // The due's page opens.
    expect(find.text('Rahim owes you'), findsOneWidget);
    expect(find.text('300.00'), findsWidgets);
    expect(
      await cashBalance(tester, store),
      70000,
      reason: 'the lent money left Cash',
    );

    await tapOn(tester, find.text('Add part payment'));
    await tester.enterText(field('Amount'), '400');
    await tapOn(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.text('Only 300.00 USD is left'), findsOneWidget);
    await tester.enterText(field('Amount'), '100');
    await tapOn(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.text('100.00 received of 300.00 USD'), findsOneWidget);
    expect(find.text('Payment received'), findsOneWidget);
    expect(find.text('Money lent'), findsOneWidget);

    await tapOn(tester, find.text('Mark received'));
    await tapOn(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.text('Settled'), findsWidgets);
    expect(await cashBalance(tester, store), 100000);

    final totals = (await tester.runAsync(
      () => store
          .watchMonthTotals(
            DateTime.now().toIso8601String().substring(0, 7),
            'USD',
          )
          .first,
    ))!;
    expect(
      (totals.incomeMinor, totals.expenseMinor),
      (0, 0),
      reason: 'a loan is not income or spending',
    );
    await finish(tester);
  });

  testWidgets('a bill I owe needs a category; paying it is spending', (
    tester,
  ) async {
    final store = await start(tester);
    await openDues(tester);
    await tapOn(tester, find.text('I owe'));
    expect(find.text('You owe nobody'), findsOneWidget);
    await tapOn(tester, find.text('Add due'));
    await tapOn(tester, find.text('Bill'));
    await tester.enterText(field('Who do you owe?'), 'Corner shop');
    await tester.enterText(field('Amount'), '25');
    final add = find.widgetWithText(FilledButton, 'Add due');
    await scrollTo(tester, add);
    await tapOn(tester, add);
    expect(find.text('Choose a category for the bill.'), findsOneWidget);

    final category = find.widgetWithText(
      DropdownButtonFormField<String>,
      'Spending category',
    );
    await scrollTo(tester, category);
    await tapOn(tester, category);
    await tapOn(tester, find.text('Groceries').last);
    await scrollTo(tester, add);
    await tapOn(tester, add);
    expect(find.text('You owe Corner shop'), findsOneWidget);

    await tapOn(tester, find.text('Mark paid'));
    await tapOn(tester, find.widgetWithText(FilledButton, 'Save'));
    final month = DateTime.now().toIso8601String().substring(0, 7);
    final totals = (await tester.runAsync(
      () => store.watchMonthTotals(month, 'USD').first,
    ))!;
    expect(totals.expenseMinor, 2500);
    await finish(tester);
  });

  testWidgets('forgive the rest, reopen; a loan entry opens its due', (
    tester,
  ) async {
    final store = await start(tester);
    await untilDone(tester, () async {
      final cash = (await store.db.select(store.db.accounts).get()).single;
      await store.createDue(
        direction: DueDirection.owedToMe,
        kind: DueKind.loan,
        person: 'Karim',
        amountMinor: 5000,
        currency: 'USD',
        startDate: '2026-11-01',
        accountId: cash.id,
        moneyMovedNow: true,
      );
    });
    await openDues(tester);
    await tapOn(tester, find.text('Karim'));
    await tapOn(tester, find.text('Forgive the rest'));
    expect(find.text('Closed'), findsOneWidget);
    expect(find.text('Forgiven'), findsOneWidget);
    await tapOn(tester, find.text('Reopen'));
    expect(find.text('Left'), findsOneWidget);

    // Back to the list: settled ones are hidden until asked for.
    await tester.pageBack();
    await settle(tester);
    expect(find.text('Karim'), findsOneWidget);

    // In Transactions, the loan entry leads to its due.
    await tester.pageBack();
    await settle(tester);
    await tapOn(tester, find.text('Transactions').last);
    await tapOn(tester, find.text('Loan money out'));
    expect(find.text('Karim owes you'), findsOneWidget);
    await finish(tester);
  });
}
