import 'package:flutter/foundation.dart' show defaultTargetPlatform;

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

/// Facts about this phone that the server wants at sign-up.
class DeviceProfile {
  const DeviceProfile();

  /// Shown in the user's session list later, e.g. "android" or "iOS".
  String get deviceName => defaultTargetPlatform.name;

  /// BCP 47 language tag, e.g. "en-BD".
  String get locale => PlatformDispatcher.instance.locale.toLanguageTag();

  /// IANA time zone such as "Asia/Dhaka". Falls back to UTC if unknown.
  Future<String> timezone() async {
    try {
      return (await FlutterTimezone.getLocalTimezone()).identifier;
    } on Object {
      return 'UTC';
    }
  }

  /// A sensible starting currency from the phone's region. The user can change it.
  String get defaultCurrency =>
      currencyForRegion(PlatformDispatcher.instance.locale.countryCode);
}

/// Currency used in a country (ISO 3166 code -> ISO 4217 code).
/// Covers the currencies offered in the sign-up picker; anything else -> USD.
String currencyForRegion(String? country) {
  const euro = {
    'AT', 'BE', 'CY', 'DE', 'EE', 'ES', 'FI', 'FR', 'GR', 'HR', 'IE', 'IT', //
    'LT', 'LU', 'LV', 'MT', 'NL', 'PT', 'SI', 'SK',
  };
  if (country == null) return 'USD';
  if (euro.contains(country)) return 'EUR';
  return const {
        'US': 'USD',
        'GB': 'GBP',
        'BD': 'BDT',
        'IN': 'INR',
        'PK': 'PKR',
        'NP': 'NPR',
        'LK': 'LKR',
        'JP': 'JPY',
        'CN': 'CNY',
        'KR': 'KRW',
        'CA': 'CAD',
        'AU': 'AUD',
        'NZ': 'NZD',
        'SG': 'SGD',
        'MY': 'MYR',
        'ID': 'IDR',
        'TH': 'THB',
        'PH': 'PHP',
        'AE': 'AED',
        'SA': 'SAR',
        'TR': 'TRY',
        'CH': 'CHF',
        'SE': 'SEK',
        'NO': 'NOK',
        'DK': 'DKK',
        'PL': 'PLN',
        'BR': 'BRL',
        'MX': 'MXN',
        'ZA': 'ZAR',
        'NG': 'NGN',
        'EG': 'EGP',
        'KE': 'KES',
      }[country] ??
      'USD';
}

/// Currencies offered in the sign-up picker (most common first).
const supportedCurrencies = [
  'USD', 'EUR', 'GBP', 'BDT', 'INR', 'PKR', 'NPR', 'LKR', 'JPY', 'CNY', //
  'KRW', 'CAD', 'AUD', 'NZD', 'SGD', 'MYR', 'IDR', 'THB', 'PHP', 'AED',
  'SAR', 'TRY', 'CHF', 'SEK', 'NOK', 'DKK', 'PLN', 'BRL', 'MXN', 'ZAR',
  'NGN', 'EGP', 'KES',
];

final deviceProfileProvider = Provider<DeviceProfile>(
  (ref) => const DeviceProfile(),
);
