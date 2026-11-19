import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/core/device/device_profile.dart';
import 'package:pennywise/core/device/timezone_currencies.dart';
import 'package:pennywise/core/router/routes.dart';
import 'package:pennywise/core/utils/currencies.dart';
import 'package:pennywise/features/auth/application/auth_controller.dart';
import 'package:pennywise/features/auth/domain/app_user.dart';
import 'package:pennywise/features/auth/domain/validators.dart';

void main() {
  group('authRedirect', () {
    const user = AppUser(
      id: '1',
      email: 'a@b.co',
      name: '',
      baseCurrency: 'USD',
      timezone: 'UTC', //
      locale: 'en',
      emailVerified: true,
      hasPassword: true,
      googleLinked: false,
    );
    const signedIn = SignedIn(user);

    final cases = <(AuthState, String, String?)>[
      // While loading, everything waits on the splash screen.
      (const AuthLoading(), Routes.dashboard, Routes.splash),
      (const AuthLoading(), Routes.splash, null),
      // Signed out: only the login screens.
      (const SignedOut(), Routes.dashboard, Routes.login),
      (const SignedOut(), Routes.settings, Routes.login),
      (const SignedOut(), Routes.splash, Routes.login),
      (const SignedOut(), Routes.login, null),
      (const SignedOut(), Routes.register, null),
      (const SignedOut(), Routes.forgotPassword, null),
      // Signed in: login screens bounce to the dashboard.
      (signedIn, Routes.login, Routes.dashboard),
      (signedIn, Routes.register, Routes.dashboard),
      (signedIn, Routes.splash, Routes.dashboard),
      (signedIn, Routes.settings, null),
      // A reset link opens in every state.
      (const AuthLoading(), Routes.resetPassword, null),
      (const SignedOut(), Routes.resetPassword, null),
      (signedIn, Routes.resetPassword, null),
    ];
    for (final (state, from, want) in cases) {
      test('${state.runtimeType} at $from -> ${want ?? "stay"}', () {
        expect(authRedirect(state, from), want);
      });
    }
  });

  group('validators', () {
    test('email', () {
      expect(validateEmail(''), isNotNull);
      expect(validateEmail('ann'), isNotNull);
      expect(validateEmail('ann@example'), isNotNull);
      expect(validateEmail(' ann@example.com '), isNull);
    });

    test('new password counts characters, not bytes', () {
      expect(validateNewPassword('short'), contains('10'));
      expect(validateNewPassword('é' * 10), isNull);
      expect(validateNewPassword('a' * 129), isNotNull);
    });

    test('login password only needs to be non-empty', () {
      expect(validateLoginPassword(''), isNotNull);
      expect(validateLoginPassword('x'), isNull);
    });
  });

  test('currencyForRegion', () {
    expect(currencyForRegion('BD'), 'BDT');
    expect(currencyForRegion('DE'), 'EUR');
    expect(currencyForRegion('JP'), 'JPY');
    expect(currencyForRegion('ZZ'), 'USD');
    expect(currencyForRegion(null), 'USD');
    for (final c in ['BDT', 'EUR', 'JPY', 'GBP', 'INR']) {
      expect(supportedCurrencies, contains(c));
    }
  });

  test('detectCurrency prefers timezone over locale region', () {
    expect(detectCurrency(timezone: 'Asia/Dhaka', countryCode: 'US'), 'BDT');
    expect(detectCurrency(timezone: 'Asia/Dacca', countryCode: 'US'), 'BDT');
    expect(detectCurrency(timezone: 'Asia/Kolkata', countryCode: 'US'), 'INR');
    expect(detectCurrency(timezone: 'Europe/London', countryCode: 'US'), 'GBP');
    expect(detectCurrency(timezone: 'Europe/Berlin', countryCode: 'US'), 'EUR');
    expect(
      detectCurrency(timezone: 'Europe/Stockholm', countryCode: 'US'),
      'SEK',
    );
    expect(detectCurrency(timezone: 'Asia/Tokyo', countryCode: 'US'), 'JPY');
    expect(detectCurrency(timezone: 'UTC', countryCode: 'GB'), 'GBP');
    expect(detectCurrency(timezone: 'UTC', countryCode: null), 'USD');
  });

  test('regionCurrencies and timezoneCountries are consistent', () {
    final catalogCodes = {for (final c in allCurrencies) c.code};
    for (final entry in regionCurrencies.entries) {
      expect(catalogCodes, contains(entry.value), reason: entry.key);
    }
    for (final entry in timezoneCountries.entries) {
      expect(regionCurrencies.keys, contains(entry.value), reason: entry.key);
    }
  });
}
