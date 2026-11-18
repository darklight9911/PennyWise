import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pennywise/app.dart';
import 'package:pennywise/features/ledger/application/ledger_providers.dart';
import 'package:pennywise/features/ledger/data/ledger_store.dart';

import '../../support/test_app.dart';
import '../../widget_test.dart' show field, finish, logIn, pumpApp, pw, tapOn;

void main() {
  late TestHarness h;
  setUp(() {
    h = TestHarness();
    h.backend.seedUser('ann@example.com', pw); // main currency USD
  });

  testWidgets('add a goal, put money in, take some out, edit and delete it', (
    tester,
  ) async {
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);
    final store = await ProviderScope.containerOf(
      tester.element(find.byType(PennyWiseApp)),
    ).read(ledgerStoreProvider.future);

    await tapOn(tester, find.text('Settings'));
    await tester.scrollUntilVisible(
      find.text('Goals'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tapOn(tester, find.text('Goals'));
    expect(find.text('No goals yet'), findsOneWidget);

    await tapOn(tester, find.text('Add goal'));
    await tapOn(tester, find.widgetWithText(FilledButton, 'Add goal'));
    expect(find.text('Give the goal a name'), findsOneWidget);

    await tester.enterText(field('What are you saving for?'), 'Laptop');
    await tester.enterText(field('Target'), '1000');
    await tapOn(tester, find.widgetWithText(FilledButton, 'Add goal'));

    // The new goal's page opens.
    expect(find.text('0.00 saved of 1000.00'), findsOneWidget);
    expect(find.text('Nothing yet.'), findsOneWidget);

    await tapOn(tester, find.widgetWithText(FilledButton, 'Add money'));
    await tapOn(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.text('Enter an amount'), findsOneWidget);
    await tester.enterText(field('Amount'), '400');
    await tester.enterText(field('Note (optional)'), 'Bonus');
    await tapOn(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.text('400.00 saved of 1000.00'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('Bonus'), findsOneWidget);

    await tapOn(tester, find.widgetWithText(OutlinedButton, 'Take out'));
    await tester.enterText(field('Amount'), '150');
    await tapOn(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.text('250.00 saved of 1000.00'), findsOneWidget);

    final goal = (await tester.runAsync(() => store.watchGoalProgress().first))!
        .single
        .goal;
    final saved = (await tester.runAsync(
      () => store.watchContributions(goal.id).first,
    ))!;
    expect(saved.map((c) => c.amountMinor), unorderedEquals([40000, -15000]));
    expect(
      h.backend.serverRows[(Entity.goal, goal.id)]?.data['target_minor'],
      100000,
    );

    // Lower the target so the goal is reached.
    await tapOn(tester, find.byTooltip('Edit goal'));
    await tester.enterText(field('Target'), '200');
    await tapOn(tester, find.widgetWithText(FilledButton, 'Save changes'));
    expect(find.text('Reached'), findsOneWidget);

    await tapOn(tester, find.byTooltip('Edit goal'));
    await tapOn(tester, find.byTooltip('Delete goal'));
    await tapOn(tester, find.widgetWithText(FilledButton, 'Delete'));
    expect(find.text('No goals yet'), findsOneWidget);
    await finish(tester);
  });
}
