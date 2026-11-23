import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pennywise/app.dart';
import 'package:pennywise/core/database/app_database.dart';
import 'package:pennywise/features/dues/application/due_reminders.dart';
import 'package:pennywise/features/ledger/application/ledger_providers.dart';
import 'package:pennywise/features/ledger/data/ledger_store.dart';

import '../../support/test_app.dart';
import '../../widget_test.dart' show field, finish, pumpApp, settle, tapOn;
import '../dashboard/dashboard_flow_test.dart' show untilDone;

void main() {
  group('planning', () {
    late AppDatabase db;
    late LedgerStore store;
    setUp(() => store = LedgerStore(db = AppDatabase(NativeDatabase.memory())));
    tearDown(() => db.close());

    Future<Due> due({
      String? dueDate,
      int? remind,
      String direction = DueDirection.owedToMe,
    }) => store.createDue(
      direction: direction,
      kind: DueKind.loan,
      person: 'Rahim',
      amountMinor: 30000,
      currency: 'USD',
      startDate: '2026-11-01',
      dueDate: dueDate,
      remindDaysBefore: remind,
    );

    test('one reminder per open due, at 09:00 on the reminder day', () async {
      final a = await due(dueDate: '2026-11-30', remind: 3);
      await due(dueDate: '2026-11-30'); // no reminder
      await due(); // no due date
      await due(dueDate: '2026-11-05', remind: 7); // reminder day already gone
      final b = await due(
        dueDate: '2026-11-20',
        remind: 0,
        direction: DueDirection.iOwe,
      );
      final plan = planDueReminders(
        await store.watchDues().first,
        DateTime(2026, 11, 10, 12),
      );
      expect(plan.map((r) => r.dueId), [b.id, a.id]);
      expect(plan[1].at, DateTime(2026, 11, 27, 9));
      expect(plan[1].title, 'Rahim owes you 300.00 USD');
      expect(plan[1].body, startsWith('Due in 3 days ('));
      expect(plan[0].title, 'You owe Rahim 300.00 USD');
      expect(plan[0].body, startsWith('Due today ('));
      expect(
        plan[1].id,
        reminderIdFor(a.id),
        reason: 'stable, so rescheduling replaces it',
      );
    });

    test(
      'settled dues have no reminder; ids are stable and positive',
      () async {
        final a = await due(dueDate: '2026-11-30', remind: 1);
        await store.forgiveDue(a);
        expect(
          planDueReminders(
            await store.watchDues().first,
            DateTime(2026, 11, 10),
          ),
          isEmpty,
        );
        expect(reminderIdFor('x'), reminderIdFor('x'));
        expect(
          reminderIdFor('0193c0de-0000-7000-8000-000000000001'),
          greaterThan(0),
        );
      },
    );
  });

  testWidgets(
    'saving a reminder schedules it; settling removes it; tapping opens the due',
    (tester) async {
      final h = TestHarness()
        ..store.guestProfile = {
          'name': '',
          'base_currency': 'USD',
          'timezone': 'UTC',
          'locale': 'en',
        };
      h.reminderNow = DateTime.now().subtract(const Duration(days: 1));
      await pumpApp(tester, h);
      final store = await ProviderScope.containerOf(
        tester.element(find.byType(PennyWiseApp)),
      ).read(ledgerStoreProvider.future);
      final dueDay = DateTime.now().add(const Duration(days: 10));
      late Due d;
      await untilDone(tester, () async {
        final cash = await store.createAccount(
          name: 'Cash',
          type: 'cash',
          currency: 'USD',
        );
        d = await store.createDue(
          direction: DueDirection.owedToMe,
          kind: DueKind.loan,
          person: 'Rahim',
          amountMinor: 5000,
          currency: 'USD',
          startDate: '2026-11-01',
          dueDate:
              '${dueDay.year}-${dueDay.month.toString().padLeft(2, '0')}-${dueDay.day.toString().padLeft(2, '0')}',
          remindDaysBefore: 1,
          accountId: cash.id,
        );
      });
      await settle(tester);
      expect(
        h.reminders.scheduled.values.single.title,
        'Rahim owes you 50.00 USD',
      );

      // Tapping the notification opens the due.
      h.reminders.onOpen!(d.id);
      await settle(tester);
      expect(find.text('Rahim owes you'), findsOneWidget);

      await tapOn(tester, find.text('Mark received'));
      await tapOn(tester, find.widgetWithText(FilledButton, 'Save'));
      expect(
        h.reminders.scheduled,
        isEmpty,
        reason: 'settled: nothing to remind',
      );
      await finish(tester);
    },
  );

  testWidgets(
    'the form asks for notification permission when a reminder is set',
    (tester) async {
      final h = TestHarness()
        ..store.guestProfile = {
          'name': '',
          'base_currency': 'USD',
          'timezone': 'UTC',
          'locale': 'en',
        };
      await pumpApp(tester, h);
      await tapOn(tester, find.text('Settings').last);
      final dues = find.text('Dues');
      await tester.scrollUntilVisible(
        dues,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tapOn(tester, dues);
      await tapOn(tester, find.text('Add due'));
      await tester.enterText(field('Who owes you?'), 'Nadia');
      await tester.enterText(field('Amount'), '10');
      final add = find.widgetWithText(FilledButton, 'Add due');
      await tester.scrollUntilVisible(
        add,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      // "Money moved now" needs an account: there is none, so turn it off.
      await tapOn(tester, find.text('Money moved now'));
      await tapOn(tester, add);
      expect(h.reminders.permissionAsks, 0, reason: 'no due date, no reminder');
      expect(find.text('Nadia owes you'), findsOneWidget);

      // Edit: give it a due date (the reminder defaults to 1 day before).
      await tapOn(tester, find.byTooltip('Edit due'));
      await tapOn(tester, find.text('No due date'));
      await tapOn(tester, find.text('OK'));
      expect(find.text('1 day before'), findsOneWidget);
      final save = find.widgetWithText(FilledButton, 'Save changes');
      await tester.scrollUntilVisible(
        save,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tapOn(tester, save);
      expect(h.reminders.permissionAsks, 1);
      await finish(tester);
    },
  );
}
