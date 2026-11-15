import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/local_database.dart';
import '../../../core/device/device_profile.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/token_store.dart';
import '../data/auth_api.dart';
import '../data/google_auth.dart';
import '../domain/app_user.dart';

/// Where the user is in the login flow.
sealed class AuthState {
  const AuthState();
}

/// Reading the saved session at app start.
class AuthLoading extends AuthState {
  const AuthLoading();
}

class SignedOut extends AuthState {
  const SignedOut();
}

class SignedIn extends AuthState {
  const SignedIn(this.user);
  final AppUser user;
}

class AuthController extends Notifier<AuthState> {
  AuthApi get _api => ref.read(authApiProvider);
  SessionManager get _session => ref.read(sessionManagerProvider);
  TokenStore get _store => ref.read(tokenStoreProvider);
  DeviceProfile get _device => ref.read(deviceProfileProvider);
  LocalDatabase get _local => ref.read(localDatabaseProvider);

  @override
  AuthState build() {
    final sub = ref
        .watch(sessionManagerProvider)
        .onSessionExpired
        .listen((_) => state = const SignedOut());
    ref.onDispose(sub.cancel);
    unawaited(_restore());
    return const AuthLoading();
  }

  /// Opens the app with the saved session. Works offline: if the server
  /// cannot be reached, the last known profile is used.
  Future<void> _restore() async {
    final tokens = await _session.current();
    if (tokens == null) return _set(const SignedOut());

    final cached = await _store.readUser();
    if (cached != null) {
      final user = AppUser.fromJson(cached);
      await _claimLocalData(user.id);
      _set(SignedIn(user));
    }

    try {
      await refreshUser();
      final now = state;
      if (cached == null && now is SignedIn) await _claimLocalData(now.user.id);
    } on ApiException catch (e) {
      if (e.isNetworkError) {
        if (cached == null) _set(const SignedOut());
        return;
      }
      if (e.statusCode == 401) {
        await _session.clear();
        _set(const SignedOut());
      }
    }
  }

  Future<void> login(String email, String password) async {
    final result = await _api.login(
      email: email.trim(),
      password: password,
      deviceName: _device.deviceName,
    );
    await _establish(result);
  }

  Future<void> register({
    required String email,
    required String password,
    required String name,
    required String baseCurrency,
  }) async {
    final result = await _api.register(
      email: email.trim(),
      password: password,
      deviceName: _device.deviceName,
      profile: await _profile(name: name, baseCurrency: baseCurrency),
    );
    await _establish(result);
  }

  /// Returns false if the user closed the Google dialog.
  Future<bool> loginWithGoogle() async {
    final idToken = await ref.read(googleAuthProvider).signIn();
    if (idToken == null) return false;
    final result = await _api.loginWithGoogle(
      idToken: idToken,
      deviceName: _device.deviceName,
      profile: await _profile(baseCurrency: _device.defaultCurrency),
    );
    await _establish(result);
    return true;
  }

  /// Ends the session on the server (best effort) and on the phone.
  Future<void> logout() async {
    final tokens = await _session.current();
    if (tokens != null) {
      try {
        await _api.logout(tokens.refreshToken);
      } on ApiException {
        // Offline: the local logout still happens; the token expires on its own.
      }
    }
    try {
      await ref.read(googleAuthProvider).signOut();
    } on Object {
      // Not signed in with Google, or the plugin is unavailable.
    }
    await _session.clear();
    // Logging out removes this user's data from the phone, with its key.
    try {
      await _local.wipe();
    } on Object catch (e, st) {
      userMessage(e, st); // report; the user is logged out regardless
    }
    _set(const SignedOut());
  }

  /// Reloads the profile from the server.
  Future<void> refreshUser() async {
    final user = await _api.me();
    await _store.writeUser(user.toJson());
    if (state is! SignedOut) _set(SignedIn(user));
  }

  /// Confirms an email address from a link. Works logged in or out.
  Future<void> verifyEmail(String token) async {
    await _api.verifyEmail(token);
    if (state is SignedIn) await refreshUser();
  }

  Future<void> _establish(AuthResult result) async {
    await _session.save(result.tokens);
    await _store.writeUser(result.user.toJson());
    await _claimLocalData(result.user.id);
    _set(SignedIn(result.user));
  }

  /// Opens the encrypted local database for [userId], wiping another
  /// user's data first. A failure is reported but does not block login:
  /// the screens that need local data show their own error.
  Future<void> _claimLocalData(String userId) async {
    try {
      await _local.claimFor(userId);
    } on Object catch (e, st) {
      userMessage(e, st);
    }
  }

  Future<SignUpProfile> _profile({
    String name = '',
    required String baseCurrency,
  }) async => SignUpProfile(
    name: name.trim(),
    baseCurrency: baseCurrency,
    timezone: await _device.timezone(),
    locale: _device.locale,
  );

  void _set(AuthState s) {
    if (ref.mounted) state = s;
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
