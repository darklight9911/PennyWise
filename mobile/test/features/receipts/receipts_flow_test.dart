import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pennywise/app.dart';
import 'package:pennywise/features/ledger/application/ledger_providers.dart';
import 'package:pennywise/features/receipts/data/receipt_picker.dart';

import '../../support/test_app.dart';
import '../../widget_test.dart' show field, finish, logIn, pumpApp, pw, tapOn;
import '../dashboard/dashboard_flow_test.dart' show untilDone;

// A real 1x1 PNG, so the image widgets can decode it.
final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

void main() {
  late TestHarness h;
  setUp(() {
    h = TestHarness();
    h.backend.seedUser('ann@example.com', pw);
  });

  testWidgets('attach a photo to a new expense, then view and delete it', (
    tester,
  ) async {
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PennyWiseApp)),
    );
    final store = await container.read(ledgerStoreProvider.future);
    await untilDone(tester, () async {
      await store.createAccount(name: 'Cash', type: 'cash', currency: 'USD');
      await store.createCategory(name: 'Lunch', kind: 'expense');
    });

    await tapOn(tester, find.byTooltip('Add transaction'));
    await tester.enterText(field('Amount'), '12');
    await tapOn(tester, find.text('Lunch'));
    final add = find.text('Add photo');
    await tester.scrollUntilVisible(
      add,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Receipts (0/3)'), findsOneWidget);

    // Cancelled: nothing added.
    h.nextPhoto = null;
    await tapOn(tester, add);
    await tapOn(tester, find.text('Take a photo'));
    expect(find.text('Receipts (0/3)'), findsOneWidget);

    h.nextPhoto = (bytes: png, contentType: 'image/png');
    await tapOn(tester, add);
    await tapOn(tester, find.text('Choose from gallery'));
    expect(h.pickedFrom, [PhotoSource.camera, PhotoSource.gallery]);
    expect(find.text('Receipts (1/3)'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Save'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tapOn(tester, find.widgetWithText(FilledButton, 'Save'));

    final receipts = (await tester.runAsync(
      () => store.db.select(store.db.receipts).get(),
    ))!;
    expect(receipts, hasLength(1));
    expect(h.receiptFiles.files.values.single, png);

    // Saving synced the transaction, then uploaded the photo.
    await untilDone(tester, () async {});
    final saved = (await tester.runAsync(
      () => store.db.select(store.db.receipts).get(),
    ))!.single;
    expect(saved.status, 'uploaded');
    expect(h.backend.bucket[saved.id], png);

    // Open it again from the list and delete the photo.
    await tapOn(tester, find.text('Lunch').first);
    final thumb = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'Receipt photo',
    );
    await tester.scrollUntilVisible(
      thumb,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tapOn(tester, thumb);
    expect(find.text('Receipt'), findsOneWidget);
    await tapOn(tester, find.byTooltip('Delete photo'));
    await tapOn(tester, find.widgetWithText(FilledButton, 'Delete'));
    expect(find.text('Receipts (0/3)'), findsOneWidget);
    await untilDone(tester, () async {});
    expect(h.backend.bucket, isEmpty);
    expect(h.receiptFiles.files, isEmpty);
    await finish(tester);
  });
}
