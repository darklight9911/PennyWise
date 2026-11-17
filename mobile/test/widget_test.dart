import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pennywise/app.dart';
import 'package:pennywise/core/network/token_store.dart';
import 'package:pennywise/core/theme/app_colors.dart';

import 'support/test_app.dart';

const pw = 'a-strong-password';

Future<void> pumpApp(WidgetTester tester, TestHarness h) async {
  // A real phone screen (Pixel-like, 393 x 851 logical pixels).
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(overrides: h.overrides, child: const PennyWiseApp()),
  );
  await settle(tester);
}

/// Lets async work (fake HTTP, redirects, animations) finish.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

/// Ends a test that changed data: removes the app and lets the last
/// sync it started finish, so no timer is left running.
Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Scrolls [finder] into view, taps it and waits.
Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await settle(tester);
}

Finder field(String label) => find.widgetWithText(TextFormField, label);

Future<void> logIn(WidgetTester tester, String email, String password) async {
  await tester.enterText(field('Email'), email);
  await tester.enterText(field('Password'), password);
  await tapOn(tester, find.widgetWithText(FilledButton, 'Log in'));
}

void main() {
  late TestHarness h;
  setUp(() {
    h = TestHarness();
    h.backend.seedUser('ann@example.com', pw);
  });

  testWidgets('without a saved session the app opens on log in', (
    tester,
  ) async {
    await pumpApp(tester, h);
    expect(find.text('Welcome back'), findsOneWidget);
    // Google is not configured in tests, so its button is hidden.
    expect(find.text('Continue with Google'), findsNothing);
  });

  testWidgets('log in form checks fields before calling the server', (
    tester,
  ) async {
    await pumpApp(tester, h);
    await tapOn(tester, find.widgetWithText(FilledButton, 'Log in'));
    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    expect(h.backend.callCount('/login'), 0);
  });

  testWidgets(
    'wrong password shows the server message; right one opens the dashboard',
    (tester) async {
      await pumpApp(tester, h);
      await logIn(tester, 'ann@example.com', 'wrong-password');
      expect(find.text('email or password is wrong'), findsOneWidget);

      await logIn(tester, 'ann@example.com', pw);
      expect(find.text('Hi, ann'), findsOneWidget);
      expect(
        find.text('Confirm your email'),
        findsNothing,
        reason: 'the reminder lives in Settings, not on the dashboard',
      );
      expect(
        h.store.tokens,
        isNotNull,
        reason: 'session saved to secure storage',
      );
      await finish(tester);
    },
  );

  testWidgets('sign up creates the account and shows the dashboard', (
    tester,
  ) async {
    await pumpApp(tester, h);
    await tapOn(tester, find.text('Create an account'));

    await tester.enterText(field('Name (optional)'), 'Bo');
    await tester.enterText(field('Email'), 'bo@example.com');
    await tester.enterText(field('Password'), 'short');
    await tapOn(tester, find.widgetWithText(FilledButton, 'Create account'));
    expect(find.text('Use at least 10 characters'), findsOneWidget);
    expect(h.backend.callCount('/register'), 0);

    await tester.enterText(field('Password'), pw);
    await tapOn(tester, find.widgetWithText(FilledButton, 'Create account'));
    expect(find.text('Hi, Bo'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('an unexpected error still shows a message (no silent failure)', (
    tester,
  ) async {
    h = TestHarness(device: const BrokenDeviceProfile());
    await pumpApp(tester, h);
    await tapOn(tester, find.text('Create an account'));
    await tester.enterText(field('Email'), 'dee@example.com');
    await tester.enterText(field('Password'), pw);
    await tapOn(tester, find.widgetWithText(FilledButton, 'Create account'));
    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
    expect(
      tester.takeException(),
      isA<StateError>(),
      reason: 'and it is reported',
    );
    // The button works again for another try.
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Create account'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('sign up with a taken email marks the email field', (
    tester,
  ) async {
    await pumpApp(tester, h);
    await tapOn(tester, find.text('Create an account'));
    await tester.enterText(field('Email'), 'ann@example.com');
    await tester.enterText(field('Password'), pw);
    await tapOn(tester, find.widgetWithText(FilledButton, 'Create account'));
    expect(find.textContaining('already exists'), findsOneWidget);
  });

  testWidgets('a saved session opens the dashboard even offline', (
    tester,
  ) async {
    h.store.tokens = AuthTokens(
      accessToken: 'stale',
      accessExpiresAt: DateTime.now().add(const Duration(minutes: 10)),
      refreshToken: 'stale-refresh',
      refreshExpiresAt: DateTime.now().add(const Duration(days: 10)),
    );
    h.store.user = {
      'id': 'u1',
      'email': 'cy@example.com',
      'name': 'Cy',
      'base_currency': 'EUR', //
      'timezone': 'UTC', 'locale': 'en', 'email_verified': true,
      'has_password': true, 'google_linked': false,
    };
    h.backend.offline = true;

    await pumpApp(tester, h);
    expect(find.text('Hi, Cy'), findsOneWidget);
    expect(
      h.store.tokens,
      isNotNull,
      reason: 'offline must not log the user out',
    );
    await finish(tester);
  });

  testWidgets('log out from settings returns to log in', (tester) async {
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);

    await tapOn(tester, find.text('Settings'));
    expect(find.text('ann@example.com · not confirmed'), findsOneWidget);
    await tapOn(tester, find.text('Log out').first);
    await tapOn(tester, find.widgetWithText(FilledButton, 'Log out'));

    expect(find.text('Welcome back'), findsOneWidget);
    expect(h.store.tokens, isNull);
    expect(h.backend.callCount('/logout'), 1);
  });

  testWidgets('verify-email link confirms the address', (tester) async {
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);
    await tapOn(tester, find.text('Settings'));
    expect(find.text('Confirm your email'), findsOneWidget);

    h.links.add(Uri.parse('pennywise://verify-email?token=good-token'));
    await settle(tester);
    expect(find.text('Email confirmed. Thank you!'), findsOneWidget);
    expect(find.text('Confirm your email'), findsNothing);
    await finish(tester);
  });

  testWidgets('Settings can send the confirm-email link again', (tester) async {
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);
    await tapOn(tester, find.text('Settings'));
    await tapOn(tester, find.text('Send the link again'));
    expect(find.text('We sent a new link to ann@example.com.'), findsOneWidget);
    expect(h.backend.callCount('/resend-verification'), 1);
    await finish(tester);
  });

  testWidgets('an expired verify link explains what happened', (tester) async {
    await pumpApp(tester, h);
    h.links.add(Uri.parse('pennywise://verify-email?token=old'));
    await settle(tester);
    expect(find.textContaining('expired or was already used'), findsOneWidget);
  });

  testWidgets(
    'reset-password link opens the reset screen and leads to log in',
    (tester) async {
      await pumpApp(tester, h);
      h.links.add(Uri.parse('pennywise://reset-password?token=good-token'));
      await settle(tester);
      expect(find.text('Choose a new password'), findsOneWidget);

      await tester.enterText(field('New password'), 'brand-new-password');
      await tester.enterText(field('Repeat new password'), 'something-else-1');
      await tapOn(
        tester,
        find.widgetWithText(FilledButton, 'Save new password'),
      );
      expect(find.text('Passwords do not match'), findsOneWidget);

      await tester.enterText(
        field('Repeat new password'),
        'brand-new-password',
      );
      await tapOn(
        tester,
        find.widgetWithText(FilledButton, 'Save new password'),
      );
      expect(find.text('Welcome back'), findsOneWidget);
      expect(
        find.text('Password changed. Log in with your new password.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('after log in: palette applied and bottom navigation works', (
    tester,
  ) async {
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);

    final context = tester.element(find.byType(NavigationBar));
    expect(Theme.of(context).colorScheme.primary, AppColors.primary);
    expect(Theme.of(context).scaffoldBackgroundColor, AppColors.canvas);

    await tapOn(tester, find.text('Transactions'));
    expect(find.text('No transactions yet'), findsOneWidget);

    await tapOn(tester, find.text('Reports'));
    expect(find.text('Nothing to show yet'), findsOneWidget);

    await tapOn(tester, find.text('Home'));
    expect(find.text('Total balance'), findsOneWidget);
    await finish(tester);
  });
}
