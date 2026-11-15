import 'package:flutter/foundation.dart';

/// The logged-in user, as returned by the API (never contains secrets).
@immutable
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.name,
    required this.baseCurrency,
    required this.timezone,
    required this.locale,
    required this.emailVerified,
    required this.hasPassword,
    required this.googleLinked,
  });

  final String id;
  final String email;
  final String name;
  final String baseCurrency;
  final String timezone;
  final String locale;
  final bool emailVerified;
  final bool hasPassword;
  final bool googleLinked;

  /// Name if set, otherwise the part of the email before "@".
  String get displayName => name.isNotEmpty ? name : email.split('@').first;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String,
    email: json['email'] as String,
    name: json['name'] as String? ?? '',
    baseCurrency: json['base_currency'] as String? ?? 'USD',
    timezone: json['timezone'] as String? ?? 'UTC',
    locale: json['locale'] as String? ?? 'en',
    emailVerified: json['email_verified'] as bool? ?? false,
    hasPassword: json['has_password'] as bool? ?? false,
    googleLinked: json['google_linked'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'base_currency': baseCurrency,
    'timezone': timezone,
    'locale': locale,
    'email_verified': emailVerified,
    'has_password': hasPassword,
    'google_linked': googleLinked,
  };

  @override
  bool operator ==(Object other) =>
      other is AppUser &&
      other.id == id &&
      other.email == email &&
      other.name == name &&
      other.baseCurrency == baseCurrency &&
      other.timezone == timezone &&
      other.locale == locale &&
      other.emailVerified == emailVerified &&
      other.hasPassword == hasPassword &&
      other.googleLinked == googleLinked;

  @override
  int get hashCode => Object.hash(
    id,
    email,
    name,
    baseCurrency,
    timezone,
    locale,
    emailVerified,
    hasPassword,
    googleLinked,
  );
}
