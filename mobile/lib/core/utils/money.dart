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
