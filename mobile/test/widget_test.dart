import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pennywise/app.dart';
import 'package:pennywise/core/theme/app_colors.dart';

Future<void> pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(const ProviderScope(child: PennyWiseApp()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('starts on the dashboard with the palette applied', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('Total balance'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
    final context = tester.element(find.byWidget(scaffold));
    expect(Theme.of(context).colorScheme.primary, AppColors.primary);
    expect(Theme.of(context).scaffoldBackgroundColor, AppColors.canvas);
  });

  testWidgets('bottom navigation switches tabs', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Transactions'));
    await tester.pumpAndSettle();
    expect(find.text('No transactions yet'), findsOneWidget);

    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing to show yet'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Base currency'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Total balance'), findsOneWidget);
  });
}
