import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pennywise/app.dart';
import 'package:pennywise/features/ledger/application/ledger_providers.dart';
import 'package:pennywise/features/ledger/data/ledger_store.dart';
import 'package:pennywise/features/recurring/domain/recurrence.dart';
import 'package:pennywise/features/recurring/presentation/recurring_screen.dart';

import '../../support/test_app.dart';
import '../../widget_test.dart' show field, finish, logIn, pumpApp, pw, tapOn;
import '../dashboard/dashboard_flow_test.dart' show untilDone;

void main() {
  late TestHarness h;
  setUp(() {
    h = TestHarness();
    h.backend.seedUser('ann@example.com', pw); // main currency USD
  });

  test('frequency labels', () {
    expect(frequencyLabel('monthly', 1), 'Every month');
    expect(frequencyLabel('weekly', 2), 'Every 2 weeks');
    expect(frequencyLabel('daily', 1), 'Every day');
    expect(frequencyLabel('yearly', 3), 'Every 3 years');
  });

  testWidgets('add a monthly bill, pause it, then delete it', (tester) async {
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);
    final store = await ProviderScope.containerOf(
      tester.element(find.byType(PennyWiseApp)),
    ).read(ledgerStoreProvider.future);
    await untilDone(tester, () async {
      await store.createAccount(name: 'Bank', type: 'bank', currency: 'USD');
      await store.createCategory(name: 'Rent', kind: 'expense');
    });

    await tapOn(tester, find.text('Settings'));
    await tester.scrollUntilVisible(
      find.text('Recurring'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tapOn(tester, find.text('Recurring'));
    expect(find.text('Nothing recurring yet'), findsOneWidget);

    await tapOn(tester, find.text('Add recurring'));
    final add = find.widgetWithText(FilledButton, 'Add recurring');
    await tester.scrollUntilVisible(
      add,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tapOn(tester, add);
    expect(find.text('Choose an account'), findsOneWidget);
    expect(find.text('Choose a category'), findsOneWidget);

    await tester.scrollUntilVisible(
      field('Amount'),
      -200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(field('Amount'), '950');
    await tapOn(
      tester,
      find.widgetWithText(DropdownButtonFormField<String>, 'Account'),
    );
    await tapOn(tester, find.text('Bank').last);
    await tapOn(
      tester,
      find.widgetWithText(DropdownButtonFormField<String>, 'Category'),
    );
    await tapOn(tester, find.text('Rent').last);
    await tester.scrollUntilVisible(
      add,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tapOn(tester, add);

    // Starts today, so the first bill is due now.
    expect(find.text('Rent'), findsOneWidget);
    expect(find.textContaining('Every month · Next Today'), findsOneWidget);

    final rule = (await tester.runAsync(
      () => store.watchRecurringRules().first,
    ))!.single;
    expect(rule.amountMinor, 95000);
    expect(rule.currency, 'USD');
    expect(rule.startDate, ymd(DateTime.now()));
    expect(
      h.backend.serverRows[(Entity.recurringRule, rule.id)]?.data['frequency'],
      'monthly',
    );

    // Pause it.
    await tapOn(tester, find.text('Rent'));
    final active = find.widgetWithText(SwitchListTile, 'Active');
    await tester.scrollUntilVisible(
      active,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tapOn(tester, active);
    await tester.scrollUntilVisible(
      find.text('Save changes'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tapOn(tester, find.text('Save changes'));
    expect(find.textContaining('Paused'), findsOneWidget);

    await tapOn(tester, find.text('Rent'));
    await tapOn(tester, find.byTooltip('Delete recurring'));
    await tapOn(tester, find.widgetWithText(FilledButton, 'Delete'));
    expect(find.text('Nothing recurring yet'), findsOneWidget);
    await finish(tester);
  });
}
