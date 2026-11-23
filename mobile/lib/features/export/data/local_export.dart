import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/money.dart';

/// Export files are made on the phone, from the local database, so they
/// work offline and without an account. The CSV has the same columns as
/// the server's export.

/// One transaction with its names, as exported.
class ExportRow {
  const ExportRow({
    required this.date,
    required this.kind,
    required this.account,
    required this.category,
    required this.note,
    required this.amountMinor,
    required this.currency,
    this.baseMinor,
    this.rate,
    this.rateSource,
    this.toAccount,
    this.toCurrency,
    this.toAmount,
  });

  final String date; // YYYY-MM-DD
  final String kind;
  final String account;
  final String category; // "Food › Cafe" for sub-categories
  final String note;
  final int amountMinor;
  final String currency;
  final int? baseMinor;
  final String? rate;
  final String? rateSource;
  final String? toAccount;
  final String? toCurrency;
  final int? toAmount;
}

/// Transactions from [from] to [to] (YYYY-MM-DD, both included), oldest
/// first, deleted ones left out.
Future<List<ExportRow>> loadExportRows(
  AppDatabase db, {
  required String from,
  required String to,
}) async {
  final accounts = {
    for (final a in await db.select(db.accounts).get()) a.id: a,
  };
  final cats = {for (final c in await db.select(db.categories).get()) c.id: c};
  String categoryName(String? id) {
    final c = cats[id];
    if (c == null) return '';
    final parent = cats[c.parentId];
    return parent == null ? c.name : '${parent.name} › ${c.name}';
  }

  final txs =
      await (db.select(db.transactions)
            ..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.localDate.isBiggerOrEqualValue(from) &
                  t.localDate.isSmallerOrEqualValue(to),
            )
            ..orderBy([
              (t) => OrderingTerm(expression: t.localDate),
              (t) => OrderingTerm(expression: t.occurredAt),
              (t) => OrderingTerm(expression: t.id),
            ]))
          .get();
  return [
    for (final t in txs)
      ExportRow(
        date: t.localDate,
        kind: t.kind,
        account: accounts[t.accountId]?.name ?? '',
        category: categoryName(t.categoryId),
        note: t.note,
        amountMinor: t.amountMinor,
        currency: t.currency,
        baseMinor: t.amountBaseMinor,
        rate: t.fxRateToBase,
        rateSource: t.fxRateSource,
        toAccount: accounts[t.transferAccountId]?.name,
        toCurrency: accounts[t.transferAccountId]?.currency,
        toAmount: t.transferAmountMinor,
      ),
  ];
}

String exportFileName(String format, String from, String to) =>
    'pennywise-$from-to-$to.$format';

/// Money in (income, loan money in) is positive; spending, transfers out
/// and loan money out are negative.
int _signed(String kind, int v) =>
    kind == 'income' || kind == 'loan_in' ? v : -v;

/// Stops spreadsheet formula injection: a note like "=HYPERLINK(...)"
/// would otherwise run when the file is opened.
String _safeCell(String s) =>
    s.isNotEmpty && '=+-@\t\r'.contains(s[0]) ? "'$s" : s;

String _csvField(String s) =>
    RegExp(r'[",\r\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;

/// One line per transaction. Amounts are plain decimals (12.34) so
/// spreadsheets read them as numbers. Starts with a BOM so Excel reads
/// the file as UTF-8.
String buildCsv(List<ExportRow> rows, String base) {
  final b = base.toLowerCase();
  final lines = <List<String>>[
    [
      'date', 'type', 'account', 'category', 'note', 'amount', 'currency', //
      'amount_$b', 'rate_to_$b', 'rate_source', 'to_account', 'to_amount',
      'to_currency',
    ],
    for (final x in rows)
      [
        x.date,
        x.kind,
        _safeCell(x.account),
        _safeCell(x.category),
        _safeCell(x.note),
        formatMinor(_signed(x.kind, x.amountMinor), x.currency),
        x.currency,
        x.baseMinor == null
            ? ''
            : formatMinor(_signed(x.kind, x.baseMinor!), base),
        x.rate ?? '',
        x.rateSource ?? '',
        if (x.toAccount != null &&
            x.toAmount != null &&
            x.toCurrency != null) ...[
          _safeCell(x.toAccount!),
          formatMinor(x.toAmount!, x.toCurrency!),
          x.toCurrency!,
        ] else ...[
          '',
          '',
          '',
        ],
      ],
  ];
  return '\uFEFF${lines.map((l) => l.map(_csvField).join(',')).join('\r\n')}\r\n';
}

/// A printable statement: totals, spending by category and every
/// transaction, in the main currency [base].
Future<Uint8List> buildPdf({
  required List<ExportRow> rows,
  required String base,
  required String from,
  required String to,
  required pw.Font regular,
  required pw.Font bold,
}) async {
  var income = 0, spending = 0, noRate = 0;
  final byCategory = <String, int>{};
  for (final x in rows) {
    // Transfers and loans move money but are not income or spending.
    if (x.kind != 'income' && x.kind != 'expense') continue;
    final v = x.baseMinor;
    if (v == null) {
      noRate++;
      continue;
    }
    if (x.kind == 'income') {
      income += v;
    } else {
      spending += v;
      final name = x.category.isEmpty ? 'No category' : x.category;
      byCategory[name] = (byCategory[name] ?? 0) + v;
    }
  }
  final top = byCategory.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  const primary = PdfColor.fromInt(0xFF2C706E);
  const incomeColor = PdfColor.fromInt(0xFF2F7734);
  const expenseColor = PdfColor.fromInt(0xFFBA1120);
  const muted = PdfColor.fromInt(0xFF5C6B69);
  const shade = PdfColor.fromInt(0xFFEEE9E0);
  String money(int v) => '${formatMinor(v, base)} $base';
  pw.TextStyle st(double size, {bool strong = false, PdfColor? color}) =>
      pw.TextStyle(
        font: strong ? bold : regular,
        fontSize: size,
        color: color ?? PdfColors.black,
      );

  pw.Widget figure(String label, String value, PdfColor color) => pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: const pw.BoxDecoration(color: shade),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: st(9, color: muted)),
          pw.SizedBox(height: 4),
          pw.Text(value, style: st(13, strong: true, color: color)),
        ],
      ),
    ),
  );

  final doc = pw.Document(title: 'pennyWise $from to $to');
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 48),
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('pennyWise · $from – $to', style: st(8, color: muted)),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: st(8, color: muted),
          ),
        ],
      ),
      build: (context) => [
        pw.Text('Statement', style: st(20, strong: true, color: primary)),
        pw.SizedBox(height: 4),
        pw.Text('$from to $to · amounts in $base', style: st(10, color: muted)),
        pw.SizedBox(height: 16),
        pw.Row(
          children: [
            figure('Income', money(income), incomeColor),
            pw.SizedBox(width: 8),
            figure('Spending', money(spending), expenseColor),
            pw.SizedBox(width: 8),
            figure('Net', money(income - spending), PdfColors.black),
          ],
        ),
        if (noRate > 0) ...[
          pw.SizedBox(height: 6),
          pw.Text(
            '$noRate transaction(s) in other currencies have no $base amount '
            'yet and are not in these totals.',
            style: st(8.5, color: muted),
          ),
        ],
        if (top.isNotEmpty) ...[
          pw.SizedBox(height: 18),
          pw.Text('Spending by category', style: st(11, strong: true)),
          pw.SizedBox(height: 6),
          for (final c in top.take(8))
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Row(
                children: [
                  pw.SizedBox(
                    width: 140,
                    child: pw.Text(c.key, style: st(9.5), maxLines: 1),
                  ),
                  pw.Expanded(
                    child: _bar(
                      spending == 0 ? 0 : (c.value * 1000 / spending).round(),
                      primary,
                      shade,
                    ),
                  ),
                  pw.SizedBox(
                    width: 110,
                    child: pw.Text(
                      money(c.value),
                      style: st(9.5),
                      textAlign: pw.TextAlign.right,
                    ),
                  ),
                  pw.SizedBox(
                    width: 36,
                    child: pw.Text(
                      '${spending == 0 ? 0 : (c.value * 100 / spending).round()}%',
                      style: st(9.5, color: muted),
                      textAlign: pw.TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
        ],
        pw.SizedBox(height: 18),
        pw.Text('Transactions (${rows.length})', style: st(11, strong: true)),
        pw.SizedBox(height: 6),
        if (rows.isEmpty)
          pw.Text(
            'No transactions in this period.',
            style: st(9.5, color: muted),
          )
        else
          pw.TableHelper.fromTextArray(
            headers: ['Date', 'Category', 'Account', 'Note', 'Amount', base],
            data: [
              for (final x in rows)
                [
                  x.date,
                  x.kind == 'transfer' && x.toAccount != null
                      ? 'Transfer to ${x.toAccount}'
                      : x.category,
                  x.account,
                  x.note,
                  '${formatMinor(_signed(x.kind, x.amountMinor), x.currency)} ${x.currency}',
                  x.baseMinor == null
                      ? 'no rate'
                      : formatMinor(_signed(x.kind, x.baseMinor!), base),
                ],
            ],
            headerStyle: st(8.5, strong: true, color: muted),
            headerDecoration: const pw.BoxDecoration(color: shade),
            cellStyle: st(8.5),
            cellAlignments: {
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
            },
            columnWidths: {
              0: const pw.FixedColumnWidth(62),
              1: const pw.FlexColumnWidth(2),
              2: const pw.FlexColumnWidth(1.5),
              3: const pw.FlexColumnWidth(2),
              4: const pw.FixedColumnWidth(84),
              5: const pw.FixedColumnWidth(64),
            },
            border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(color: shade, width: 0.5),
            ),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 4,
            ),
          ),
      ],
    ),
  );
  return doc.save();
}

/// A bar filled [perMille]/1000 of its width.
pw.Widget _bar(int perMille, PdfColor fill, PdfColor rest) => pw.Row(
  children: [
    if (perMille > 0)
      pw.Expanded(
        flex: perMille,
        child: pw.Container(height: 8, color: fill),
      ),
    if (perMille < 1000)
      pw.Expanded(
        flex: 1000 - perMille,
        child: pw.Container(height: 8, color: rest),
      ),
  ],
);

/// The bundled Onest font, so names and notes print as on screen.
Future<({pw.Font regular, pw.Font bold})> loadPdfFonts() async => (
  regular: pw.Font.ttf(
    await rootBundle.load('assets/fonts/onest/Onest-Regular.ttf'),
  ),
  bold: pw.Font.ttf(await rootBundle.load('assets/fonts/onest/Onest-Bold.ttf')),
);

/// Hands a finished file to the phone's share sheet (save to Files or
/// Drive, email, chat...). Tests replace it.
typedef FileSharer = Future<void> Function(
  Uint8List bytes,
  String fileName,
  String mimeType,
);

final fileSharerProvider = Provider<FileSharer>(
  (ref) => (bytes, fileName, mimeType) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, name: fileName, mimeType: mimeType)],
        fileNameOverrides: [fileName],
      ),
    );
  },
);
