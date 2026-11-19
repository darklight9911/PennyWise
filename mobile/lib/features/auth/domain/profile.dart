import 'package:flutter/foundation.dart';

/// What the screens need to know about the person using the app, whether
/// they are signed in or using it without an account: a name to greet,
/// the main currency and the time zone.
@immutable
class Profile {
  const Profile({
    required this.name,
    required this.baseCurrency,
    required this.timezone,
    required this.locale,
    this.recalculating = false,
  });

  /// May be empty (no name given, or no account).
  final String name;
  final String baseCurrency;
  final String timezone;
  final String locale;

  /// Totals are being converted to a new main currency right now and
  /// should not be shown yet.
  final bool recalculating;

  Profile copyWith({String? name, String? baseCurrency, bool? recalculating}) =>
      Profile(
        name: name ?? this.name,
        baseCurrency: baseCurrency ?? this.baseCurrency,
        timezone: timezone,
        locale: locale,
        recalculating: recalculating ?? this.recalculating,
      );

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    name: json['name'] as String? ?? '',
    baseCurrency: json['base_currency'] as String? ?? 'USD',
    timezone: json['timezone'] as String? ?? 'UTC',
    locale: json['locale'] as String? ?? 'en',
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'base_currency': baseCurrency,
    'timezone': timezone,
    'locale': locale,
  };

  @override
  bool operator ==(Object other) =>
      other is Profile &&
      other.name == name &&
      other.baseCurrency == baseCurrency &&
      other.timezone == timezone &&
      other.locale == locale &&
      other.recalculating == recalculating;

  @override
  int get hashCode =>
      Object.hash(name, baseCurrency, timezone, locale, recalculating);
}
