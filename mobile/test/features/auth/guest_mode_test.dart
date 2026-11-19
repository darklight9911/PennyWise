import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/core/database/local_database.dart';
import 'package:pennywise/features/auth/application/auth_controller.dart';
import 'package:pennywise/features/ledger/application/ledger_providers.dart';
import 'package:pennywise/features/ledger/domain/default_categories.dart';
import 'package:pennywise/features/sync/sync_controller.dart';

import '../../support/test_app.dart';

/// Using pennyWise without an account, and signing in later.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const email = 'ann@example.com';
  const password = 'ann-password-1';
  late TestHarness h;
  late ProviderContainer c;
  AuthController auth() => c.read(authControllerProvider.notifier);

  /// Lets timers, futures and the fake server finish.
  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  setUp(() async {
    h = TestHarness();
    h.backend.seedUser(email, password);
    c = h.container();
    addTearDown(c.dispose);
    addTearDown(h.local.close);
    c.listen(syncControllerProvider, (_, _) {}); // alive, like in the app
    await settle();
  });

  test('first launch needs only the main currency', () async {
    expect(c.read(authControllerProvider), isA<SetupNeeded>());
    await auth().startAsGuest(baseCurrency: 'EUR');

    final state = c.read(authControllerProvider);
    expect(state, isA<Guest>());
    expect(c.read(baseCurrencyProvider), 'EUR');
    expect(h.store.guestProfile?['base_currency'], 'EUR');
    expect(h.store.tokens, isNull);
  });

  test('a guest gets the default categories, once', () async {
    await auth().startAsGuest(baseCurrency: 'EUR');
    final store = await c.read(ledgerStoreProvider.future);
    final names = (await store.watchCategories().first).map((x) => x.name);
    expect(names.length, defaultCategories.length);
    expect(names, contains('Groceries'));

    await store.seedDefaultCategories(); // again: nothing new
    expect(
      (await store.watchCategories().first).length,
      defaultCategories.length,
    );
  });

  test('guest data stays on the phone: nothing is sent', () async {
    await auth().startAsGuest(baseCurrency: 'EUR');
    final store = await c.read(ledgerStoreProvider.future);
    await store.createAccount(name: 'Wallet', type: 'cash', currency: 'EUR');
    await settle();

    expect(h.backend.callCount('/sync/push'), 0);
    expect(h.backend.callCount('/sync/pull'), 0);
    expect(await h.local.owner(), LocalDatabase.guestOwner);
  });

  test('signing in keeps guest data and marks it for merging', () async {
    await auth().startAsGuest(baseCurrency: 'EUR');
    final guestStore = await c.read(ledgerStoreProvider.future);
    await guestStore.createAccount(
      name: 'Wallet',
      type: 'cash',
      currency: 'EUR',
    );

    await auth().login(email, password);
    await settle();

    expect(h.local.wipeCount, 0, reason: 'guest data is kept');
    expect(await h.local.owner(), h.backend.users[email]!['id']);
    final store = await c.read(ledgerStoreProvider.future);
    final accounts = await store.watchAccounts().first;
    expect(accounts.map((a) => a.name), contains('Wallet'));
  });

  test('signing in uploads guest data, joining default categories', () async {
    // The account already has its own "Groceries" (server defaults).
    h.backend.serverWrite(email, 'category', 'acct-groceries', {
      'parent_id': null,
      'name': 'Groceries',
      'kind': 'expense',
      'icon': 'local_grocery_store',
      'color': '#81B29A',
      'sort_order': 1,
    }, updatedAt: DateTime.utc(2026, 11, 1));

    await auth().startAsGuest(baseCurrency: 'USD');
    final guest = await c.read(ledgerStoreProvider.future);
    final groceries = (await guest.watchCategories(kind: 'expense').first)
        .firstWhere((x) => x.name == 'Groceries');
    final wallet = await guest.createAccount(
      name: 'Wallet',
      type: 'cash',
      currency: 'USD',
    );
    final tx = await guest.createTransaction(
      kind: 'expense',
      accountId: wallet.id,
      amountMinor: 1250,
      currency: 'USD',
      occurredAt: DateTime(2026, 11, 19, 18),
      categoryId: groceries.id,
    );

    await auth().login(email, password);
    for (var i = 0; i < 5; i++) {
      await settle();
    }

    final server = h.backend.serverRows;
    expect(server[('account', wallet.id)], isNotNull, reason: 'uploaded');
    expect(
      server[('transaction', tx.id)]?.data['category_id'],
      'acct-groceries',
      reason: "joined into the account's Groceries",
    );
    final groceriesOnServer = server.values.where(
      (r) => r.entity == 'category' && r.data['name'] == 'Groceries',
    );
    expect(groceriesOnServer, hasLength(1), reason: 'no duplicate category');

    final store = await c.read(ledgerStoreProvider.future);
    expect(await store.watchPendingCount().first, 0, reason: 'all synced');
  });

  test('erasing guest data starts empty, same currency', () async {
    await auth().startAsGuest(baseCurrency: 'JPY');
    final store = await c.read(ledgerStoreProvider.future);
    await store.createAccount(name: 'Wallet', type: 'cash', currency: 'JPY');

    await auth().eraseGuestData();
    await settle();

    expect(h.local.wipeCount, 1);
    expect(c.read(baseCurrencyProvider), 'JPY');
    final fresh = await c.read(ledgerStoreProvider.future);
    expect(await fresh.watchAccounts().first, isEmpty);
  });

  test('an expired session keeps the data and stops syncing', () async {
    await auth().login(email, password);
    await settle();
    final store = await c.read(ledgerStoreProvider.future);
    await store.createAccount(name: 'Wallet', type: 'cash', currency: 'USD');
    await settle();

    h.backend.revokeAllSessions();
    await expectLater(auth().refreshUser(), throwsA(anything));
    await settle();

    final state = c.read(authControllerProvider);
    expect(state, isA<SignedIn>());
    expect((state as SignedIn).sessionExpired, isTrue);
    expect(h.local.wipeCount, 0);

    // Still usable offline-style; nothing is pushed until a new log-in.
    final pushes = h.backend.callCount('/sync/push');
    await store.createAccount(name: 'Card', type: 'card', currency: 'USD');
    await settle();
    expect(h.backend.callCount('/sync/push'), pushes);

    await auth().login(email, password);
    await settle();
    expect(c.read(authControllerProvider), isA<SignedIn>());
    expect(
      (c.read(authControllerProvider) as SignedIn).sessionExpired,
      isFalse,
    );
    expect(h.backend.callCount('/sync/push'), greaterThan(pushes));
  });
}
