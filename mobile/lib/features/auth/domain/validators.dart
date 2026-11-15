/// Form checks that mirror the server rules, so users see mistakes at once.
/// The server still checks everything again.
library;

/// Same minimum as the backend (NIST: length matters, not symbol rules).
const minPasswordLength = 10;
const maxPasswordLength = 128;

final _emailShape = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

String? validateEmail(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return 'Enter your email';
  if (!_emailShape.hasMatch(v)) return 'Enter a valid email address';
  return null;
}

/// For new passwords (sign-up, reset).
String? validateNewPassword(String? value) {
  final length = value?.runes.length ?? 0;
  if (length == 0) return 'Choose a password';
  if (length < minPasswordLength) {
    return 'Use at least $minPasswordLength characters';
  }
  if (length > maxPasswordLength) {
    return 'Use at most $maxPasswordLength characters';
  }
  return null;
}

/// For the login form: only "not empty". Length rules could leak which
/// passwords are possible and lock out users of older, shorter passwords.
String? validateLoginPassword(String? value) =>
    (value == null || value.isEmpty) ? 'Enter your password' : null;

String? validateName(String? value) => (value?.trim().runes.length ?? 0) > 100
    ? 'Use at most 100 characters'
    : null;
