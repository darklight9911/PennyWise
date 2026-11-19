import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pennywise/app.dart';
import 'package:pennywise/core/widgets/panda_mascot.dart';
import 'package:pennywise/features/ledger/application/ledger_providers.dart';
import 'package:pennywise/features/transactions/presentation/empty_transactions_stage.dart';

import '../../support/test_app.dart';
import '../../widget_test.dart' show finish, logIn, pumpApp, pw, settle, tapOn;
import '../dashboard/dashboard_flow_test.dart' show untilDone;

void main() {
  group('empty transactions helpers', () {
    test('pennyEmptyMood transitions with account state and pokes', () {
      expect(pennyEmptyMood(hasAccounts: false, pokeCount: 0), PandaMood.wave);
      expect(pennyEmptyMood(hasAccounts: false, pokeCount: 1), PandaMood.happy);
      expect(
        pennyEmptyMood(hasAccounts: false, pokeCount: 2),
        PandaMood.celebrate,
      );

      expect(
        pennyEmptyMood(hasAccounts: true, pokeCount: 0),
        PandaMood.sleeping,
      );
      expect(pennyEmptyMood(hasAccounts: true, pokeCount: 1), PandaMood.wave);
      expect(pennyEmptyMood(hasAccounts: true, pokeCount: 2), PandaMood.happy);
      expect(
        pennyEmptyMood(hasAccounts: true, pokeCount: 3),
        PandaMood.celebrate,
      );
    });

    test('pennyEmptyMessage adapts to account readiness and pokes', () {
      expect(
        pennyEmptyMessage(hasAccounts: false, pokeCount: 0),
        contains('Add your first account'),
      );
      expect(
        pennyEmptyMessage(hasAccounts: false, pokeCount: 1),
        contains('Hehe!'),
      );
      expect(
        pennyEmptyMessage(hasAccounts: true, pokeCount: 0),
        contains('taking a nap'),
      );
      expect(
        pennyEmptyMessage(hasAccounts: true, pokeCount: 1),
        contains('Wide awake!'),
      );
      expect(
        pennyEmptyMessage(hasAccounts: true, pokeCount: 2),
        contains('Ready whenever you are'),
      );
    });

    test('sampleCoffeeMinor respects currency decimal rules', () {
      expect(sampleCoffeeMinor('USD'), -450);
      expect(sampleCoffeeMinor('bdt'), -25000);
      expect(sampleCoffeeMinor('JPY'), -550);
      expect(sampleCoffeeMinor('KWD'), -1500);
    });
  });

  group('empty states flow', () {
    late TestHarness h;
    setUp(() {
      h = TestHarness();
      h.backend.seedUser('ann@example.com', pw);
    });

    Future<void> addBankAccount(WidgetTester tester) async {
      final store = await ProviderScope.containerOf(
        tester.element(find.byType(PennyWiseApp)),
      ).read(ledgerStoreProvider.future);
      await untilDone(tester, () async {
        await store.createAccount(
          name: 'Bank',
          type: 'bank',
          currency: 'USD',
          openingBalanceMinor: 10000,
        );
      });
      await settle(tester);
    }

    testWidgets('0 accounts: Penny greets and launchpad adds an account', (
      tester,
    ) async {
      await pumpApp(tester, h);
      await logIn(tester, 'ann@example.com', pw);
      await tapOn(tester, find.text('Transactions'));

      expect(find.text('No transactions yet'), findsOneWidget);
      expect(find.text('0 of 2 done'), findsOneWidget);
      expect(
        tester.widget<PandaMascot>(find.byType(PandaMascot)).mood,
        PandaMood.wave,
      );

      await tapOn(tester, find.byType(PandaMascot));
      expect(
        tester.widget<PandaMascot>(find.byType(PandaMascot)).mood,
        PandaMood.happy,
      );
      expect(find.textContaining('Hehe!'), findsOneWidget);

      await tapOn(tester, find.text('Add your first account'));
      expect(find.text('New account'), findsOneWidget);
      await finish(tester);
    });

    testWidgets(
      'with account: sleeping Penny wakes up, ghost preview and CTAs work',
      (tester) async {
        await pumpApp(tester, h);
        await logIn(tester, 'ann@example.com', pw);
        await addBankAccount(tester);

        await tapOn(tester, find.text('Transactions'));

        expect(find.text('1 of 2 done'), findsOneWidget);
        expect(find.text('Done · 1 account ready'), findsOneWidget);
        expect(find.text('Zzz'), findsOneWidget);
        expect(
          tester.widget<PandaMascot>(find.byType(PandaMascot)).mood,
          PandaMood.sleeping,
        );

        await tapOn(tester, find.byType(PandaMascot));
        expect(
          tester.widget<PandaMascot>(find.byType(PandaMascot)).mood,
          PandaMood.wave,
        );
        expect(find.textContaining('Wide awake!'), findsOneWidget);
        expect(find.text('Zzz'), findsNothing);

        expect(find.text('Morning coffee'), findsOneWidget);
        expect(find.text('Example'), findsOneWidget);
        expect(find.text('−4.50 USD'), findsOneWidget);

        await tapOn(tester, find.text('Add income'));
        expect(find.text('New income'), findsOneWidget);
        await tester.pageBack();
        await settle(tester);

        await tapOn(tester, find.text('Add expense'));
        expect(find.text('New expense'), findsOneWidget);
        await tester.pageBack();
        await settle(tester);

        await tapOn(tester, find.text('Morning coffee'));
        expect(find.text('New expense'), findsOneWidget);
        await finish(tester);
      },
    );

    testWidgets('dashboard empty recent card navigates by account state', (
      tester,
    ) async {
      await pumpApp(tester, h);
      await logIn(tester, 'ann@example.com', pw);

      await tester.scrollUntilVisible(
        find.text('No activity yet'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('No activity yet'), findsOneWidget);
      await tapOn(tester, find.text('Add account'));
      expect(find.text('New account'), findsOneWidget);
      await tester.pageBack();
      await settle(tester);

      await addBankAccount(tester);
      await tester.scrollUntilVisible(
        find.text('Add expense'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tapOn(tester, find.text('Add expense'));
      expect(find.text('New expense'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('reports empty state action navigates by account state', (
      tester,
    ) async {
      await pumpApp(tester, h);
      await logIn(tester, 'ann@example.com', pw);
      await tapOn(tester, find.text('Reports'));

      expect(find.text('Nothing to show yet'), findsOneWidget);
      await tapOn(tester, find.text('Add your first account'));
      expect(find.text('New account'), findsOneWidget);
      await tester.pageBack();
      await settle(tester);

      await addBankAccount(tester);
      await tapOn(tester, find.text('Add transaction'));
      expect(find.text('New expense'), findsOneWidget);
      await finish(tester);
    });

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets(
        'empty states pass accessibility without and with accounts (${mode.name})',
        (tester) async {
          h.prefs.values['theme_mode'] = mode.name;
          final handle = tester.ensureSemantics();
          await pumpApp(tester, h);
          await logIn(tester, 'ann@example.com', pw);

          // 0 accounts: Home, Transactions, Reports.
          for (final tab in ['Home', 'Transactions', 'Reports']) {
            await tapOn(tester, find.text(tab).last);
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
              reason: '$tab 0-accounts',
            );
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
              reason: '$tab 0-accounts',
            );
            await expectLater(
              tester,
              meetsGuideline(textContrastGuideline),
              reason: '$tab 0-accounts',
            );
          }

          // With account: Home, Transactions, Reports.
          await addBankAccount(tester);
          for (final tab in ['Home', 'Transactions', 'Reports']) {
            await tapOn(tester, find.text(tab).last);
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
              reason: '$tab with-account',
            );
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
              reason: '$tab with-account',
            );
            await expectLater(
              tester,
              meetsGuideline(textContrastGuideline),
              reason: '$tab with-account',
            );
          }

          handle.dispose();
          await finish(tester);
        },
      );
    }

    testWidgets('empty states have no overflow at double text size', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pumpApp(tester, h);
      await logIn(tester, 'ann@example.com', pw);

      for (final tab in ['Home', 'Transactions', 'Reports']) {
        await tapOn(tester, find.text(tab).last);
      }

      await addBankAccount(tester);
      for (final tab in ['Home', 'Transactions', 'Reports']) {
        await tapOn(tester, find.text(tab).last);
      }
      await finish(tester);
    });
  });
}
