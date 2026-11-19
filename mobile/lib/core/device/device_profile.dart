import 'package:flutter/foundation.dart' show defaultTargetPlatform;

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import 'timezone_currencies.dart';

export 'timezone_currencies.dart'
    show
        countryForTimezone,
        currencyForRegion,
        currencyForTimezone,
        detectCurrency;

/// Facts about this phone that the server wants at sign-up.
class DeviceProfile {
  const DeviceProfile();

  /// Shown in the user's session list later, e.g. "android" or "iOS".
  String get deviceName => defaultTargetPlatform.name;

  /// BCP 47 language tag, e.g. "en-BD".
  String get locale => PlatformDispatcher.instance.locale.toLanguageTag();

  /// ISO 3166 region code from the system locale, or null when unset.
  String? get countryCode => PlatformDispatcher.instance.locale.countryCode;

  /// IANA time zone such as "Asia/Dhaka". Falls back to UTC if unknown.
  Future<String> timezone() async {
    try {
      return (await FlutterTimezone.getLocalTimezone()).identifier;
    } on Object {
      return 'UTC';
    }
  }

  /// Synchronous currency fallback from the phone's locale region.
  String get defaultCurrency => currencyForRegion(countryCode);

  /// Starting currency from the device's time zone (accurate even on en-US
  /// devices), falling back to [countryCode] and finally USD.
  Future<String> detectDefaultCurrency() async {
    try {
      final tz = await timezone();
      return detectCurrency(timezone: tz, countryCode: countryCode);
    } on Object {
      return defaultCurrency;
    }
  }
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

final detectedCurrencyProvider = FutureProvider<String>(
  (ref) => ref.watch(deviceProfileProvider).detectDefaultCurrency(),
);
