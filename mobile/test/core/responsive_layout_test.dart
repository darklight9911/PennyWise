import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pennywise/app.dart';
import 'package:pennywise/core/theme/app_theme.dart';
import 'package:pennywise/core/widgets/responsive_layout.dart';
import 'package:pennywise/features/ledger/application/ledger_providers.dart';

import '../features/dashboard/dashboard_flow_test.dart' show untilDone;
import '../support/test_app.dart';
import '../widget_test.dart' show finish, logIn, pumpApp, pw, settle, tapOn;

void main() {
  Future<TestHarness> pumpSeededViewport(
    WidgetTester tester,
    Size logicalSize, {
    double textScale = 1.0,
  }) async {
    final h = TestHarness();
    h.backend.seedUser('ann@example.com', pw);
    tester.view.physicalSize = logicalSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    if (textScale != 1.0) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    await tester.pumpWidget(
      ProviderScope(overrides: h.overrides, child: const PennyWiseApp()),
    );
    await settle(tester);
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

  Future<void> pumpViewportApp(
    WidgetTester tester,
    TestHarness h,
    Size logicalSize,
  ) async {
    tester.view.physicalSize = logicalSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(overrides: h.overrides, child: const PennyWiseApp()),
    );
    await settle(tester);
  }

  testWidgets('ResponsiveBody caps width at ContentWidths.content on desktop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const boxKey = ValueKey('box');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ResponsiveBody(
            child: SizedBox(key: boxKey, width: double.infinity, height: 100),
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byKey(boxKey));
    expect(size.width, ContentWidths.content);
    expect(
      tester.getTopLeft(find.byKey(boxKey)).dx,
      (1280 - ContentWidths.content) / 2,
    );
  });

  testWidgets('ResponsiveBody fills narrow phone width (320x640)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const boxKey = ValueKey('box');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ResponsiveBody(
            child: SizedBox(key: boxKey, width: double.infinity, height: 100),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(boxKey)).width, 320);
  });

  testWidgets('ResponsiveLayout helpers adapt padding and breakpoints', (
    tester,
  ) async {
    Future<void> checkWidth(
      double width, {
      required double expectedPad,
      required bool expectedRail,
      required bool expectedCompact,
    }) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      late double pad;
      late bool rail;
      late bool compact;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              pad = ResponsiveLayout.horizontalPadding(context);
              rail = ResponsiveLayout.useRail(context);
              compact = ResponsiveLayout.isCompact(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(pad, expectedPad);
      expect(rail, expectedRail);
      expect(compact, expectedCompact);
    }

    await checkWidth(
      320,
      expectedPad: Spacing.md,
      expectedRail: false,
      expectedCompact: true,
    );
    await checkWidth(
      393,
      expectedPad: Spacing.lg,
      expectedRail: false,
      expectedCompact: true,
    );
    await checkWidth(
      640,
      expectedPad: Spacing.lg,
      expectedRail: false,
      expectedCompact: false,
    );
    await checkWidth(
      720,
      expectedPad: Spacing.lg,
      expectedRail: true,
      expectedCompact: false,
    );
  });

  testWidgets(
    'AppShell renders NavigationBar on phone and interactive NavigationRail on desktop',
    (tester) async {
      final h1 = TestHarness();
      h1.store.guestProfile = {
        'base_currency': 'USD',
        'timezone': 'UTC',
        'locale': 'en',
        'name': '',
      };
      await pumpApp(tester, h1);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      await finish(tester);

      final h2 = TestHarness();
      h2.store.guestProfile = {
        'base_currency': 'USD',
        'timezone': 'UTC',
        'locale': 'en',
        'name': '',
      };
      await pumpViewportApp(tester, h2, const Size(1024, 768));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);

      for (final tab in ['Transactions', 'Reports', 'Settings', 'Home']) {
        await tapOn(tester, find.text(tab).last);
      }
      await finish(tester);
    },
  );

  testWidgets(
    'primary screens render without overflow on narrow phone (320x640 at 2.0x text scale)',
    (tester) async {
      await pumpSeededViewport(tester, const Size(320, 640), textScale: 2.0);
      expect(find.byType(NavigationBar), findsOneWidget);
      for (final tab in ['Home', 'Transactions', 'Reports', 'Settings']) {
        await tapOn(tester, find.text(tab).last);
        expect(tester.takeException(), isNull, reason: tab);
      }
      await finish(tester);
    },
  );

  testWidgets(
    'primary screens cap content width and pass a11y guidelines on desktop (1024x768)',
    (tester) async {
      final handle = tester.ensureSemantics();
      await pumpSeededViewport(tester, const Size(1024, 768));
      expect(find.byType(NavigationRail), findsOneWidget);

      for (final tab in ['Home', 'Transactions', 'Reports', 'Settings']) {
        await tapOn(tester, find.text(tab).last);
        final constrained = find
            .descendant(
              of: find.byType(ResponsiveBody).last,
              matching: find.byType(ConstrainedBox),
            )
            .first;
        expect(
          tester.getSize(constrained).width,
          lessThanOrEqualTo(ContentWidths.content),
          reason: tab,
        );
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

      handle.dispose();
      await finish(tester);
    },
  );
}
