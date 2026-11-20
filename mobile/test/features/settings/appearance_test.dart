import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pennywise/app.dart';

import '../../support/test_app.dart';
import '../../widget_test.dart' show finish, logIn, pumpApp, pw, tapOn;

void main() {
  late TestHarness h;
  setUp(() {
    h = TestHarness();
    h.backend.seedUser('ann@example.com', pw);
  });

  Brightness brightness(WidgetTester tester) =>
      Theme.of(tester.element(find.byKey(const ValueKey('theme_toggle'))))
          .brightness;

  testWidgets(
    'toggle dark mode on dashboard; it is remembered and removed from settings',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await pumpApp(tester, h);
      await logIn(tester, 'ann@example.com', pw);

      // Initial state: light mode on Dashboard
      expect(brightness(tester), Brightness.light);
      expect(find.byKey(const ValueKey('theme_toggle')), findsOneWidget);

      // Toggle to dark mode directly on Dashboard
      await tapOn(tester, find.byKey(const ValueKey('theme_toggle')));
      expect(brightness(tester), Brightness.dark);
      expect(h.prefs.values['theme_mode'], 'dark');

      // Toggle back to light mode on Dashboard
      await tapOn(tester, find.byKey(const ValueKey('theme_toggle')));
      expect(brightness(tester), Brightness.light);
      expect(h.prefs.values['theme_mode'], 'light');

      // Toggle to dark mode again
      await tapOn(tester, find.byKey(const ValueKey('theme_toggle')));
      expect(brightness(tester), Brightness.dark);
      expect(h.prefs.values['theme_mode'], 'dark');

      // Appearance is removed from Settings
      await tapOn(tester, find.text('Settings'));
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Appearance'), findsNothing);

      // A fresh start reads the saved choice.
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, h);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      expect(find.byType(PennyWiseApp), findsOneWidget);
      await finish(tester);
    },
  );
}
