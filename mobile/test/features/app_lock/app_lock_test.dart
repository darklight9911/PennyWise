import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pennywise/features/app_lock/application/app_lock.dart';
import 'package:pennywise/features/app_lock/presentation/pin_pad.dart';

import '../../support/test_app.dart';
import '../../widget_test.dart' show finish, logIn, pumpApp, pw, settle, tapOn;

void main() {
  late TestHarness h;
  setUp(() {
    h = TestHarness();
    h.backend.seedUser('ann@example.com', pw);
  });

  test('PIN hashes are salted and stable', () {
    expect(hashPin('1234', [1, 2, 3]), hashPin('1234', [1, 2, 3]));
    expect(hashPin('1234', [1, 2, 3]), isNot(hashPin('1234', [1, 2, 4])));
    expect(hashPin('1234', [1, 2, 3]), isNot(hashPin('1235', [1, 2, 3])));
  });

  Future<void> type(WidgetTester tester, String digits) async {
    for (final d in digits.split('')) {
      await tester.tap(
        find.descendant(of: find.byType(PinPad), matching: find.text(d)),
      );
      await tester.pump();
    }
    await settle(tester);
  }

  Future<void> background(WidgetTester tester, Duration away) async {
    for (final s in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump();
    h.clock = h.clock.add(away);
    for (final s in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await settle(tester);
  }

  final locked = find.text('pennyWise is locked');

  Future<void> turnOn(WidgetTester tester) async {
    await tapOn(tester, find.text('Settings'));
    await tapOn(tester, find.text('App lock'));
    expect(find.text('Choose a PIN'), findsOneWidget);
    await type(tester, '12');
    await tapOn(tester, find.text('Next'));
    expect(find.text('Use at least 4 digits'), findsOneWidget);
    await type(tester, '34');
    await tapOn(tester, find.text('Next'));
    await type(tester, '1235');
    expect(find.text("The PINs don't match. Start again."), findsOneWidget);
    await type(tester, '1234');
    await tapOn(tester, find.text('Next'));
    await type(tester, '1234');
    expect(find.text('Choose a PIN'), findsNothing);
    expect(h.prefs.values['lock_pin_hash'], isNotNull);
    expect(
      h.prefs.values.values,
      isNot(contains('1234')),
      reason: 'never stored plain',
    );
  }

  testWidgets('lock after 30 s away; wrong PIN, pause, right PIN', (
    tester,
  ) async {
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);
    await turnOn(tester);
    expect(find.text('Unlock with fingerprint or face'), findsOneWidget);

    await background(tester, const Duration(seconds: 10));
    expect(locked, findsNothing, reason: 'a short switch away does not lock');

    await background(tester, const Duration(seconds: 31));
    expect(locked, findsOneWidget);
    expect(h.biometrics.prompts, 0, reason: 'fingerprint is off');

    await type(tester, '9999');
    expect(find.text('Wrong PIN. Try again.'), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      await type(tester, '9999');
    }
    expect(find.text('Too many tries. Wait 30 seconds.'), findsOneWidget);
    await type(tester, '1234');
    expect(locked, findsOneWidget, reason: 'the right PIN waits too');

    h.clock = h.clock.add(const Duration(seconds: 31));
    await tester.pump(const Duration(seconds: 31));
    await type(tester, '1234');
    expect(locked, findsNothing);
    expect(
      find.text('App lock'),
      findsOneWidget,
      reason: 'back where the user was',
    );
    await finish(tester);
  });

  testWidgets('a fresh start is locked; fingerprint unlocks', (tester) async {
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);
    await turnOn(tester);
    await tapOn(tester, find.text('Unlock with fingerprint or face'));
    expect(h.prefs.values['lock_biometric'], 'true');

    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, h);
    expect(
      locked,
      findsNothing,
      reason: 'the fingerprint prompt came first and succeeded',
    );
    expect(h.biometrics.prompts, 1);

    h.biometrics.willSucceed = false;
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, h);
    expect(locked, findsOneWidget);
    h.biometrics.willSucceed = true;
    await tapOn(
      tester,
      find.bySemanticsLabel('Unlock with fingerprint or face'),
    );
    expect(locked, findsNothing);
    await finish(tester);
  });

  testWidgets('forgot PIN: log out removes the lock', (tester) async {
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);
    await turnOn(tester);
    await background(tester, const Duration(minutes: 5));
    await tapOn(tester, find.text('Forgot PIN?'));
    await tapOn(tester, find.widgetWithText(FilledButton, 'Log out'));
    expect(find.text('Welcome back'), findsOneWidget);
    expect(h.prefs.values.containsKey('lock_pin_hash'), isFalse);

    await logIn(tester, 'ann@example.com', pw);
    expect(locked, findsNothing);
    await finish(tester);
  });

  testWidgets('turning it off needs the PIN', (tester) async {
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);
    await turnOn(tester);
    await tapOn(tester, find.text('App lock'));
    await tester.enterText(find.byType(TextField), '0000');
    await tapOn(tester, find.text('Turn off'));
    expect(find.text('Wrong PIN'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '1234');
    await tapOn(tester, find.text('Turn off'));
    expect(h.prefs.values.containsKey('lock_pin_hash'), isFalse);
    expect(find.text('Unlock with fingerprint or face'), findsNothing);
    await finish(tester);
  });
}
