import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pennywise/app.dart';
import 'package:pennywise/features/ledger/application/ledger_providers.dart';
import 'package:pennywise/features/ledger/data/ledger_store.dart';

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

  /// Direct database calls run in real time: in a widget test, time only
  /// moves while the test pumps, so a stream read here would never finish.
  Future<T> db<T>(WidgetTester tester, Future<T> Function() fn) async =>
      (await tester.runAsync(fn)) as T;

  Future<void> openAccounts(WidgetTester tester) async {
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);
    await tapOn(tester, find.text('Settings'));
    await tapOn(tester, find.text('Accounts'));
  }

  testWidgets('add an account, see its balance, edit it', (tester) async {
    await openAccounts(tester);
    expect(find.text('No accounts yet'), findsOneWidget);

    await tapOn(tester, find.text('Add account'));
    await tapOn(tester, find.widgetWithText(FilledButton, 'Add account'));
    expect(find.text('Give the account a name'), findsOneWidget);

    await tester.enterText(field('Name'), 'Wallet');
    await tester.enterText(field('Starting balance'), '12.345');
    await tapOn(tester, find.widgetWithText(FilledButton, 'Add account'));
    expect(find.text('USD has 2 decimals at most'), findsOneWidget);

    await tester.enterText(field('Starting balance'), '100.5');
    await tapOn(tester, find.widgetWithText(FilledButton, 'Add account'));
    expect(find.text('Wallet'), findsOneWidget);
    expect(find.text('100.50'), findsOneWidget);
    expect(find.text('Bank account · USD'), findsOneWidget);

    await tapOn(tester, find.text('Wallet'));
    await tester.enterText(field('Name'), 'Cash wallet');
    await tapOn(tester, find.widgetWithText(FilledButton, 'Save changes'));
    expect(find.text('Cash wallet'), findsOneWidget);

    // The change was queued and pushed to the (fake) server.
    final store = await storeOf(tester);
    final acct = (await db(tester, () => store.watchAccounts().first)).single;
    expect(
      h.backend.serverRows[(Entity.account, acct.id)]?.data['name'],
      'Cash wallet',
    );
    await finish(tester);
  });

  testWidgets(
    'currency is locked once the account has transactions; delete warns',
    (tester) async {
      await openAccounts(tester);
      final store = await storeOf(tester);
      final bank = await db(
        tester,
        () => store.createAccount(
          name: 'Bank',
          type: 'bank',
          currency: 'USD',
          openingBalanceMinor: 5000,
        ),
      );
      final food = await db(
        tester,
        () => store.createCategory(name: 'Food', kind: 'expense'),
      );
      await db(
        tester,
        () => store.createTransaction(
          kind: TxKind.expense,
          accountId: bank.id,
          amountMinor: 1250,
          currency: 'USD',
          occurredAt: DateTime(2026, 11, 15),
          categoryId: food.id,
        ),
      );
      await settle(tester);
      expect(find.text('37.50'), findsOneWidget, reason: '50.00 − 12.50, live');

      await tapOn(tester, find.text('Bank'));
      expect(
        find.text('Locked: this account already has transactions.'),
        findsOneWidget,
      );

      await tapOn(tester, find.byTooltip('Delete account'));
      expect(
        find.text('Its 1 transaction is deleted too. This cannot be undone.'),
        findsOneWidget,
      );
      await tapOn(tester, find.widgetWithText(FilledButton, 'Delete'));
      expect(find.text('No accounts yet'), findsOneWidget);
      expect(await db(tester, () => store.watchTransactions().first), isEmpty);
      await finish(tester);
    },
  );
}
