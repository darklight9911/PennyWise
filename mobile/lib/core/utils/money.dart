/// Money helpers. Amounts are always integer minor units (e.g. cents),
/// never doubles. This mirrors backend/internal/money.
library;

/// Currencies whose number of decimals is not 2 (ISO 4217).
const _minorUnits = <String, int>{
  // 0 decimals
  'BIF': 0, 'CLP': 0, 'DJF': 0, 'GNF': 0, 'ISK': 0, 'JPY': 0, 'KMF': 0,
  'KRW': 0, 'PYG': 0, 'RWF': 0, 'UGX': 0, 'UYI': 0, 'VND': 0, 'VUV': 0,
  'XAF': 0, 'XOF': 0, 'XPF': 0,
  // 3 decimals
  'BHD': 3, 'IQD': 3, 'JOD': 3, 'KWD': 3, 'LYD': 3, 'OMR': 3, 'TND': 3,
};

final _currencyCode = RegExp(r'^[A-Z]{3}$');

/// How many decimal places [currency] uses.
int currencyExponent(String currency) {
  if (!_currencyCode.hasMatch(currency)) {
    throw ArgumentError.value(currency, 'currency', 'not an ISO 4217 code');
  }
  return _minorUnits[currency] ?? 2;
}

/// Formats minor units as a plain decimal string: 1234 USD -> "12.34".
/// No symbol or grouping; that is added by the display layer.
String formatMinor(int minor, String currency) {
  final exp = currencyExponent(currency);
  final negative = minor < 0;
  final digits = minor.abs().toString();
  final sign = negative ? '-' : '';
  if (exp == 0) return '$sign$digits';
  final padded = digits.padLeft(exp + 1, '0');
  final cut = padded.length - exp;
  return '$sign${padded.substring(0, cut)}.${padded.substring(cut)}';
}

/// Formats an amount with an explicit sign, as the design requires that
/// income and expense are never shown by colour alone: "+12.34" / "−12.34".
/// Uses the true minus sign (U+2212) so it is as wide as the plus sign.
String formatSigned(int minor, String currency) {
  final plain = formatMinor(minor.abs(), currency);
  if (minor > 0) return '+$plain';
  if (minor < 0) return '−$plain';
  return plain;
}

/// Why a typed amount was not accepted.
enum AmountError { empty, invalid, tooPrecise, negative, tooLarge }

/// Largest amount accepted (same limit as the server: 10^15 minor units).
const maxAmountMinor = 1000000000000000;

/// Parses what the user typed ("12.5", "12,50", "1500") into minor units.
/// Either "." or "," may be the decimal separator. Grouping separators are
/// not allowed, so "1,000" is read as 1.000 and "1,000.50" is invalid.
/// More decimals than the currency has is an error, never rounded.
({int? minor, AmountError? error}) parseAmount(
  String input,
  String currency, {
  bool allowNegative = false,
}) {
  var s = input.trim().replaceAll(' ', '');
  if (s.isEmpty) return (minor: null, error: AmountError.empty);
  var negative = false;
  if (s.startsWith('-') || s.startsWith('−')) {
    if (!allowNegative) return (minor: null, error: AmountError.negative);
    negative = true;
    s = s.substring(1);
  }
  s = s.replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d*)?$|^\.\d+$').hasMatch(s)) {
    return (minor: null, error: AmountError.invalid);
  }
  final exp = currencyExponent(currency);
  final parts = s.split('.');
  final intPart = parts[0].isEmpty ? '0' : parts[0];
  final frac = parts.length > 1 ? parts[1] : '';
  if (frac.length > exp) return (minor: null, error: AmountError.tooPrecise);
  final digits = intPart + frac.padRight(exp, '0');
  if (digits.replaceFirst(RegExp('^0+'), '').length > 16) {
    return (minor: null, error: AmountError.tooLarge);
  }
  final value = int.parse(digits);
  if (value > maxAmountMinor) return (minor: null, error: AmountError.tooLarge);
  return (minor: negative ? -value : value, error: null);
}

/// A short message for [error], for form fields.
String amountErrorText(AmountError error, String currency) => switch (error) {
  AmountError.empty => 'Enter an amount',
  AmountError.invalid => 'Use digits and one decimal point, like 12.50',
  AmountError.tooPrecise =>
    currencyExponent(currency) == 0
        ? '$currency has no decimals'
        : '$currency has ${currencyExponent(currency)} decimals at most',
  AmountError.negative => 'Enter a positive amount',
  AmountError.tooLarge => 'That amount is too large',
};

/// Reads an exchange rate the user typed ("1.0989", "117,5"): a positive
/// decimal with at most 10 decimals and 10 digits before the point (what
/// the server stores). Returns it in plain form, or null if not valid.
String? parseRate(String input) {
  var s = input.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d{1,10}(\.\d{1,10})?$').hasMatch(s)) return null;
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  s = s.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  if (RegExp(r'^0(\.0*)?$').hasMatch(s)) return null; // zero
  return s;
}

/// Converts [amountMinor] of [from] into minor units of [to] at [rate]
/// (how much `to` one `from` buys, a decimal string). Exact integer maths;
/// halves round away from zero, like the server.
int convertMinor(int amountMinor, String from, String to, String rate) {
  final parts = rate.split('.');
  final decimals = parts.length == 2 ? parts[1].length : 0;
  final rateNum = BigInt.parse(parts.join());
  final shift = currencyExponent(to) - currencyExponent(from) - decimals;
  var num = BigInt.from(amountMinor) * rateNum;
  var den = BigInt.one;
  if (shift >= 0) {
    num *= BigInt.from(10).pow(shift);
  } else {
    den = BigInt.from(10).pow(-shift);
  }
  final neg = num.isNegative;
  final abs = num.abs();
  var q = abs ~/ den;
  if ((abs % den) * BigInt.two >= den) q += BigInt.one;
  return (neg ? -q : q).toInt();
}

/// 1 / [rate], rounded to 10 decimals (halves away from zero): turns
/// "1 USD = 0.91 EUR" into "1 EUR = 1.0989010989 USD".
String invertRate(String rate) {
  final parts = rate.split('.');
  final decimals = parts.length == 2 ? parts[1].length : 0;
  final den = BigInt.parse(parts.join());
  // 10^(decimals + 10) / den, rounded.
  final num = BigInt.from(10).pow(decimals + 10);
  var q = num ~/ den;
  if ((num % den) * BigInt.two >= den) q += BigInt.one;
  var s = q.toString().padLeft(11, '0');
  s = '${s.substring(0, s.length - 10)}.${s.substring(s.length - 10)}';
  s = s.replaceFirst(RegExp(r'0+$'), '');
  return s.endsWith('.') ? s.substring(0, s.length - 1) : s;
}
