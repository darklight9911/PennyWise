// End-to-end: the app's real networking code against a running Go API.
// Skipped unless a URL is given:
//
//   flutter test test/e2e --dart-define=E2E_API_URL=http://localhost:8080
//
// It creates a throwaway account on that server. Never point it at production.
@Tags(['e2e'])
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/core/config/app_config.dart';
import 'package:pennywise/core/device/device_profile.dart';
import 'package:pennywise/core/network/api_client.dart';
import 'package:pennywise/core/network/api_exception.dart';
import 'package:pennywise/core/network/token_store.dart';
import 'package:pennywise/features/auth/application/auth_controller.dart';
import 'package:pennywise/features/auth/data/auth_api.dart';
import 'package:pennywise/features/auth/data/google_auth.dart';

import '../support/test_app.dart' show FakeDeviceProfile, FakeGoogleAuth;

const apiUrl = String.fromEnvironment('E2E_API_URL');

void main() {
  late ProviderContainer c;
  late InMemoryTokenStore store;

  setUp(() {
    store = InMemoryTokenStore();
    c = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(apiBaseUrl: apiUrl),
        ),
        tokenStoreProvider.overrideWithValue(store),
        deviceProfileProvider.overrideWithValue(const FakeDeviceProfile()),
        googleAuthProvider.overrideWithValue(FakeGoogleAuth()),
      ],
    );
    addTearDown(c.dispose);
  });

  Future<void> untilSettled() async {
    for (
      var i = 0;
      i < 50 && c.read(authControllerProvider) is AuthLoading;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test(
    'register, use, refresh, log out, log in again',
    skip: apiUrl.isEmpty ? 'set --dart-define=E2E_API_URL' : null,
    () async {
      final email = 'e2e-${DateTime.now().microsecondsSinceEpoch}@example.com';
      const password = 'e2e-strong-password';
      final auth = c.read(authControllerProvider.notifier);
      await untilSettled();
      expect(c.read(authControllerProvider), isA<SignedOut>());

      // Register: server returns user + tokens, the app stores them.
      await auth.register(
        email: email,
        password: password,
        name: 'E2E',
        baseCurrency: 'BDT',
      );
      final state = c.read(authControllerProvider);
      expect(state, isA<SignedIn>());
      final user = (state as SignedIn).user;
      expect(user.email, email);
      expect(user.baseCurrency, 'BDT');
      expect(user.timezone, 'Asia/Dhaka');
      expect(user.emailVerified, isFalse);
      final first = store.tokens!;

      // An authenticated call through the interceptor.
      expect((await c.read(authApiProvider).me()).id, user.id);

      // Force a refresh: the server rotates the refresh token.
      final rotated = await c.read(sessionManagerProvider).refresh();
      expect(rotated, isNotNull);
      expect(rotated!.refreshToken, isNot(first.refreshToken));
      expect(store.tokens!.refreshToken, rotated.refreshToken);

      // The OLD refresh token is now "used": the real server must reject it
      // and kill the session family (theft protection).
      final raw = Dio(BaseOptions(baseUrl: apiUrl));
      await expectLater(
        raw.post<dynamic>(
          '/v1/auth/refresh',
          data: {'refresh_token': first.refreshToken},
        ),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'status',
            401,
          ),
        ),
      );
      // ...so the app's current token is dead too, and the next refresh logs out.
      expect(await c.read(sessionManagerProvider).refresh(), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(authControllerProvider), isA<SignedOut>());

      // Log in again, then log out cleanly.
      await auth.login(email, password);
      expect(c.read(authControllerProvider), isA<SignedIn>());
      final session = store.tokens!;
      await auth.logout();
      expect(c.read(authControllerProvider), isA<SignedOut>());
      expect(store.tokens, isNull);
      await expectLater(
        raw.post<dynamic>(
          '/v1/auth/refresh',
          data: {'refresh_token': session.refreshToken},
        ),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'status',
            401,
          ),
        ),
      );

      // Wrong password: the server's error reaches the app intact.
      await expectLater(
        auth.login(email, 'not-the-password'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'invalid_credentials',
          ),
        ),
      );
      // Forgot password never reveals whether the email exists.
      await c
          .read(authApiProvider)
          .forgotPassword(
            'nobody-${DateTime.now().millisecondsSinceEpoch}@example.com',
          );
    },
  );
}
