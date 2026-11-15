import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import 'api_exception.dart';
import 'token_store.dart';

/// Owns the current session and refreshes it.
///
/// Refresh tokens work once: the server treats a reused one as stolen and
/// ends the session. So only ONE refresh may run at a time. Every caller
/// that needs a refresh while one is running waits for that same one.
class SessionManager {
  SessionManager({
    required Dio refreshDio,
    required TokenStore store,
    DateTime Function()? now,
  }) : _dio = refreshDio,
       _store = store, // ignore: prefer_initializing_formals
       _now = now ?? DateTime.now;

  final Dio _dio;
  final TokenStore _store;
  final DateTime Function() _now;

  AuthTokens? _tokens;
  bool _loaded = false;
  Future<AuthTokens?>? _refreshing;
  final _expired = StreamController<void>.broadcast();

  /// Fires when the server rejects the refresh token: the user must log in again.
  Stream<void> get onSessionExpired => _expired.stream;

  Future<AuthTokens?> current() async {
    if (!_loaded) {
      _tokens = await _store.readTokens();
      _loaded = true;
    }
    return _tokens;
  }

  Future<void> save(AuthTokens tokens) async {
    _tokens = tokens;
    _loaded = true;
    await _store.writeTokens(tokens);
  }

  Future<void> clear() async {
    _tokens = null;
    _loaded = true;
    await _store.clear();
  }

  /// An access token that is valid for at least 30 more seconds, refreshing
  /// first if needed. Null when logged out. Throws ApiException (network)
  /// when a refresh is needed but the server cannot be reached.
  Future<String?> validAccessToken() async {
    final t = await current();
    if (t == null) return null;
    if (!t.accessExpiresSoon(_now())) return t.accessToken;
    return (await refresh())?.accessToken;
  }

  /// Gets a new token pair. Concurrent calls share one request.
  Future<AuthTokens?> refresh() =>
      _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<AuthTokens?> _doRefresh() async {
    final t = await current();
    if (t == null) return null;
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/auth/refresh',
        data: {'refresh_token': t.refreshToken},
      );
      final tokens = AuthTokens.fromJson(
        res.data!['tokens'] as Map<String, dynamic>,
      );
      await save(tokens);
      return tokens;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401) {
        // Expired, revoked or reused: this session is over.
        await clear();
        _expired.add(null);
        return null;
      }
      // Offline or server trouble: keep the session, the user is not logged out.
      throw ApiException.fromDio(e);
    }
  }

  void dispose() => _expired.close();
}

/// Adds the access token to requests and retries once after a refresh
/// when the server says the token is invalid.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._session, this._dio);

  final SessionManager _session;
  final Dio _dio;

  /// Put `extra: {'auth': false}` on requests that must not send a token.
  static const noAuth = {'auth': false};

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra['auth'] == false) return handler.next(options);
    try {
      final token = await _session.validAccessToken();
      if (token == null) {
        return handler.reject(
          DioException(
            requestOptions: options,
            error: const ApiException(
              code: 'unauthenticated',
              message: 'Please log in again.',
              statusCode: 401,
            ),
          ),
        );
      }
      options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    } on ApiException catch (e) {
      handler.reject(DioException(requestOptions: options, error: e));
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final req = err.requestOptions;
    final retryable =
        err.response?.statusCode == 401 &&
        req.extra['auth'] != false &&
        req.extra['retried'] != true;
    if (!retryable) return handler.next(err);

    try {
      // If another request already refreshed, just retry with the new token.
      final sent = (req.headers['Authorization'] as String?)?.substring(7);
      final now = await _session.current();
      final fresh = (now != null && now.accessToken != sent)
          ? now
          : await _session.refresh();
      if (fresh == null) return handler.next(err);

      req.extra['retried'] = true;
      req.headers['Authorization'] = 'Bearer ${fresh.accessToken}';
      handler.resolve(await _dio.fetch<dynamic>(req));
    } on DioException catch (e) {
      handler.next(e);
    } on ApiException catch (e) {
      handler.next(DioException(requestOptions: req, error: e));
    }
  }
}

BaseOptions _options(AppConfig config) => BaseOptions(
  baseUrl: config.apiBaseUrl,
  connectTimeout: const Duration(seconds: 10),
  receiveTimeout: const Duration(seconds: 20),
  sendTimeout: const Duration(seconds: 20),
  contentType: Headers.jsonContentType,
  responseType: ResponseType.json,
);

final sessionManagerProvider = Provider<SessionManager>((ref) {
  final config = ref.watch(appConfigProvider);
  final session = SessionManager(
    refreshDio: Dio(_options(config)), // no interceptors: avoids loops
    store: ref.watch(tokenStoreProvider),
  );
  ref.onDispose(session.dispose);
  return session;
});

/// The Dio instance every API call uses.
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(_options(ref.watch(appConfigProvider)));
  dio.interceptors.add(AuthInterceptor(ref.watch(sessionManagerProvider), dio));
  ref.onDispose(dio.close);
  return dio;
});
