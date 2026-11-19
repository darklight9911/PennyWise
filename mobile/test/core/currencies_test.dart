import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/core/device/device_profile.dart';
import 'package:pennywise/core/utils/currencies.dart';
import 'package:pennywise/core/utils/money.dart';

void main() {
  group('allCurrencies catalog', () {
    test('contains >= 150 unique valid currencies sorted alphabetically', () {
      expect(allCurrencies.length, greaterThanOrEqualTo(150));

      final isoCode = RegExp(r'^[A-Z]{3}$');
      final codes = <String>[];
      for (final c in allCurrencies) {
        expect(isoCode.hasMatch(c.code), isTrue, reason: c.code);
        expect(c.name.trim(), isNotEmpty, reason: c.code);
        expect(c.symbol.trim(), isNotEmpty, reason: c.code);
        codes.add(c.code);
      }

      expect(codes.toSet().length, codes.length, reason: 'no duplicate codes');
      final sorted = [...codes]..sort();
      expect(codes, sorted);
    });

    test('covers supportedCurrencies, region defaults, decimal rules and ECB rates', () {
      final byCode = {for (final c in allCurrencies) c.code: c};

      for (final code in supportedCurrencies) {
        expect(byCode.containsKey(code), isTrue, reason: code);
      }

      for (final country in [
        'US', 'GB', 'DE', 'BD', 'IN', 'PK', 'NP', 'LK', 'JP', 'CN', //
        'KR', 'CA', 'AU', 'NZ', 'SG', 'MY', 'ID', 'TH', 'PH', 'AE',
        'SA', 'TR', 'CH', 'SE', 'NO', 'DK', 'PL', 'BR', 'MX', 'ZA',
        'NG', 'EG', 'KE',
      ]) {
        expect(
          byCode.containsKey(currencyForRegion(country)),
          isTrue,
          reason: country,
        );
      }

      const zeroAndThreeDecimalCirculating = [
        'BIF', 'CLP', 'DJF', 'GNF', 'ISK', 'JPY', 'KMF', 'KRW', //
        'PYG', 'RWF', 'UGX', 'VND', 'VUV', 'XAF', 'XOF', 'XPF',
        'BHD', 'IQD', 'JOD', 'KWD', 'LYD', 'OMR', 'TND',
      ];
      for (final code in zeroAndThreeDecimalCirculating) {
        expect(byCode.containsKey(code), isTrue, reason: code);
        // Also sanity-check money.dart agrees on its exponent.
        expect(currencyExponent(code), isNot(2), reason: code);
      }

      const ecbCurrencies = [
        'AUD', 'BGN', 'BRL', 'CAD', 'CHF', 'CNY', 'CZK', 'DKK', //
        'EUR', 'GBP', 'HKD', 'HUF', 'IDR', 'ILS', 'INR', 'ISK',
        'JPY', 'KRW', 'MXN', 'MYR', 'NOK', 'NZD', 'PHP', 'PLN',
        'RON', 'SEK', 'SGD', 'THB', 'TRY', 'USD', 'ZAR',
      ];
      final autoCodes = {
        for (final c in allCurrencies)
          if (c.autoRates) c.code,
      };
      expect(autoCodes, ecbCurrencies.toSet());
    });
  });

  group('currencyInfo & currencyLabel', () {
    test('resolves case-insensitively and falls back safely', () {
      final bdt = currencyInfo(' bdt ');
      expect(bdt.code, 'BDT');
      expect(bdt.symbol, '৳');
      expect(bdt.name, 'Bangladeshi Taka');
      expect(bdt.autoRates, isFalse);

      expect(currencyLabel('bdt'), 'BDT · Bangladeshi Taka');

      final unknown = currencyInfo('xyz');
      expect(unknown.code, 'XYZ');
      expect(unknown.name, 'XYZ');
      expect(unknown.symbol, 'XYZ');
      expect(currencyLabel('xyz'), 'XYZ');
    });
  });

  group('searchCurrencies', () {
    test('ranks exact code, prefix, symbol, name and country keywords', () {
      expect(searchCurrencies('US').first.code, 'USD');

      for (final q in ['taka', 'bangladesh', '৳', 'bdt', ' BDT ']) {
        final results = searchCurrencies(q);
        expect(results, isNotEmpty, reason: q);
        expect(results.first.code, 'BDT', reason: q);
      }

      expect(searchCurrencies('yen').first.code, 'JPY');
      expect(searchCurrencies('japan').first.code, 'JPY');

      expect(searchCurrencies('zzz-none'), isEmpty);
      expect(searchCurrencies('').length, allCurrencies.length);
    });
  });

  group('suggestedCurrencyCodes', () {
    test('preserves priority order and removes duplicates', () {
      expect(
        suggestedCurrencyCodes(
          selected: 'bdt',
          detectedCode: 'BDT',
          accountCodes: ['eur', 'BDT', 'jpy', 'usd'],
          fallbacks: ['USD', 'EUR', 'GBP'],
        ),
        ['BDT', 'EUR', 'JPY', 'USD', 'GBP'],
      );
    });
  });
}
