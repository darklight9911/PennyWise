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
      Theme.of(tester.element(find.text('Settings').first)).brightness;

  testWidgets('pick dark mode; it is remembered', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);
    await tapOn(tester, find.text('Settings'));
    expect(find.text('Same as phone'), findsOneWidget);
    expect(brightness(tester), Brightness.light);

    await tapOn(tester, find.text('Appearance'));
    await tapOn(tester, find.text('Dark'));
    expect(brightness(tester), Brightness.dark);
    expect(h.prefs.values['theme_mode'], 'dark');

    // A fresh start reads the saved choice.
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, h);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(find.byType(PennyWiseApp), findsOneWidget);
    await finish(tester);
  });
}
