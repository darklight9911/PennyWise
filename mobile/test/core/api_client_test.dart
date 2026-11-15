import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/core/network/api_client.dart';
import 'package:pennywise/core/network/api_exception.dart';
import 'package:pennywise/core/network/token_store.dart';
import 'package:pennywise/features/auth/data/auth_api.dart';

import '../support/fake_backend.dart';
import '../support/test_app.dart';

void main() {
  late TestHarness h;
  late DateTime clock;

  setUp(() {
    clock = DateTime.utc(2026, 11, 15, 12);
    h = TestHarness(backend: FakeBackend(now: () => clock));
    h.backend.seedUser('ann@example.com', 'a-strong-password');
  });

  /// Logs in through the API and stores the session, like the app does.
  Future<(Dio, SessionManager)> loggedIn() async {
    final c = h.container();
    addTearDown(c.dispose);
    final result = await c
        .read(authApiProvider)
        .login(
          email: 'ann@example.com',
          password: 'a-strong-password',
          deviceName: 't',
        );
    final session = c.read(sessionManagerProvider);
    await session.save(result.tokens);
    return (c.read(dioProvider), session);
  }

  test('sends the access token on authenticated requests', () async {
    final (dio, _) = await loggedIn();
    final res = await dio.get<Map<String, dynamic>>('/v1/me');
    expect(res.statusCode, 200);
    expect(h.backend.callCount('/refresh'), 0);
  });

  test(
    'refreshes before the request when the access token is about to expire',
    () async {
      final (dio, session) = await loggedIn();
      clock = clock.add(
        const Duration(minutes: 14, seconds: 45),
      ); // < 30 s left
      await dio.get<dynamic>('/v1/me');
      expect(h.backend.callCount('/refresh'), 1);
      expect((await session.current())!.refreshToken, isNot('refresh-1'));
    },
  );

  test(
    'parallel requests share ONE refresh (a second would look like theft)',
    () async {
      final (dio, session) = await loggedIn();
      h.backend.refreshDelay = const Duration(milliseconds: 50);
      clock = clock.add(const Duration(minutes: 20)); // access token expired

      final results = await Future.wait([
        for (var i = 0; i < 5; i++) dio.get<dynamic>('/v1/me'),
      ]);

      expect(results.every((r) => r.statusCode == 200), isTrue);
      expect(h.backend.callCount('/refresh'), 1);
      expect(
        await session.current(),
        isNotNull,
        reason: 'session must survive',
      );
    },
  );

  test('a 401 from the server triggers one refresh and a retry', () async {
    final (dio, _) = await loggedIn();
    h.backend.revokeAllAccessTokens();
    final res = await dio.get<dynamic>('/v1/me');
    expect(res.statusCode, 200);
    expect(h.backend.callCount('/refresh'), 1);
    expect(h.backend.callCount('/me'), 2);
  });

  test('a rejected refresh token ends the session', () async {
    final (dio, session) = await loggedIn();
    var expired = false;
    session.onSessionExpired.listen((_) => expired = true);

    // Someone else (a thief with a copy) uses our refresh token first.
    final mine = (await session.current())!;
    final thief = Dio(BaseOptions(baseUrl: TestHarness.config.apiBaseUrl))
      ..httpClientAdapter = h.backend;
    await thief.post<dynamic>(
      '/v1/auth/refresh',
      data: {'refresh_token': mine.refreshToken},
    );

    // Our next request needs a refresh; the server sees reuse and refuses.
    h.backend.revokeAllAccessTokens();
    await expectLater(
      dio.get<dynamic>('/v1/me'),
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'status',
          401,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(expired, isTrue);
    expect(await session.current(), isNull);
    expect(
      await h.store.readTokens(),
      isNull,
      reason: 'cleared from storage too',
    );
  });

  test(
    'offline refresh keeps the session (no logout without signal)',
    () async {
      final (dio, session) = await loggedIn();
      clock = clock.add(const Duration(minutes: 20));
      h.backend.offline = true;

      await expectLater(
        dio.get<dynamic>('/v1/me'),
        throwsA(
          isA<DioException>().having(
            (e) => ApiException.fromDio(e).isNetworkError,
            'isNetworkError',
            isTrue,
          ),
        ),
      );
      expect(await session.current(), isNotNull);

      h.backend.offline = false;
      expect((await dio.get<dynamic>('/v1/me')).statusCode, 200);
    },
  );

  test('ApiException reads the server error shape', () async {
    final c = h.container();
    addTearDown(c.dispose);
    await expectLater(
      c
          .read(authApiProvider)
          .login(email: 'ann@example.com', password: 'nope', deviceName: 't'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'invalid_credentials')
            .having((e) => e.statusCode, 'status', 401),
      ),
    );
  });

  test('tokens survive a JSON round trip', () {
    final t = AuthTokens(
      accessToken: 'a',
      accessExpiresAt: DateTime.utc(2026, 1, 1, 10),
      refreshToken: 'r',
      refreshExpiresAt: DateTime.utc(2026, 2, 1),
    );
    final back = AuthTokens.fromJson(t.toJson());
    expect(back.accessToken, 'a');
    expect(back.accessExpiresAt, t.accessExpiresAt);
    expect(back.accessExpiresSoon(DateTime.utc(2026, 1, 1, 9, 59, 31)), isTrue);
    expect(back.accessExpiresSoon(DateTime.utc(2026, 1, 1, 9, 59)), isFalse);
  });
}
