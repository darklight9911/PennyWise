import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/token_store.dart';
import '../domain/app_user.dart';

/// Result of any successful login or sign-up.
class AuthResult {
  const AuthResult(this.user, this.tokens);
  final AppUser user;
  final AuthTokens tokens;
}

/// Details sent on sign-up so the account starts with the right settings.
class SignUpProfile {
  const SignUpProfile({
    this.name = '',
    required this.baseCurrency,
    required this.timezone,
    required this.locale,
  });

  final String name;
  final String baseCurrency;
  final String timezone;
  final String locale;

  Map<String, dynamic> toJson() => {
    'name': name,
    'base_currency': baseCurrency,
    'timezone': timezone,
    'locale': locale,
  };
}

/// Calls the /v1/auth endpoints. Every method throws [ApiException] on failure.
class AuthApi {
  AuthApi(this._dio);
  final Dio _dio;

  static final _public = Options(extra: AuthInterceptor.noAuth);

  Future<AuthResult> register({
    required String email,
    required String password,
    required String deviceName,
    required SignUpProfile profile,
  }) => _authCall('/v1/auth/register', {
    'email': email,
    'password': password,
    'device_name': deviceName,
    ...profile.toJson(),
  });

  Future<AuthResult> login({
    required String email,
    required String password,
    required String deviceName,
  }) => _authCall('/v1/auth/login', {
    'email': email,
    'password': password,
    'device_name': deviceName,
  });

  Future<AuthResult> loginWithGoogle({
    required String idToken,
    required String deviceName,
    required SignUpProfile profile,
  }) => _authCall('/v1/auth/google', {
    'id_token': idToken,
    'device_name': deviceName,
    ...profile.toJson(),
  });

  Future<void> logout(String refreshToken) => _call(
    () => _dio.post<void>(
      '/v1/auth/logout',
      data: {'refresh_token': refreshToken},
      options: _public,
    ),
  );

  Future<AppUser> me() => _call(() async {
    final res = await _dio.get<Map<String, dynamic>>('/v1/me');
    return AppUser.fromJson(res.data!['user'] as Map<String, dynamic>);
  });

  Future<void> verifyEmail(String token) => _call(
    () => _dio.post<void>(
      '/v1/auth/verify-email',
      data: {'token': token},
      options: _public,
    ),
  );

  Future<void> resendVerification() =>
      _call(() => _dio.post<void>('/v1/auth/resend-verification'));

  Future<void> forgotPassword(String email) => _call(
    () => _dio.post<void>(
      '/v1/auth/forgot-password',
      data: {'email': email},
      options: _public,
    ),
  );

  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) => _call(
    () => _dio.post<void>(
      '/v1/auth/reset-password',
      data: {'token': token, 'new_password': newPassword},
      options: _public,
    ),
  );

  Future<AuthResult> _authCall(String path, Map<String, dynamic> body) =>
      _call(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          path,
          data: body,
          options: _public,
        );
        final data = res.data!;
        return AuthResult(
          AppUser.fromJson(data['user'] as Map<String, dynamic>),
          AuthTokens.fromJson(data['tokens'] as Map<String, dynamic>),
        );
      });

  Future<T> _call<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(ref.watch(dioProvider)),
);
