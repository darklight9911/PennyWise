import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/core/database/app_database.dart';
import 'package:pennywise/core/network/api_client.dart';
import 'package:pennywise/core/network/api_exception.dart';
import 'package:pennywise/features/auth/data/auth_api.dart';
import 'package:pennywise/features/ledger/data/ledger_store.dart';
import 'package:pennywise/features/sync/sync_engine.dart';

import '../../support/fake_backend.dart';
import '../../support/test_app.dart';

const email = 'ann@example.com';

void main() {
  late TestHarness h;
  late AppDatabase db;
  late LedgerStore store;
  late SyncEngine engine;

  setUp(() async {
    h = TestHarness();
    h.backend.seedUser(email, 'ann-password-1');
    final c = h.container();
    addTearDown(c.dispose);
    final login = await c
        .read(authApiProvider)
        .login(email: email, password: 'ann-password-1', deviceName: 't');
    await c.read(sessionManagerProvider).save(login.tokens);

    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    store = LedgerStore(db);
    engine = SyncEngine(db: db, dio: c.read(dioProvider));
  });

  Future<List<OutboxData>> outbox() => db.select(db.outbox).get();
  FakeServerRow? onServer(String entity, String id) =>
      h.backend.serverRows[(entity, id)];

  test('push sends local rows and empties the outbox', () async {
    final bank = await store.createAccount(
      name: 'Bank',
      type: 'bank',
      currency: 'USD',
    );
    final food = await store.createCategory(name: 'Food', kind: 'expense');
    final t = await store.createTransaction(
      kind: TxKind.expense,
      accountId: bank.id,
      amountMinor: 1250,
      currency: 'USD',
      occurredAt: DateTime.utc(2026, 11, 15, 12),
      categoryId: food.id,
      note: 'lunch',
    );

    final report = await engine.sync();
    expect(report.pushed, 3);
    expect(await outbox(), isEmpty);
    final row = onServer(Entity.transaction, t.id)!;
    expect(row.data['amount_minor'], 1250);
    expect(row.data['local_date'], '2026-11-15');
    expect(row.data['note'], 'lunch');
    expect(
      row.updatedAt,
      t.updatedAt,
      reason: 'exact edit time, no precision lost',
    );
  });

  test(
    'pull brings rows from the server (e.g. default categories, other phone)',
    () async {
      h.backend.serverWrite(email, Entity.category, 'cat-1', {
        'parent_id': null,
        'name': 'Salary',
        'kind': 'income',
        'icon': 'payments',
        'color': '#2F7734',
        'sort_order': 0,
      }, updatedAt: DateTime.utc(2026, 11, 1));

      final report = await engine.sync();
      expect(report.pulled, 1);
      final cats = await store.watchCategories().first;
      expect(cats.single.name, 'Salary');
      expect(cats.single.serverVersion, isNotNull);
      expect(await db.readMeta(SyncEngine.cursorKey), isNot('0'));
    },
  );

  test(
    'a pending local edit is not overwritten by an older server copy',
    () async {
      var a = await store.createAccount(
        name: 'Bank',
        type: 'bank',
        currency: 'USD',
      );
      await engine.sync();
      a = await store.updateAccount(
        a.copyWith(name: 'My bank'),
      ); // offline edit, not pushed

      // Meanwhile another phone renamed it (pushed earlier, with an older edit time).
      h.backend.serverWrite(email, Entity.account, a.id, {
        'name': 'Other phone',
        'type': 'bank',
        'currency': 'USD',
        'opening_balance_minor': 0,
        'icon': '',
        'color': '',
        'archived': false,
        'sort_order': 0,
      }, updatedAt: a.updatedAt.subtract(const Duration(minutes: 5)));

      await engine.sync();
      final local = (await store.watchAccounts().first).single;
      expect(
        local.name,
        'My bank',
        reason: 'the newer edit wins on both sides',
      );
      expect(onServer(Entity.account, a.id)!.data['name'], 'My bank');
    },
  );

  test('an edit made while a push is in flight stays queued', () async {
    var a = await store.createAccount(
      name: 'Bank',
      type: 'bank',
      currency: 'USD',
    );
    var edited = false;
    h.backend.onPush = () async {
      if (edited) return;
      edited = true;
      a = await store.updateAccount(a.copyWith(name: 'Edited during push'));
    };

    await engine.sync();
    // The first push carried "Bank"; the edit must not be lost: the next
    // run (queued automatically by the write) sends it.
    final o = await outbox();
    if (o.isNotEmpty) {
      expect(o.single.queuedUpdatedAt, a.updatedAt);
      await engine.sync();
    }
    expect(onServer(Entity.account, a.id)!.data['name'], 'Edited during push');
    expect(await outbox(), isEmpty);
  });

  test(
    'a rejected change is kept with its reason and not retried as-is',
    () async {
      final bad = await store.createAccount(
        name: 'REJECT ME',
        type: 'bank',
        currency: 'USD',
      );
      final good = await store.createAccount(
        name: 'Fine',
        type: 'bank',
        currency: 'USD',
      );

      final report = await engine.sync();
      expect(report.rejected, 1);
      expect(onServer(Entity.account, good.id), isNotNull);
      final o = (await outbox()).single;
      expect(o.rowId, bad.id);
      expect(o.rejectedCode, 'invalid');

      final calls = h.backend.callCount('/sync/push');
      await engine.sync();
      expect(
        h.backend.callCount('/sync/push'),
        calls,
        reason: 'nothing left to push',
      );
    },
  );

  test('the server copy replaces a rejected local edit', () async {
    var a = await store.createAccount(
      name: 'Bank',
      type: 'bank',
      currency: 'USD',
    );
    await engine.sync();
    a = await store.updateAccount(a.copyWith(name: 'REJECT ME'));
    await engine.sync();
    expect((await outbox()).single.rejectedCode, isNotNull);

    h.backend.serverWrite(email, Entity.account, a.id, {
      'name': 'Server name',
      'type': 'bank',
      'currency': 'USD',
      'opening_balance_minor': 0,
      'icon': '',
      'color': '',
      'archived': false,
      'sort_order': 0,
    }, updatedAt: DateTime.now().toUtc());
    await engine.sync();
    expect((await store.watchAccounts().first).single.name, 'Server name');
    expect(await outbox(), isEmpty);
  });

  test('pull pages through everything and remembers the cursor', () async {
    h.backend.pullPageSize = 3;
    for (var i = 0; i < 10; i++) {
      h.backend.serverWrite(email, Entity.category, 'c$i', {
        'parent_id': null,
        'name': 'Cat $i',
        'kind': 'expense',
        'icon': '',
        'color': '',
        'sort_order': i,
      }, updatedAt: DateTime.utc(2026, 11, 1));
    }
    final report = await engine.sync();
    expect(report.pulled, 10);
    expect(await store.watchCategories().first, hasLength(10));

    final pulls = h.backend.callCount('/sync/pull');
    await engine.sync();
    expect(
      h.backend.callCount('/sync/pull'),
      pulls + 1,
      reason: 'one call, nothing new',
    );
  });

  test('deletions from the server are applied', () async {
    final a = await store.createAccount(
      name: 'Old',
      type: 'bank',
      currency: 'USD',
    );
    await engine.sync();
    h.backend.serverWrite(
      email,
      Entity.account,
      a.id,
      {
        'name': 'Old',
        'type': 'bank',
        'currency': 'USD',
        'opening_balance_minor': 0,
        'icon': '',
        'color': '',
        'archived': false,
        'sort_order': 0,
      },
      updatedAt: DateTime.now().toUtc(),
      deletedAt: DateTime.now().toUtc(),
    );
    await engine.sync();
    expect(await store.watchAccounts().first, isEmpty);
  });

  test('offline: the sync fails, the outbox keeps everything', () async {
    await store.createAccount(name: 'Bank', type: 'bank', currency: 'USD');
    h.backend.offline = true;
    await expectLater(
      engine.sync(),
      throwsA(
        isA<ApiException>().having((e) => e.isNetworkError, 'network', isTrue),
      ),
    );
    expect(await outbox(), hasLength(1));

    h.backend.offline = false;
    await engine.sync();
    expect(await outbox(), isEmpty);
  });

  test('parallel sync calls share one run plus one follow-up', () async {
    await store.createAccount(name: 'Bank', type: 'bank', currency: 'USD');
    await Future.wait([engine.sync(), engine.sync(), engine.sync()]);
    expect(h.backend.callCount('/sync/push'), lessThanOrEqualTo(2));
    expect(await outbox(), isEmpty);
  });

  test('server-computed base amounts arrive with the pull', () async {
    final bank = await store.createAccount(
      name: 'Bank',
      type: 'bank',
      currency: 'USD',
    );
    final food = await store.createCategory(name: 'Food', kind: 'expense');
    final t = await store.createTransaction(
      kind: TxKind.expense,
      accountId: bank.id,
      amountMinor: 500,
      currency: 'USD',
      occurredAt: DateTime.utc(2026, 11, 15),
      categoryId: food.id,
    );
    await engine.sync();
    // The real server fills these; the fake stores what it got, so set them.
    final row = onServer(Entity.transaction, t.id)!;
    h.backend.serverWrite(email, Entity.transaction, t.id, {
      ...row.data,
      'amount_base_minor': 500,
      'fx_rate_to_base': '1.0000000000',
    }, updatedAt: row.updatedAt.add(const Duration(seconds: 1)));
    await engine.sync();
    final local = await store.getTransaction(t.id);
    expect(local!.amountBaseMinor, 500);
    expect(local.fxRateToBase, '1.0000000000');
  });

  test('unknown entity types from a newer server are skipped safely', () async {
    h.backend.serverWrite(email, 'budget', 'b1', {
      'x': 1,
    }, updatedAt: DateTime.utc(2026));
    final report = await engine.sync();
    expect(report.pulled, 0);
  });

  test('ignores Value import lint', () => expect(const Value(1).value, 1));
}
