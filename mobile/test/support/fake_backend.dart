import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// An in-memory imitation of the pennyWise auth API, plugged into Dio as
/// its HTTP adapter. It follows the real server's rules that matter to the
/// app: refresh tokens rotate and a reused one ends the session.
class FakeBackend implements HttpClientAdapter {
  FakeBackend({DateTime Function()? now}) : now = now ?? DateTime.now;

  DateTime Function() now;
  Duration accessTtl = const Duration(minutes: 15);

  /// When true, every request fails like a phone with no signal.
  bool offline = false;

  /// Delay for /refresh, to make parallel requests overlap.
  Duration refreshDelay = Duration.zero;

  final users = <String, Map<String, dynamic>>{}; // email -> user
  final passwords = <String, String>{};
  final _access = <String, String>{}; // token -> email
  final _refresh = <String, ({String email, bool used})>{};
  final calls = <String>[]; // "POST /v1/auth/login", ...
  int _n = 0;

  int callCount(String pathSuffix) =>
      calls.where((c) => c.endsWith(pathSuffix)).length;

  /// Creates a user directly (no HTTP), e.g. for login tests.
  void seedUser(String email, String password, {bool verified = false}) {
    users[email] = _user(email, verified: verified);
    passwords[email] = password;
  }

  /// Makes every issued access token invalid, as after a server-side expiry.
  void revokeAllAccessTokens() => _access.clear();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    final path = options.uri.path;
    calls.add('${options.method} $path');
    final body = (options.data as Map?)?.cast<String, dynamic>() ?? {};

    switch ('${options.method} $path') {
      case 'POST /v1/auth/register':
        final email = (body['email'] as String).toLowerCase();
        if (users.containsKey(email)) {
          return _error(
            409,
            'email_taken',
            'an account with this email already exists',
          );
        }
        if ((body['password'] as String).length < 10) {
          return _error(
            422,
            'validation_failed',
            'password too short',
            field: 'password',
          );
        }
        users[email] = _user(
          email,
          name: body['name'] as String? ?? '',
          currency: body['base_currency'] as String?,
        );
        passwords[email] = body['password'] as String;
        return _json(201, {'user': users[email], 'tokens': _issue(email)});

      case 'POST /v1/auth/login':
        final email = (body['email'] as String).toLowerCase();
        if (passwords[email] != body['password']) {
          return _error(
            401,
            'invalid_credentials',
            'email or password is wrong',
          );
        }
        return _json(200, {'user': users[email], 'tokens': _issue(email)});

      case 'POST /v1/auth/refresh':
        if (refreshDelay > Duration.zero) {
          await Future<void>.delayed(refreshDelay);
        }
        final t = body['refresh_token'] as String;
        final rt = _refresh[t];
        if (rt == null) {
          return _error(401, 'invalid_refresh_token', 'session expired');
        }
        if (rt.used) {
          // Reuse = theft: kill every refresh token of this user.
          _refresh.removeWhere((_, v) => v.email == rt.email);
          return _error(401, 'invalid_refresh_token', 'session expired');
        }
        _refresh[t] = (email: rt.email, used: true);
        return _json(200, {'tokens': _issue(rt.email)});

      case 'POST /v1/auth/logout':
        _refresh.remove(body['refresh_token']);
        return _empty(204);

      case 'POST /v1/auth/verify-email':
        if (body['token'] != 'good-token') {
          return _error(
            400,
            'invalid_link',
            'this link is invalid or has expired',
          );
        }
        for (final u in users.values) {
          u['email_verified'] = true;
        }
        return _empty(204);

      case 'POST /v1/auth/forgot-password':
        return _empty(202);

      case 'POST /v1/auth/reset-password':
        return body['token'] == 'good-token'
            ? _empty(204)
            : _error(
                400,
                'invalid_link',
                'this link is invalid or has expired',
              );

      case 'POST /v1/auth/resend-verification':
      case 'GET /v1/me':
        final auth = options.headers['Authorization'] as String?;
        final email = auth == null
            ? null
            : _access[auth.replaceFirst('Bearer ', '')];
        if (email == null) {
          return _error(
            401,
            'invalid_token',
            'access token is invalid or expired',
          );
        }
        return path.endsWith('/me')
            ? _json(200, {'user': users[email]})
            : _empty(202);
    }
    return _error(404, 'not_found', 'route not found');
  }

  Map<String, dynamic> _issue(String email) {
    _n++;
    final access = 'access-$_n';
    final refresh = 'refresh-$_n';
    _access[access] = email;
    _refresh[refresh] = (email: email, used: false);
    return {
      'access_token': access,
      'access_expires_at': now().add(accessTtl).toUtc().toIso8601String(),
      'refresh_token': refresh,
      'refresh_expires_at': now()
          .add(const Duration(days: 30))
          .toUtc()
          .toIso8601String(),
      'token_type': 'Bearer',
    };
  }

  Map<String, dynamic> _user(
    String email, {
    String name = '',
    String? currency,
    bool verified = false,
  }) => {
    'id': 'user-${email.hashCode}',
    'email': email,
    'name': name,
    'base_currency': currency ?? 'USD',
    'base_currency_status': 'ok',
    'locale': 'en',
    'timezone': 'UTC',
    'email_verified': verified,
    'has_password': true,
    'google_linked': false,
    'created_at': '2026-11-15T00:00:00Z',
  };

  ResponseBody _json(int status, Object body) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  ResponseBody _error(
    int status,
    String code,
    String message, {
    String? field,
  }) => _json(status, {
    'error': {'code': code, 'message': message, 'field': ?field},
  });

  ResponseBody _empty(int status) => ResponseBody.fromString('', status);

  @override
  void close({bool force = false}) {}
}
