import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/test_app.dart';
import '../../widget_test.dart' show field, finish, logIn, pumpApp, pw, tapOn;

void main() {
  late TestHarness h;
  setUp(() {
    h = TestHarness();
    h.backend.seedUser('ann@example.com', pw);
  });

  Future<void> openDialog(WidgetTester tester) async {
    await tapOn(tester, find.text('Settings'));
    final delete = find.text('Delete account');
    await tester.scrollUntilVisible(
      delete,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tapOn(tester, delete);
    expect(find.text('Delete your account?'), findsOneWidget);
  }

  testWidgets('a wrong password keeps the account', (tester) async {
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);
    await openDialog(tester);

    final button = find.widgetWithText(FilledButton, 'Delete account');
    await tapOn(tester, button);
    expect(find.text('Type your password to confirm'), findsOneWidget);

    await tester.enterText(field('Password'), 'not it');
    await tapOn(tester, button);
    expect(find.text('That password is wrong'), findsOneWidget);
    expect(h.backend.users.containsKey('ann@example.com'), isTrue);

    await tapOn(tester, find.text('Cancel'));
    expect(find.text('Delete your account?'), findsNothing);
    await finish(tester);
  });

  testWidgets('deleting logs out and removes the account', (tester) async {
    await pumpApp(tester, h);
    await logIn(tester, 'ann@example.com', pw);
    await openDialog(tester);

    await tester.enterText(field('Password'), pw);
    await tapOn(tester, find.widgetWithText(FilledButton, 'Delete account'));

    expect(find.text('Delete your account?'), findsNothing);
    expect(h.store.guestProfile, isNotNull, reason: 'goes on without one');
    expect(h.backend.users.containsKey('ann@example.com'), isFalse);
    expect(h.store.tokens, isNull);
    expect(h.backend.callCount('DELETE /v1/me'), 1);
    await finish(tester);
  });
}
