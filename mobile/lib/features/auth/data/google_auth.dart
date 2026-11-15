import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/app_config.dart';

/// Gets a Google ID token for our backend.
abstract class GoogleAuth {
  bool get enabled;

  /// Returns an ID token, or null if the user closed the Google dialog.
  Future<String?> signIn();

  Future<void> signOut();
}

class PluginGoogleAuth implements GoogleAuth {
  PluginGoogleAuth(this._serverClientId);

  final String _serverClientId;
  Future<void>? _init;

  @override
  bool get enabled => _serverClientId.isNotEmpty;

  Future<void> _ensureInit() => _init ??= GoogleSignIn.instance.initialize(
    // The backend's client ID. The ID token is issued "to" it, which is
    // exactly what the server checks (GOOGLE_CLIENT_IDS).
    serverClientId: _serverClientId,
  );

  @override
  Future<String?> signIn() async {
    if (!enabled) return null;
    await _ensureInit();
    try {
      final account = await GoogleSignIn.instance.authenticate();
      return account.authentication.idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  @override
  Future<void> signOut() async {
    if (!enabled) return;
    await _ensureInit();
    await GoogleSignIn.instance.signOut();
  }
}

final googleAuthProvider = Provider<GoogleAuth>(
  (ref) => PluginGoogleAuth(ref.watch(appConfigProvider).googleServerClientId),
);
