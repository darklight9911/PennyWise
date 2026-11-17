import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pennywise/app.dart';
import 'package:pennywise/core/database/app_database.dart';
import 'package:pennywise/features/ledger/application/ledger_providers.dart';
import 'package:pennywise/features/ledger/data/ledger_store.dart';
import 'package:pennywise/features/ledger/presentation/day_labels.dart';

import '../../support/test_app.dart';
import '../../widget_test.dart'
    show field, finish, logIn, pumpApp, pw, settle, tapOn;

void main() {
  late TestHarness h;
  setUp(() {
    h = TestHarness();
    h.backend.seedUser('ann@example.com', pw);
  });

  Future<LedgerStore> storeOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(PennyWiseApp)))
          .read(ledgerStoreProvider.future);

  /// Direct database calls run in real time (see accounts_flow_test.dart).
  Future<T> db<T>(WidgetTester tester, Future<T> Function() fn) async =>
      (await tester.runAsync(fn)) as T;

  /// Logs in, creates accounts/categories, opens the Transactions tab.
  Future<LedgerStore> setUpLedger(
    WidgetTester tester, {
    List<(String, String)> accounts = const [('Bank', 'USD')],
  }) async {
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);
    final store = await storeOf(tester);
    for (final (name, cur) in accounts) {
      await db(
        tester,
        () => store.createAccount(
          name: name,
          type: 'bank',
          currency: cur,
          openingBalanceMinor: 10000,
        ),
      );
    }
    await db(
      tester,
      () => store.createCategory(
        name: 'Food',
        kind: 'expense',
        icon: 'restaurant',
      ),
    );
    await db(
      tester,
      () => store.createCategory(
        name: 'Salary',
        kind: 'income',
        icon: 'payments',
      ),
    );
    await settle(tester);
    await tapOn(tester, find.text('Transactions'));
    return store;
  }

  Future<void> pickFromDropdown(
    WidgetTester tester,
    String label,
    String item,
  ) async {
    await tapOn(
      tester,
      find.widgetWithText(DropdownButtonFormField<String>, label),
    );
    await tapOn(tester, find.text(item).last);
  }

  testWidgets('add an expense: it shows in the list and lowers the balance', (
    tester,
  ) async {
    final store = await setUpLedger(tester);
    expect(find.text('No transactions yet'), findsOneWidget);

    await tapOn(tester, find.byTooltip('Add transaction'));
    expect(find.text('New expense'), findsOneWidget);

    await tapOn(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.text('Enter an amount'), findsOneWidget);

    await tester.enterText(field('Amount'), '12.5');
    await tapOn(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.text('Pick a category'), findsOneWidget);

    await tapOn(tester, find.widgetWithText(ChoiceChip, 'Food'));
    await tester.enterText(field('Note (optional)'), 'lunch');
    await tapOn(tester, find.widgetWithText(FilledButton, 'Save'));

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Bank · lunch'), findsOneWidget);
    expect(find.text('−12.50'), findsOneWidget);

    final balances = await db(tester, () => store.watchBalances().first);
    expect(balances.values.single, 10000 - 1250);
    await finish(tester);
  });

  testWidgets(
    'income shows with a plus sign; switching kind shows its categories',
    (tester) async {
      await setUpLedger(tester);
      await tapOn(tester, find.byTooltip('Add transaction'));
      await tapOn(tester, find.text('Income'));
      expect(find.widgetWithText(ChoiceChip, 'Food'), findsNothing);
      await tester.enterText(field('Amount'), '2500');
      await tapOn(tester, find.widgetWithText(ChoiceChip, 'Salary'));
      await tapOn(tester, find.widgetWithText(FilledButton, 'Save'));
      expect(find.text('+2,500.00'.replaceAll(',', '')), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets('same-currency transfer moves money without a sign', (
    tester,
  ) async {
    final store = await setUpLedger(
      tester,
      accounts: [('Bank', 'USD'), ('Cash', 'USD')],
    );
    await tapOn(tester, find.byTooltip('Add transaction'));
    await tapOn(tester, find.text('Transfer'));
    await tester.enterText(field('Amount'), '20');
    await tapOn(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.text('Pick where the money goes'), findsOneWidget);

    await pickFromDropdown(tester, 'To account', 'Cash (USD)');
    expect(find.text('Amount received'), findsNothing, reason: 'same currency');
    await tapOn(tester, find.widgetWithText(FilledButton, 'Save'));

    expect(find.text('Transfer'), findsWidgets);
    expect(find.text('Bank → Cash'), findsOneWidget);
    expect(find.text('20.00'), findsOneWidget);
    final accounts = await db(tester, () => store.watchAccounts().first);
    final balances = await db(tester, () => store.watchBalances().first);
    final byName = {for (final a in accounts) a.name: balances[a.id]};
    expect(byName, {'Bank': 10000 - 2000, 'Cash': 10000 + 2000});
    await finish(tester);
  });

  testWidgets('cross-currency transfer asks for the amount received', (
    tester,
  ) async {
    final store = await setUpLedger(
      tester,
      accounts: [('Bank', 'USD'), ('Euro', 'EUR')],
    );
    await tapOn(tester, find.byTooltip('Add transaction'));
    await tapOn(tester, find.text('Transfer'));
    await tester.enterText(field('Amount'), '100');
    await pickFromDropdown(tester, 'To account', 'Euro (EUR)');
    expect(find.text('Amount received'), findsOneWidget);
    await tapOn(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.text('Enter an amount'), findsOneWidget);

    await tester.enterText(field('Amount received'), '92,30');
    await tapOn(tester, find.widgetWithText(FilledButton, 'Save'));
    final t = (await db(tester, () => store.watchTransactions().first)).single;
    expect(t.transferAmountMinor, 9230);
    expect(t.currency, 'USD');
    await finish(tester);
  });

  testWidgets('edit and delete a transaction', (tester) async {
    final store = await setUpLedger(tester);
    // Add it through the form (all in test time, like a user would).
    await tapOn(tester, find.byTooltip('Add transaction'));
    await tester.enterText(field('Amount'), '5');
    await tapOn(tester, find.widgetWithText(ChoiceChip, 'Food'));
    await tapOn(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.text('\u22125.00'), findsOneWidget);

    await tapOn(tester, find.text('Food'));
    expect(find.text('Edit transaction'), findsOneWidget);
    await tester.enterText(field('Amount'), '7.25');
    await tapOn(tester, find.widgetWithText(FilledButton, 'Save changes'));
    expect(find.text('\u22127.25'), findsOneWidget);

    await tapOn(tester, find.text('Food'));
    await tapOn(tester, find.byTooltip('Delete transaction'));
    await tapOn(tester, find.widgetWithText(FilledButton, 'Delete'));
    expect(find.text('No transactions yet'), findsOneWidget);
    final List<MoneyTransaction> left = await db(
      tester,
      () => store.watchTransactions().first,
    );
    expect(left, isEmpty);
    await finish(tester);
  });

  testWidgets('without accounts the form asks for one first', (tester) async {
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);
    await tapOn(tester, find.text('Transactions'));
    await tapOn(tester, find.byTooltip('Add transaction'));
    expect(find.text('First, add an account'), findsOneWidget);
    await tapOn(tester, find.text('Add an account'));
    expect(find.text('New account'), findsOneWidget);
    await finish(tester);
  });

  group('day labels', () {
    final now = DateTime(2026, 11, 16, 9);
    test('today, yesterday, this year, other year', () {
      expect(dayLabel('2026-11-16', now), 'Today');
      expect(dayLabel('2026-11-15', now), 'Yesterday');
      expect(dayLabel('2026-11-10', now), 'Tue 10 Nov');
      expect(dayLabel('2025-12-31', now), 'Wed 31 Dec 2025');
      expect(monthLabel('2026-03'), 'March 2026');
    });
  });
}
