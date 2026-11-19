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

  group('parseAmount', () {
    final ok = <(String, String, int)>[
      ('12.34', 'USD', 1234),
      ('12.5', 'USD', 1250),
      ('12,50', 'EUR', 1250),
      ('7', 'USD', 700),
      ('.5', 'USD', 50),
      ('12.', 'USD', 1200),
      (' 1 500 ', 'JPY', 1500),
      ('1.234', 'KWD', 1234),
      ('0', 'USD', 0),
    ];
    for (final (input, cur, want) in ok) {
      test('"$input" $cur -> $want', () {
        expect(parseAmount(input, cur), (minor: want, error: null));
      });
    }
    final bad = <(String, String, AmountError)>[
      ('', 'USD', AmountError.empty),
      ('abc', 'USD', AmountError.invalid),
      ('1,000.50', 'USD', AmountError.invalid),
      ('1.2.3', 'USD', AmountError.invalid),
      ('12.345', 'USD', AmountError.tooPrecise),
      ('1.5', 'JPY', AmountError.tooPrecise),
      ('-5', 'USD', AmountError.negative),
      ('99999999999999999', 'USD', AmountError.tooLarge),
    ];
    for (final (input, cur, want) in bad) {
      test('"$input" $cur -> $want', () {
        expect(parseAmount(input, cur).error, want);
      });
    }
    test('negative allowed for opening balances', () {
      expect(parseAmount('-20.5', 'USD', allowNegative: true).minor, -2050);
      expect(parseAmount('\u221220', 'USD', allowNegative: true).minor, -2000);
    });
    test('error texts mention the currency rule', () {
      expect(
        amountErrorText(AmountError.tooPrecise, 'JPY'),
        'JPY has no decimals',
      );
      expect(
        amountErrorText(AmountError.tooPrecise, 'USD'),
        contains('2 decimals'),
      );
    });
    test('round trip with formatMinor', () {
      for (final v in [0, 5, 99, 1234, 100000]) {
        expect(parseAmount(formatMinor(v, 'USD'), 'USD').minor, v);
      }
    });
  });

  group('exchange rates', () {
    test('parseRate accepts plain positive decimals', () {
      expect(parseRate(' 1.0989 '), '1.0989');
      expect(parseRate('117,50'), '117.5');
      expect(parseRate('007'), '7');
      expect(parseRate('0.0000000001'), '0.0000000001');
      for (final bad in [
        '',
        '0',
        '0.00',
        '-1',
        '1e5',
        '1.',
        '.5',
        'abc',
        '1.00000000001',
        '12345678901',
      ]) {
        expect(parseRate(bad), isNull, reason: bad);
      }
    });

    test('multiplyRates', () {
      expect(multiplyRates('1.17', '160.5'), '187.785');
      expect(multiplyRates('2', '3'), '6');
      expect(multiplyRates('0.0000123', '3'), '0.0000369');
      // Rounded to 10 decimals, halves away from zero.
      expect(multiplyRates('1.0989010989', '0.91'), '1');
    });

    test('invertRate', () {
      expect(invertRate('0.91'), '1.0989010989');
      expect(invertRate('1.25'), '0.8');
      expect(invertRate('2'), '0.5');
      expect(invertRate('150.5'), '0.0066445183');
    });

    test('convertMinor matches the server', () {
      // The same cases as backend/internal/fx/rates_test.go.
      expect(convertMinor(1000, 'USD', 'EUR', '0.91'), 910);
      expect(convertMinor(1234, 'USD', 'JPY', '150.5'), 1857);
      expect(convertMinor(1857, 'JPY', 'USD', '0.0066445'), 1234);
      expect(convertMinor(1000, 'USD', 'KWD', '0.3075'), 3075);
      expect(convertMinor(5, 'USD', 'EUR', '0.5'), 3);
      expect(convertMinor(-5, 'USD', 'EUR', '0.5'), -3);
      expect(convertMinor(999999, 'IDR', 'USD', '0.0000613'), 61);
      expect(convertMinor(100, 'EUR', 'EUR', '1'), 100);
    });
  });
}
