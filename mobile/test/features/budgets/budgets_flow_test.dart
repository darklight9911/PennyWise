import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pennywise/app.dart';
import 'package:pennywise/features/budgets/presentation/budget_tile.dart';
import 'package:pennywise/features/ledger/application/ledger_providers.dart';
import 'package:pennywise/features/ledger/data/ledger_store.dart';

import '../../support/test_app.dart';
import '../../widget_test.dart' show field, finish, logIn, pumpApp, pw, tapOn;
import '../dashboard/dashboard_flow_test.dart' show untilDone;

void main() {
  late TestHarness h;
  setUp(() {
    h = TestHarness();
    h.backend.seedUser('ann@example.com', pw); // main currency USD
  });

  testWidgets('add a budget, see its progress, edit and delete it', (
    tester,
  ) async {
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);
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
      await store.createTransaction(
        kind: TxKind.expense,
        accountId: bank.id,
        amountMinor: 25000,
        currency: 'USD',
        occurredAt: DateTime.now(),
        categoryId: food.id,
      );
    });

    await tapOn(tester, find.text('Settings'));
    await tapOn(tester, find.text('Budgets'));
    expect(find.text('No budgets yet'), findsOneWidget);

    await tapOn(tester, find.text('Add budget'));
    await tapOn(tester, find.widgetWithText(FilledButton, 'Add budget'));
    expect(find.text('Enter an amount'), findsOneWidget);

    await tapOn(
      tester,
      find.widgetWithText(DropdownButtonFormField<String>, 'Spending on'),
    );
    await tapOn(tester, find.text('Food').last);
    await tester.enterText(field('Limit'), '300');
    await tapOn(tester, find.widgetWithText(FilledButton, 'Add budget'));

    expect(find.text('Food'), findsOneWidget);
    expect(find.text('83%'), findsOneWidget);
    expect(find.text('50.00 left of 300.00 this month'), findsOneWidget);
    final pct = tester.widget<Text>(find.text('83%'));
    expect(pct.style?.color, budgetWarning, reason: '80 % or more shows amber');

    await tapOn(tester, find.text('Food'));
    await tester.enterText(field('Limit'), '200');
    await tapOn(tester, find.text('Message me at 80 %'));
    await tapOn(tester, find.widgetWithText(FilledButton, 'Save changes'));
    expect(find.text('50.00 over this month'), findsOneWidget);
    expect(find.text('125%'), findsOneWidget);

    final budget = (await tester.runAsync(() => store.watchBudgets().first))!
        .single;
    expect(budget.alertThresholds, '100');
    expect(
      h.backend.serverRows[(Entity.budget, budget.id)]?.data['amount_minor'],
      20000,
    );

    await tapOn(tester, find.text('Food'));
    await tapOn(tester, find.byTooltip('Delete budget'));
    await tapOn(tester, find.widgetWithText(FilledButton, 'Delete'));
    expect(find.text('No budgets yet'), findsOneWidget);
    await finish(tester);
  });
}
