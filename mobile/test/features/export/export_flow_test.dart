import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/test_app.dart';
import '../../widget_test.dart' show finish, logIn, pumpApp, pw, settle, tapOn;

void main() {
  late TestHarness h;
  setUp(() {
    h = TestHarness();
    h.backend.seedUser('ann@example.com', pw);
  });

  Future<void> openExport(WidgetTester tester) async {
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);
    await tapOn(tester, find.text('Reports'));
    await tapOn(tester, find.byTooltip('Export'));
    expect(find.text('Make file'), findsOneWidget);
  }

  Future<void> waitForPolls(WidgetTester tester) async {
    // The progress bar animates forever: pump by hand.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await settle(tester);
  }

  testWidgets('makes a CSV for last year and opens it', (tester) async {
    await openExport(tester);
    await tapOn(tester, find.text('CSV spreadsheet'));
    await tapOn(tester, find.text('Last year'));
    await tester.tap(find.widgetWithText(FilledButton, 'Make file'));
    await tester.pump();
    expect(find.text('Making your file…'), findsOneWidget);
    await waitForPolls(tester);

    final year = DateTime.now().year - 1;
    final name = 'pennywise-$year-01-01-to-$year-12-31.csv';
    expect(find.text(name), findsOneWidget);
    final e = h.backend.exports.values.single;
    expect((e.format, e.from, e.to), ('csv', '$year-01-01', '$year-12-31'));

    await tapOn(tester, find.widgetWithText(FilledButton, 'Open'));
    expect(h.opened.single.host, 'files.example.com');
    await finish(tester);
  });

  testWidgets('says so when the server has no export', (tester) async {
    h.backend.exportsError = 'exports_unavailable';
    await openExport(tester);
    await tapOn(tester, find.widgetWithText(FilledButton, 'Make file'));
    expect(
      find.text('Export is not available on this server yet.'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Make file'),
      findsOneWidget,
      reason: 'can try again',
    );
    await finish(tester);
  });
}
