import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The login session the server gave us.
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.accessExpiresAt,
    required this.refreshToken,
    required this.refreshExpiresAt,
  });

  final String accessToken;
  final DateTime accessExpiresAt;
  final String refreshToken;
  final DateTime refreshExpiresAt;

  /// True when the access token is expired or about to expire, so the app
  /// refreshes before sending a request that would fail anyway.
  bool accessExpiresSoon(DateTime now) =>
      !now.isBefore(accessExpiresAt.subtract(const Duration(seconds: 30)));

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
    accessToken: json['access_token'] as String,
    accessExpiresAt: DateTime.parse(json['access_expires_at'] as String),
    refreshToken: json['refresh_token'] as String,
    refreshExpiresAt: DateTime.parse(json['refresh_expires_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'access_expires_at': accessExpiresAt.toUtc().toIso8601String(),
    'refresh_token': refreshToken,
    'refresh_expires_at': refreshExpiresAt.toUtc().toIso8601String(),
  };
}

/// Where the session and the last known user profile are kept.
abstract class TokenStore {
  Future<AuthTokens?> readTokens();
  Future<void> writeTokens(AuthTokens tokens);

  /// The last /me response, so the app can open offline.
  Future<Map<String, dynamic>?> readUser();
  Future<void> writeUser(Map<String, dynamic> user);

  Future<void> clear();
}

/// Keeps everything in the Android Keystore / iOS Keychain.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              // Not synced to iCloud or restored to another phone.
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  static const _tokensKey = 'auth_tokens';
  static const _userKey = 'auth_user';

  @override
  Future<AuthTokens?> readTokens() async {
    final raw = await _storage.read(key: _tokensKey);
    if (raw == null) return null;
    try {
      return AuthTokens.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      await _storage.delete(key: _tokensKey); // corrupt: start over
      return null;
    }
  }

  @override
  Future<void> writeTokens(AuthTokens tokens) =>
      _storage.write(key: _tokensKey, value: jsonEncode(tokens.toJson()));

  @override
  Future<Map<String, dynamic>?> readUser() async {
    final raw = await _storage.read(key: _userKey);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> writeUser(Map<String, dynamic> user) =>
      _storage.write(key: _userKey, value: jsonEncode(user));

  @override
  Future<void> clear() async {
    await _storage.delete(key: _tokensKey);
    await _storage.delete(key: _userKey);
  }
}

/// For tests.
class InMemoryTokenStore implements TokenStore {
  AuthTokens? tokens;
  Map<String, dynamic>? user;

  @override
  Future<AuthTokens?> readTokens() async => tokens;
  @override
  Future<void> writeTokens(AuthTokens t) async => tokens = t;
  @override
  Future<Map<String, dynamic>?> readUser() async => user;
  @override
  Future<void> writeUser(Map<String, dynamic> u) async => user = u;
  @override
  Future<void> clear() async {
    tokens = null;
    user = null;
  }
}

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());
