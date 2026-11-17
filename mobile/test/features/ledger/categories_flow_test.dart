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
    h.backend.seedUser('ann@example.com', pw);
  });

  testWidgets('add, rename and delete a category; tabs split by kind', (
    tester,
  ) async {
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);
    await tapOn(tester, find.text('Settings'));
    await tapOn(tester, find.text('Categories'));
    expect(find.text('No categories yet.'), findsOneWidget);

    await tapOn(tester, find.text('Add expense category'));
    await tapOn(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.text('Give the category a name'), findsOneWidget);

    await tester.enterText(field('Category name'), 'Coffee');
    await tapOn(tester, find.bySemanticsLabel('Icon local_cafe'));
    await tapOn(tester, find.bySemanticsLabel('Colour #9C6644'));
    await tapOn(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.text('Coffee'), findsOneWidget);

    final store = await ProviderScope.containerOf(
      tester.element(find.byType(PennyWiseApp)),
    ).read(ledgerStoreProvider.future);
    final saved = (await tester.runAsync(() => store.watchCategories().first))!
        .single;
    expect(
      (saved.kind, saved.icon, saved.color),
      ('expense', 'local_cafe', '#9C6644'),
    );

    await tapOn(tester, find.text('Income'));
    expect(find.text('Coffee'), findsNothing);
    await tapOn(tester, find.text('Expenses'));

    await tapOn(tester, find.text('Coffee'));
    await tester.enterText(field('Category name'), 'Coffee & tea');
    await tapOn(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.text('Coffee & tea'), findsOneWidget);

    await tapOn(tester, find.text('Coffee & tea'));
    await tapOn(tester, find.widgetWithText(TextButton, 'Delete'));
    await tapOn(tester, find.widgetWithText(FilledButton, 'Delete'));
    expect(find.text('No categories yet.'), findsOneWidget);
    expect(
      h.backend.serverRows[(Entity.category, saved.id)]?.deletedAt,
      isNotNull,
      reason: 'the deletion synced',
    );
    await finish(tester);
  });
}
