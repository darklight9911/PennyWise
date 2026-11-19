import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/features/auth/application/auth_controller.dart';
import 'package:pennywise/features/ledger/application/ledger_providers.dart';
import 'package:pennywise/features/ledger/data/ledger_store.dart';
import 'package:pennywise/features/recurring/domain/recurrence.dart';
import 'package:pennywise/features/sync/sync_controller.dart';

import '../../support/test_app.dart';

const email = 'ann@example.com';
const password = 'ann-password-1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // app lifecycle listener

  late TestHarness h;
  late ProviderContainer c;

  setUp(() {
    h = TestHarness();
    h.backend.seedUser(email, password);
    c = h.container();
    addTearDown(c.dispose);
    addTearDown(h.local.close);
    c.listen(
      syncControllerProvider,
      (_, _) {},
    ); // keep it alive, like the app does
  });

  /// Lets timers, futures and the fake server finish.
  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('logging in syncs: the default categories arrive', () async {
    h.backend.serverWrite(email, Entity.category, 'cat-salary', {
      'parent_id': null,
      'name': 'Salary',
      'kind': 'income',
      'icon': 'payments',
      'color': '',
      'sort_order': 0,
    }, updatedAt: DateTime.utc(2026, 11, 1));

    await c.read(authControllerProvider.notifier).login(email, password);
    await settle();

    final store = await c.read(ledgerStoreProvider.future);
    expect((await store.watchCategories().first).map((x) => x.name), [
      'Salary',
    ]);
    expect(c.read(syncControllerProvider).lastSyncedAt, isNotNull);
  });

  test('a local change is pushed shortly after', () async {
    await c.read(authControllerProvider.notifier).login(email, password);
    await settle();
    final store = await c.read(ledgerStoreProvider.future);

    final a = await store.createAccount(
      name: 'Wallet',
      type: 'cash',
      currency: 'USD',
    );
    await settle();
    expect(
      h.backend.serverRows[(Entity.account, a.id)]?.data['name'],
      'Wallet',
    );
    expect(await store.watchPendingCount().first, 0);
  });

  test('offline: status says so, changes wait, next sync sends them', () async {
    await c.read(authControllerProvider.notifier).login(email, password);
    await settle();
    final store = await c.read(ledgerStoreProvider.future);

    h.backend.offline = true;
    await store.createAccount(
      name: 'Offline wallet',
      type: 'cash',
      currency: 'USD',
    );
    await settle();
    expect(c.read(syncControllerProvider).offline, isTrue);
    expect(
      c.read(syncControllerProvider).error,
      isNull,
      reason: 'offline is not an error',
    );
    expect(await store.watchPendingCount().first, 1);

    h.backend.offline = false;
    await c.read(syncControllerProvider.notifier).syncNow();
    expect(c.read(syncControllerProvider).offline, isFalse);
    expect(await store.watchPendingCount().first, 0);
  });

  test('after logout nothing syncs any more', () async {
    await c.read(authControllerProvider.notifier).login(email, password);
    await settle();
    await c.read(authControllerProvider.notifier).logout();
    await settle();
    final calls = h.backend.calls.length;
    await c.read(syncControllerProvider.notifier).syncNow();
    expect(h.backend.calls.length, calls);
  });

  test(
    'logging out during a sync or right after a change reports no error',
    () async {
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);

      await c.read(authControllerProvider.notifier).login(email, password);
      await settle();
      final store = await c.read(ledgerStoreProvider.future);

      // Log out while a push is on its way...
      h.backend.onPush = () => c.read(authControllerProvider.notifier).logout();
      await store.createAccount(name: 'Wallet', type: 'cash', currency: 'USD');
      await settle();
      expect(c.read(authControllerProvider), isA<Guest>());

      // ...and right after a change, before its sync starts.
      h.backend.onPush = null;
      await c.read(authControllerProvider.notifier).login(email, password);
      await settle();
      final store2 = await c.read(ledgerStoreProvider.future);
      await store2.createAccount(
        name: 'Wallet 2',
        type: 'cash',
        currency: 'USD',
      );
      await c.read(authControllerProvider.notifier).logout();
      await settle();

      expect(
        reported,
        isEmpty,
        reason: reported.map((e) => e.exception).join('\n'),
      );
      expect(c.read(syncControllerProvider).error, isNull);
    },
  );

  test('bills that came due are created and uploaded when syncing', () async {
    await c.read(authControllerProvider.notifier).login(email, password);
    await settle();
    final store = await c.read(ledgerStoreProvider.future);
    final bank = await store.createAccount(
      name: 'Bank',
      type: 'bank',
      currency: 'USD',
    );
    final rent = await store.createCategory(name: 'Rent', kind: 'expense');
    final today = DateTime.now();
    final start = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 2));
    final rule = await store.createRecurringRule(
      kind: 'expense',
      accountId: bank.id,
      categoryId: rent.id,
      amountMinor: 999,
      currency: 'USD',
      frequency: 'daily',
      startDate: ymd(start),
    );
    await settle();
    await c.read(syncControllerProvider.notifier).syncNow();
    await settle();

    final bills = h.backend.serverRows.values
        .where((r) => r.data['recurring_id'] == rule.id)
        .toList();
    expect(bills, hasLength(3), reason: 'two days ago, yesterday, today');
  });
}
