import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pennywise/core/widgets/app_icon.dart';
import 'package:pennywise/core/widgets/empty_state.dart';
import 'package:pennywise/core/widgets/panda_mascot.dart';

Widget _host(Widget child) => ProviderScope(
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  test('mood order matches the Rive file', () {
    // rive/tool/gen_penny.py: 0 idle ... 6 sleeping
    expect(PandaMood.values.map((m) => m.name), [
      'idle',
      'wave',
      'happy',
      'celebrate',
      'worried',
      'thinking',
      'sleeping',
    ]);
  });

  testWidgets('without the Rive runtime Penny keeps her space', (tester) async {
    await tester.pumpWidget(
      _host(const PandaMascot(mood: PandaMood.happy, size: 90)),
    );
    expect(tester.getSize(find.byType(PandaMascot)), const Size(90, 90));
  });

  testWidgets('Penny is labelled for screen readers when asked', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        const PandaMascot(
          mood: PandaMood.wave,
          semanticLabel: 'Penny the panda waving',
        ),
      ),
    );
    expect(find.bySemanticsLabel('Penny the panda waving'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('empty state falls back to its icon', (tester) async {
    await tester.pumpWidget(
      _host(
        const EmptyState(
          mascot: PandaMood.sleeping,
          icon: HugeIcons.strokeRoundedInvoice01,
          title: 'No transactions yet',
          message: 'Add one.',
        ),
      ),
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is AppIcon && w.icon == HugeIcons.strokeRoundedInvoice01,
      ),
      findsOneWidget,
    );
    expect(find.text('No transactions yet'), findsOneWidget);
  });

  testWidgets('PandaMascot accepts giggleTrigger updates cleanly', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const PandaMascot(mood: PandaMood.sleeping, giggleTrigger: 0)),
    );
    await tester.pumpWidget(
      _host(const PandaMascot(mood: PandaMood.wave, giggleTrigger: 1)),
    );
    expect(
      tester.widget<PandaMascot>(find.byType(PandaMascot)).giggleTrigger,
      1,
    );
  });

  testWidgets('empty state renders optional action widget', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _host(
        EmptyState(
          mascot: PandaMood.thinking,
          icon: HugeIcons.strokeRoundedPieChart,
          title: 'Nothing to show yet',
          message: 'Add an entry.',
          action: FilledButton(
            onPressed: () => tapped = true,
            child: const Text('Add transaction'),
          ),
        ),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add transaction'));
    expect(tapped, isTrue);
  });
}
