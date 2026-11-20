import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pennywise/app.dart';
import 'package:pennywise/core/theme/app_theme.dart';
import 'package:pennywise/core/widgets/responsive_layout.dart';

import '../support/test_app.dart';
import '../widget_test.dart' show finish, pumpApp, settle, tapOn;

void main() {
  Future<void> pumpViewportApp(
    WidgetTester tester,
    TestHarness h,
    Size logicalSize, {
    double textScale = 1.0,
  }) async {
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
}
