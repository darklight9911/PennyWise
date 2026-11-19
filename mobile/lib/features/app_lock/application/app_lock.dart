import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/device_prefs.dart';
import '../../auth/application/auth_controller.dart';
import 'biometrics.dart';

/// After this long in the background the app locks again.
const relockAfter = Duration(seconds: 30);

/// Wrong PINs in a row before a pause, and how long the pause is.
const maxTries = 5;
const tryAgainAfter = Duration(seconds: 30);

/// Clock for the lock rules. Tests replace it.
final lockClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

@immutable
class AppLockState {
  const AppLockState({
    this.ready = false,
    this.enabled = false,
    this.biometric = false,
    this.pinLength = 4,
    this.locked = false,
    this.covered = false,
    this.failed = 0,
    this.waitUntil,
  });

  /// Settings are read (until then the app stays covered, so nothing shows
  /// before a lock could appear).
  final bool ready;
  final bool enabled;
  final bool biometric;
  final int pinLength;
  final bool locked;

  /// The app is not in front: hide its content from the app switcher.
  final bool covered;
  final int failed;
  final DateTime? waitUntil;

  AppLockState copyWith({
    bool? ready,
    bool? enabled,
    bool? biometric,
    int? pinLength,
    bool? locked,
    bool? covered,
    int? failed,
    DateTime? Function()? waitUntil,
  }) => AppLockState(
    ready: ready ?? this.ready,
    enabled: enabled ?? this.enabled,
    biometric: biometric ?? this.biometric,
    pinLength: pinLength ?? this.pinLength,
    locked: locked ?? this.locked,
    covered: covered ?? this.covered,
    failed: failed ?? this.failed,
    waitUntil: waitUntil == null ? this.waitUntil : waitUntil(),
  );
}

enum UnlockResult { unlocked, wrong, wait }

/// Hashes a PIN with its salt, many rounds, so the stored value does not
/// give the PIN away quickly even if the Keystore were read.
String hashPin(String pin, List<int> salt) {
  var digest = sha256.convert([...salt, ...utf8.encode(pin)]).bytes;
  for (var i = 0; i < 20000; i++) {
    digest = sha256.convert([...digest, ...salt]).bytes;
  }
  return base64.encode(digest);
}

/// The optional app lock: a PIN, and fingerprint or face if the user
/// wants. Locks at start and after [relockAfter] in the background.
class AppLockController extends Notifier<AppLockState> {
  static const _hashKey = 'lock_pin_hash';
  static const _saltKey = 'lock_pin_salt';
  static const _lengthKey = 'lock_pin_length';
  static const _bioKey = 'lock_biometric';

  AppLifecycleListener? _lifecycle;
  DateTime? _hiddenAt;

  DevicePrefs get _prefs => ref.read(devicePrefsProvider);
  DateTime _now() => ref.read(lockClockProvider)();

  @override
  AppLockState build() {
    _lifecycle = AppLifecycleListener(
      onInactive: _hide,
      onHide: _hide,
      onResume: _show,
    );
    ref.onDispose(() => _lifecycle?.dispose());
    // Logging out must not leave the next person someone else's lock.
    // (A guest who signs in keeps their own lock.)
    ref.listen(authControllerProvider, (prev, next) {
      if (prev is SignedIn && next is! SignedIn) unawaited(_clear());
    });
    unawaited(_load());
    return const AppLockState();
  }

  Future<void> _load() async {
    final hash = await _prefs.read(_hashKey);
    final bio = await _prefs.read(_bioKey) == 'true';
    final len = int.tryParse(await _prefs.read(_lengthKey) ?? '') ?? 4;
    if (!ref.mounted) return;
    final on = hash != null;
    state = state.copyWith(
      ready: true,
      enabled: on,
      biometric: on && bio,
      pinLength: len,
      locked: on,
    );
  }

  void _hide() {
    _hiddenAt ??= _now();
    if (state.enabled && !state.covered) state = state.copyWith(covered: true);
  }

  void _show() {
    final hidden = _hiddenAt;
    _hiddenAt = null;
    final relock =
        state.enabled &&
        hidden != null &&
        _now().difference(hidden) >= relockAfter;
    state = state.copyWith(covered: false, locked: state.locked || relock);
  }

  /// Turns the lock on with a new PIN (4 to 6 digits).
  Future<void> enable(String pin) async {
    assert(RegExp(r'^\d{4,6}$').hasMatch(pin));
    final rnd = Random.secure();
    final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
    await _prefs.write(_saltKey, base64.encode(salt));
    await _prefs.write(_hashKey, hashPin(pin, salt));
    await _prefs.write(_lengthKey, '${pin.length}');
    state = state.copyWith(
      enabled: true,
      pinLength: pin.length,
      locked: false,
      failed: 0,
      waitUntil: () => null,
    );
  }

  /// Turns the lock off (the caller checked the PIN).
  Future<void> disable() async {
    await _clear();
  }

  Future<void> _clear() async {
    for (final k in [_hashKey, _saltKey, _lengthKey, _bioKey]) {
      await _prefs.delete(k);
    }
    if (ref.mounted) {
      state = state.copyWith(
        enabled: false,
        biometric: false,
        locked: false,
        failed: 0,
        waitUntil: () => null,
      );
    }
  }

  Future<void> setBiometric(bool on) async {
    await _prefs.write(_bioKey, '$on');
    state = state.copyWith(biometric: on);
  }

  /// Whether [pin] is the saved PIN (no counting; for settings).
  Future<bool> checkPin(String pin) async {
    final hash = await _prefs.read(_hashKey);
    final salt = await _prefs.read(_saltKey);
    if (hash == null || salt == null) return false;
    return hashPin(pin, base64.decode(salt)) == hash;
  }

  Future<UnlockResult> unlockWithPin(String pin) async {
    final wait = state.waitUntil;
    if (wait != null && _now().isBefore(wait)) return UnlockResult.wait;
    if (await checkPin(pin)) {
      state = state.copyWith(locked: false, failed: 0, waitUntil: () => null);
      return UnlockResult.unlocked;
    }
    final failed = state.failed + 1;
    state = state.copyWith(
      failed: failed,
      waitUntil: () =>
          failed % maxTries == 0 ? _now().add(tryAgainAfter) : null,
    );
    return failed % maxTries == 0 ? UnlockResult.wait : UnlockResult.wrong;
  }

  Future<bool> unlockWithBiometrics() async {
    if (!state.biometric) return false;
    final ok = await ref
        .read(biometricsProvider)
        .authenticate('Unlock pennyWise');
    if (ok && ref.mounted) {
      state = state.copyWith(locked: false, failed: 0, waitUntil: () => null);
    }
    return ok;
  }
}

final appLockProvider = NotifierProvider<AppLockController, AppLockState>(
  AppLockController.new,
);
