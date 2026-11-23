import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/features/export/data/local_export.dart';

void main() {
  const lunch = ExportRow(
    date: '2026-11-19',
    kind: 'expense',
    account: 'Wallet',
    category: 'Food › Cafe',
    note: 'Lunch, with "Bo"',
    amountMinor: 1234,
    currency: 'USD',
    baseMinor: 1234,
    rate: '1',
    rateSource: 'auto',
  );

  test('CSV: same columns as the server, signed and quoted', () {
    final csv = buildCsv([lunch], 'USD');
    final lines = csv.split('\r\n');
    expect(
      lines[0],
      '\uFEFFdate,type,account,category,note,amount,currency,amount_usd,'
      'rate_to_usd,rate_source,to_account,to_amount,to_currency',
    );
    expect(
      lines[1],
      '2026-11-19,expense,Wallet,Food › Cafe,"Lunch, with ""Bo""",'
      '-12.34,USD,-12.34,1,auto,,,',
    );
  });

  test('CSV: formulas in names cannot run in a spreadsheet', () {
    const evil = ExportRow(
      date: '2026-11-19',
      kind: 'income',
      account: '=HYPERLINK("x")',
      category: '',
      note: '+1',
      amountMinor: 500,
      currency: 'JPY',
    );
    final line = buildCsv([evil], 'EUR').split('\r\n')[1];
    expect(
      line,
      startsWith('2026-11-19,income,"\'=HYPERLINK(""x"")",,\'+1,500,JPY,,'),
    );
  });

  test('CSV: transfers show where the money went', () {
    const move = ExportRow(
      date: '2026-11-19',
      kind: 'transfer',
      account: 'Bank',
      category: '',
      note: '',
      amountMinor: 10000,
      currency: 'EUR',
      baseMinor: 10000,
      toAccount: 'Savings',
      toCurrency: 'EUR',
      toAmount: 10000,
    );
    final line = buildCsv([move], 'EUR').split('\r\n')[1];
    expect(line, endsWith(',Savings,100.00,EUR'));
    expect(line, contains(',-100.00,EUR,-100.00,'));
  });

  test('CSV: loan money in is positive, loan money out negative', () {
    ExportRow loan(String kind) => ExportRow(
      date: '2026-11-19',
      kind: kind,
      account: 'Cash',
      category: '',
      note: 'Rahim',
      amountMinor: 5000,
      currency: 'USD',
      baseMinor: 5000,
    );
    final lines = buildCsv([
      loan('loan_in'),
      loan('loan_out'),
    ], 'USD').split('\r\n');
    expect(
      lines[1],
      startsWith('2026-11-19,loan_in,Cash,,Rahim,50.00,USD,50.00,'),
    );
    expect(
      lines[2],
      startsWith('2026-11-19,loan_out,Cash,,Rahim,-50.00,USD,-50.00,'),
    );
  });

  test('file names carry the period', () {
    expect(
      exportFileName('pdf', '2026-01-01', '2026-12-31'),
      'pennywise-2026-01-01-to-2026-12-31.pdf',
    );
    expect(utf8.encode(buildCsv(const [], 'USD')).first, 0xEF, reason: 'BOM');
  });
}
