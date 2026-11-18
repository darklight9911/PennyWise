import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

/// Fingerprint / face unlock. Tests replace it.
abstract class Biometrics {
  /// Whether the phone has a fingerprint or face set up.
  Future<bool> available();

  /// Shows the system prompt. True if the user was recognised.
  Future<bool> authenticate(String reason);
}

class LocalBiometrics implements Biometrics {
  final _auth = LocalAuthentication();

  @override
  Future<bool> available() async {
    try {
      return await _auth.isDeviceSupported() &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
      );
    } on Object {
      return false; // cancelled, locked out or not available: use the PIN
    }
  }
}

final biometricsProvider = Provider<Biometrics>((ref) => LocalBiometrics());

final biometricsAvailableProvider = FutureProvider<bool>(
  (ref) => ref.watch(biometricsProvider).available(),
);
