import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pennywise/app.dart';
import 'package:pennywise/features/ledger/application/ledger_providers.dart';
import 'package:pennywise/features/ledger/data/ledger_store.dart';

import '../features/dashboard/dashboard_flow_test.dart' show untilDone;
import '../support/test_app.dart';
import '../widget_test.dart' show finish, logIn, pumpApp, pw, settle, tapOn;

/// Main screens checked against Flutter's accessibility guidelines, in both
/// themes, and at double text size (an overflow there fails the test).
void main() {
  Future<TestHarness> withData(
    WidgetTester tester, {
    ThemeMode mode = ThemeMode.light,
  }) async {
    final h = TestHarness();
    h.backend.seedUser('ann@example.com', pw);
    h.prefs.values['theme_mode'] = mode.name;
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);
    final store = await ProviderScope.containerOf(
      tester.element(find.byType(PennyWiseApp)),
    ).read(ledgerStoreProvider.future);
    await untilDone(tester, () async {
      final bank = await store.createAccount(
        name: 'Everyday bank account',
        type: 'bank',
        currency: 'USD',
        openingBalanceMinor: 123456789,
      );
      final food = await store.createCategory(
        name: 'Groceries and household',
        kind: 'expense',
      );
      final pay = await store.createCategory(name: 'Salary', kind: 'income');
      await store.createTransaction(
        kind: 'income',
        accountId: bank.id,
        amountMinor: 987654321,
        currency: 'USD',
        occurredAt: DateTime.now(),
        categoryId: pay.id,
        baseCurrency: 'USD',
      );
      await store.createTransaction(
        kind: 'expense',
        accountId: bank.id,
        amountMinor: 12345678,
        currency: 'USD',
        occurredAt: DateTime.now(),
        categoryId: food.id,
        baseCurrency: 'USD',
        note: 'Weekly shop at the big market',
      );
      await store.createBudget(
        categoryId: food.id,
        amountMinor: 15000000,
        period: 'monthly',
      );
    });
    await settle(tester);
    return h;
  }

  const tabs = ['Home', 'Transactions', 'Reports', 'Settings'];

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('guidelines on the main screens (${mode.name})', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await withData(tester, mode: mode);
      for (final tab in tabs) {
        await tapOn(tester, find.text(tab).last);
        await expectLater(
          tester,
          meetsGuideline(androidTapTargetGuideline),
          reason: tab,
        );
        await expectLater(
          tester,
          meetsGuideline(labeledTapTargetGuideline),
          reason: tab,
        );
        await expectLater(
          tester,
          meetsGuideline(textContrastGuideline),
          reason: tab,
        );
      }
      await tapOn(tester, find.text('Home').last);
      await tapOn(tester, find.byTooltip('Add transaction'));
      await expectLater(
        tester,
        meetsGuideline(androidTapTargetGuideline),
        reason: 'form',
      );
      await expectLater(
        tester,
        meetsGuideline(labeledTapTargetGuideline),
        reason: 'form',
      );
      await expectLater(
        tester,
        meetsGuideline(textContrastGuideline),
        reason: 'form',
      );
      handle.dispose();
      await finish(tester);
    });
  }

  testWidgets('double text size: nothing is cut off', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await withData(tester);
    for (final tab in tabs) {
      await tapOn(tester, find.text(tab).last);
    }
    await tapOn(tester, find.text('Home').last);
    await tapOn(tester, find.byTooltip('Add transaction'));
    await finish(tester);
  });

  // Dues: list, detail and form, with long names and big amounts.
  Future<void> addDues(WidgetTester tester) async {
    final store = await ProviderScope.containerOf(
      tester.element(find.byType(PennyWiseApp)),
    ).read(ledgerStoreProvider.future);
    await untilDone(tester, () async {
      final bank = (await store.db.select(store.db.accounts).get()).first;
      await store.createDue(
        direction: DueDirection.owedToMe,
        kind: DueKind.loan,
        person: 'Mohammad Abdur Rahim Chowdhury',
        amountMinor: 987654321,
        currency: 'USD',
        startDate: '2026-11-01',
        dueDate: '2026-11-03',
        remindDaysBefore: 1,
        accountId: bank.id,
        moneyMovedNow: true,
      );
    });
    await settle(tester);
  }

  Future<void> walkDues(
    WidgetTester tester,
    Future<void> Function(String) check,
  ) async {
    await tapOn(tester, find.text('Settings').last);
    final dues = find.text('Dues');
    await tester.scrollUntilVisible(
      dues,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tapOn(tester, dues);
    await check('dues list');
    await tapOn(tester, find.text('Mohammad Abdur Rahim Chowdhury'));
    await check('due detail');
    await tapOn(tester, find.byTooltip('Edit due'));
    await check('due form');
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('guidelines on the dues screens (${mode.name})', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await withData(tester, mode: mode);
      await addDues(tester);
      await walkDues(tester, (where) async {
        await expectLater(
          tester,
          meetsGuideline(androidTapTargetGuideline),
          reason: where,
        );
        await expectLater(
          tester,
          meetsGuideline(labeledTapTargetGuideline),
          reason: where,
        );
        await expectLater(
          tester,
          meetsGuideline(textContrastGuideline),
          reason: where,
        );
      });
      handle.dispose();
      await finish(tester);
    });
  }

  testWidgets('dues at 320 px and double text size', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await withData(tester);
    tester.view.physicalSize = const Size(320 * 2.75, 2340);
    await settle(tester);
    await addDues(tester);
    await walkDues(tester, (_) async {});
    await finish(tester);
  });
}
