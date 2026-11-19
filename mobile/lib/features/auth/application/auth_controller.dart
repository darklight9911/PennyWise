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
import '../domain/profile.dart';

/// Where the user is in the login flow.
sealed class AuthState {
  const AuthState();

  /// What the screens show (name, main currency, time zone), or null
  /// while nothing is known yet.
  Profile? get profile => null;
}

/// Reading the saved session at app start (or switching users).
class AuthLoading extends AuthState {
  const AuthLoading();
}

/// First launch: no account and no guest profile yet. The app asks for the
/// main currency, then opens as a [Guest].
class SetupNeeded extends AuthState {
  const SetupNeeded();
}

/// Using the app without an account. Everything works on the phone; data
/// is kept locally and uploaded once the user signs in.
class Guest extends AuthState {
  const Guest(this.guestProfile);
  final Profile guestProfile;

  @override
  Profile get profile => guestProfile;
}

class SignedIn extends AuthState {
  const SignedIn(this.user, {this.sessionExpired = false});
  final AppUser user;

  /// The server no longer accepts this session (e.g. the password changed
  /// on another phone). The data stays usable offline; logging in again
  /// resumes syncing.
  final bool sessionExpired;

  @override
  Profile get profile => user.profile;
}

class AuthController extends Notifier<AuthState> {
  AuthApi get _api => ref.read(authApiProvider);
  SessionManager get _session => ref.read(sessionManagerProvider);
  TokenStore get _store => ref.read(tokenStoreProvider);
  DeviceProfile get _device => ref.read(deviceProfileProvider);
  LocalDatabase get _local => ref.read(localDatabaseProvider);

  @override
  AuthState build() {
    final sub = ref.watch(sessionManagerProvider).onSessionExpired.listen((_) {
      // Keep the user's data on the phone: only syncing stops.
      final now = state;
      if (now is SignedIn) _set(SignedIn(now.user, sessionExpired: true));
    });
    ref.onDispose(sub.cancel);
    unawaited(_restore());
    return const AuthLoading();
  }

  /// Opens the app with the saved session. Works offline: if the server
  /// cannot be reached, the last known profile is used.
  Future<void> _restore() async {
    final tokens = await _session.current();
    if (tokens == null) return _openWithoutAccount();

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
        if (cached == null) await _openWithoutAccount();
        return;
      }
      if (e.statusCode == 401) {
        final now = state;
        if (now is SignedIn) {
          // Keep the data; ask to log in again to sync.
          _set(SignedIn(now.user, sessionExpired: true));
        } else {
          await _session.clear();
          await _openWithoutAccount();
        }
      }
    }
  }

  /// No session: continue as a guest, or ask for the main currency first.
  Future<void> _openWithoutAccount() async {
    final saved = await _store.readGuestProfile();
    _set(saved == null ? const SetupNeeded() : Guest(Profile.fromJson(saved)));
  }

  /// Finishes the first launch: the app opens without an account.
  Future<void> startAsGuest({required String baseCurrency}) async {
    final profile = Profile(
      name: '',
      baseCurrency: baseCurrency,
      timezone: await _device.timezone(),
      locale: _device.locale,
    );
    await _store.writeGuestProfile(profile.toJson());
    _set(Guest(profile));
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
    final tz = await _device.timezone();
    final result = await _api.loginWithGoogle(
      idToken: idToken,
      deviceName: _device.deviceName,
      profile: SignUpProfile(
        name: '',
        baseCurrency: detectCurrency(
          timezone: tz,
          countryCode: _device.countryCode,
        ),
        timezone: tz,
        locale: _device.locale,
      ),
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
    await _endLocally();
  }

  /// Without an account: deletes everything on this phone and starts
  /// empty again (same main currency).
  Future<void> eraseGuestData() async {
    final now = state;
    if (now is! Guest) return;
    _set(const AuthLoading()); // screens drop the database first
    try {
      await _local.wipe();
    } finally {
      ref.read(localDataEpochProvider.notifier).bump();
      _set(Guest(now.guestProfile));
    }
  }

  /// Deletes the account on the server, then everything on the phone.
  /// Throws (and changes nothing) if the server refuses, e.g. a wrong
  /// password or no connection.
  Future<void> deleteAccount({String? password}) async {
    await _api.deleteAccount(password: password);
    await _endLocally();
  }

  Future<void> _endLocally() async {
    final was = state;
    try {
      await ref.read(googleAuthProvider).signOut();
    } on Object {
      // Not signed in with Google, or the plugin is unavailable.
    }
    await _session.clear();
    // Leave the account FIRST: screens and sync drop the local database,
    // so nothing uses it while it is being deleted.
    _set(const AuthLoading());
    // Logging out removes this user's data from the phone, with its key.
    try {
      await _local.wipe();
    } on Object catch (e, st) {
      userMessage(e, st); // report; the user is logged out regardless
    }
    ref.read(localDataEpochProvider.notifier).bump();
    // Then the app goes on without an account, empty, in the same currency.
    final guest = Profile(
      name: '',
      baseCurrency: was.profile?.baseCurrency ?? _device.defaultCurrency,
      timezone: was.profile?.timezone ?? await _device.timezone(),
      locale: was.profile?.locale ?? _device.locale,
    );
    await _store.writeGuestProfile(guest.toJson());
    _set(Guest(guest));
  }

  /// Reloads the profile from the server.
  Future<void> refreshUser() async {
    final user = await _api.me();
    await _store.writeUser(user.toJson());
    if (state is SignedIn || state is AuthLoading) _set(SignedIn(user));
  }

  /// Switches the main currency. Signed in, the server converts all amounts
  /// in the background; until then the user is "recalculating". Without an
  /// account only the profile on the phone changes.
  Future<void> changeBaseCurrency(String currency) async {
    final now = state;
    if (now is Guest) {
      final profile = now.guestProfile.copyWith(baseCurrency: currency);
      await _store.writeGuestProfile(profile.toJson());
      _set(Guest(profile));
      return;
    }
    final user = await _api.updateProfile(baseCurrency: currency);
    await _store.writeUser(user.toJson());
    if (state is SignedIn) _set(SignedIn(user));
  }

  /// Confirms an email address from a link. Works logged in or out.
  Future<void> verifyEmail(String token) async {
    await _api.verifyEmail(token);
    if (state is SignedIn) await refreshUser();
  }

  Future<void> _establish(AuthResult result) async {
    await _session.save(result.tokens);
    await _store.writeUser(result.user.toJson());
    // Guest data on this phone now belongs to this account and is merged
    // into it with the next sync.
    final was = state;
    await _claimLocalData(
      result.user.id,
      guestCurrency: was is Guest ? was.guestProfile.baseCurrency : null,
    );
    _set(SignedIn(result.user));
  }

  /// Opens the encrypted local database for [userId]. Data made without an
  /// account is kept (and merged into the account); another user's data is
  /// wiped first. A failure is reported but does not block login: the
  /// screens that need local data show their own error.
  Future<void> _claimLocalData(String userId, {String? guestCurrency}) async {
    try {
      final db = await _local.claimFor(userId);
      if (guestCurrency != null &&
          await db.readMeta(LocalDatabase.mergePendingKey) != null) {
        await db.writeMeta(LocalDatabase.mergeFromCurrencyKey, guestCurrency);
      }
    } on Object catch (e, st) {
      userMessage(e, st);
    }
  }

  /// The main currency to suggest when creating an account: the one
  /// already used on this phone, if any.
  String? get suggestedCurrency => state.profile?.baseCurrency;

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

/// The current profile, signed in or not (null while starting up).
final profileProvider = Provider<Profile?>(
  (ref) => ref.watch(authControllerProvider).profile,
);

/// The main currency every total is shown in.
final baseCurrencyProvider = Provider<String>(
  (ref) => ref.watch(profileProvider)?.baseCurrency ?? 'USD',
);
