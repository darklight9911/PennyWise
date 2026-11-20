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

  testWidgets('Profile row replaces inline card and opens profile modal', (
    tester,
  ) async {
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);
    await tapOn(tester, find.text('Settings'));

    // Profile is a plain ListTile row with no inline profile card.
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('ann@example.com · not confirmed'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
    expect(find.text('Not confirmed'), findsNothing);
    expect(find.text('Confirm your email'), findsNothing);

    await tapOn(tester, find.text('Profile'));

    expect(find.text('Profile details'), findsOneWidget);
    expect(find.text('Account & Email'), findsOneWidget);
    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Confirm your email'), findsOneWidget);
    expect(find.text('Regional Info'), findsOneWidget);
    expect(find.text('Time zone'), findsOneWidget);
    expect(find.text('Main currency'), findsWidgets);
    expect(find.text('Security'), findsOneWidget);
    expect(find.text('Sign-in method'), findsOneWidget);
    expect(find.text('Email not confirmed'), findsOneWidget);

    await tapOn(tester, find.widgetWithText(FilledButton, 'Done'));
    expect(find.text('Profile details'), findsNothing);

    await finish(tester);
  });

  testWidgets('guest Profile row shows Offline guest and opens guest modal', (
    tester,
  ) async {
    h.store.guestProfile = {
      'base_currency': 'USD',
      'timezone': 'UTC',
      'locale': 'en',
      'name': '',
    };
    await pumpApp(tester, h);
    await tapOn(tester, find.text('Settings'));

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Offline guest'), findsOneWidget);

    await tapOn(tester, find.text('Profile'));

    expect(find.text('Profile details'), findsOneWidget);
    expect(find.text('Guest User'), findsOneWidget);
    expect(find.text('Using offline as guest'), findsOneWidget);

    await tapOn(tester, find.widgetWithText(FilledButton, 'Done'));
    expect(find.text('Profile details'), findsNothing);

    await finish(tester);
  });
}
