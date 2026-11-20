import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/test_app.dart';
import '../../widget_test.dart';

void main() {
  late TestHarness h;
  setUp(() {
    h = TestHarness();
    h.backend.seedUser('ann@example.com', pw);
  });

  testWidgets('clicking profile opens modal with structured profile details', (
    tester,
  ) async {
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);
    await tapOn(tester, find.text('Settings'));

    // The Profile section exists on Settings
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('ann@example.com · not confirmed'), findsOneWidget);

    // Tap on the profile tile
    await tapOn(tester, find.text('ann@example.com · not confirmed'));

    // The modal bottom sheet pops up
    expect(find.text('Profile details'), findsOneWidget);
    expect(find.text('Account & Email'), findsOneWidget);
    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Regional Info'), findsOneWidget);
    expect(find.text('Security'), findsOneWidget);
    expect(find.text('Sign-in method'), findsOneWidget);
    expect(find.text('Email not confirmed'), findsOneWidget);

    // Close the modal by tapping 'Done'
    await tapOn(tester, find.widgetWithText(FilledButton, 'Done'));
    expect(find.text('Profile details'), findsNothing);

    await finish(tester);
  });
}
