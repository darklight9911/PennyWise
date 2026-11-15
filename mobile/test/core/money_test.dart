import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/core/utils/money.dart';

void main() {
  group('formatMinor', () {
    final cases = <(int, String, String)>[
      (1234, 'USD', '12.34'),
      (5, 'USD', '0.05'),
      (-5, 'USD', '-0.05'),
      (0, 'USD', '0.00'),
      (1500, 'JPY', '1500'),
      (1234, 'KWD', '1.234'),
      (7, 'KWD', '0.007'),
    ];
    for (final (minor, cur, want) in cases) {
      test('$minor $cur -> $want', () {
        expect(formatMinor(minor, cur), want);
      });
    }
  });

  test('formatSigned adds + or true minus sign', () {
    expect(formatSigned(1234, 'USD'), '+12.34');
    expect(formatSigned(-1234, 'USD'), '−12.34');
    expect(formatSigned(0, 'USD'), '0.00');
  });

  test('rejects invalid currency codes', () {
    expect(() => currencyExponent('usd'), throwsArgumentError);
    expect(() => currencyExponent('US'), throwsArgumentError);
  });
}
