import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pennywise/features/ledger/application/ledger_providers.dart';

import '../../support/test_app.dart';
import '../../widget_test.dart' show finish, logIn, pumpApp, pw, settle, tapOn;

void main() {
  late TestHarness h;
  setUp(() {
    h = TestHarness();
    h.backend.seedUser('ann@example.com', pw);
  });

  Future<void> openExport(WidgetTester tester) async {
    await tapOn(tester, find.text('Reports'));
    await tapOn(tester, find.byTooltip('Export'));
    expect(find.text('Make file'), findsOneWidget);
  }

  /// Adds one expense through the store the app uses.
  Future<void> addExpense(WidgetTester tester, String note) async {
    final c = ProviderScope.containerOf(
      tester.element(find.byType(NavigationBar)),
    );
    final store = await c.read(ledgerStoreProvider.future);
    final usd = await store.createAccount(
      name: 'Wallet',
      type: 'cash',
      currency: 'USD',
    );
    await store.createTransaction(
      kind: 'expense',
      accountId: usd.id,
      amountMinor: 1234,
      currency: 'USD',
      occurredAt: DateTime.now(),
      note: note,
      baseCurrency: 'USD',
    );
  }

  /// Taps "Make file" and lets the real work (fonts, PDF) finish. The
  /// progress bar animates while busy, so time is moved by hand.
  Future<void> makeFile(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Make file'));
    for (var i = 0; i < 60 && h.shared.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('without an account and offline: a CSV is made on the phone', (
    tester,
  ) async {
    h.backend.offline = true;
    h.store.guestProfile = {
      'name': '',
      'base_currency': 'USD',
      'timezone': 'UTC',
      'locale': 'en',
    };
    await pumpApp(tester, h);
    await addExpense(tester, 'Lunch');
    await settle(tester);
    await openExport(tester);
    await tapOn(tester, find.text('CSV spreadsheet'));
    await makeFile(tester);

    final now = DateTime.now();
    final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final file = h.shared.single;
    expect(file.name, startsWith('pennywise-$month-01-to-$month-'));
    expect(file.mime, 'text/csv');
    expect(file.bytes.take(3), [0xEF, 0xBB, 0xBF], reason: 'UTF-8 BOM');
    final text = utf8.decode(file.bytes); // drops the BOM
    expect(text, startsWith('date,type,account,category,note,amount'));
    expect(text, contains(',expense,Wallet,,Lunch,-12.34,USD,-12.34,1,auto,'));
    expect(find.text(file.name), findsOneWidget);
    await finish(tester);
  });

  testWidgets('signed in: a PDF statement is made on the phone too', (
    tester,
  ) async {
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);
    await openExport(tester);
    await makeFile(tester);
    final file = h.shared.single;
    expect(file.mime, 'application/pdf');
    expect(ascii.decode(file.bytes.take(5).toList()), '%PDF-');
    expect(h.backend.callCount('/v1/exports'), 0, reason: 'no server job');
    await finish(tester);
  });
}
