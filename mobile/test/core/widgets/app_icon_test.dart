import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart' show HugeIcon;
import 'package:material_ui/material_ui.dart';
import 'package:pennywise/core/widgets/app_icon.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('follows the icon theme size, like Flutter Icon', (tester) async {
    await tester.pumpWidget(
      _host(
        const IconTheme(
          data: IconThemeData(size: 18),
          child: AppIcon(HugeIcons.strokeRoundedHome01),
        ),
      ),
    );
    expect(tester.getSize(find.byType(HugeIcon)), const Size(18, 18));
  });

  testWidgets('an explicit size wins over the theme', (tester) async {
    await tester.pumpWidget(
      _host(
        const IconTheme(
          data: IconThemeData(size: 18),
          child: AppIcon(HugeIcons.strokeRoundedHome01, size: 48),
        ),
      ),
    );
    expect(tester.getSize(find.byType(HugeIcon)), const Size(48, 48));
  });

  testWidgets('has a label only when given one', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(HugeIcons.strokeRoundedHome01, semanticLabel: 'Home'),
            AppIcon(HugeIcons.strokeRoundedSettings01),
          ],
        ),
      ),
    );
    expect(find.bySemanticsLabel('Home'), findsOneWidget);
    semantics.dispose();
  });
}
