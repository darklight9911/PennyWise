import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/core/database/app_database.dart';
import 'package:pennywise/core/network/api_client.dart';
import 'package:pennywise/core/network/api_exception.dart';
import 'package:pennywise/features/auth/data/auth_api.dart';
import 'package:pennywise/features/ledger/data/ledger_store.dart';
import 'package:pennywise/features/recurring/domain/recurrence.dart';
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
    h.backend.serverWrite(email, 'future_thing', 'f1', {
      'x': 1,
    }, updatedAt: DateTime.utc(2026));
    final report = await engine.sync();
    expect(report.pulled, 0);
  });

  test('ignores Value import lint', () => expect(const Value(1).value, 1));

  test('a stopped engine never syncs again (logout)', () async {
    await store.createAccount(name: 'Bank', type: 'bank', currency: 'USD');
    await engine.stop();
    final calls = h.backend.calls.length;
    final report = await engine.sync();
    expect(report.pushed, 0);
    expect(h.backend.calls.length, calls);
    expect(engine.isStopped, isTrue);
  });

  test('budgets sync both ways', () async {
    final food = await store.createCategory(name: 'Food', kind: 'expense');
    final b = await store.createBudget(
      categoryId: food.id,
      amountMinor: 30000,
      period: 'weekly',
      alertThresholds: [50, 100],
    );
    await engine.sync();
    final row = onServer(Entity.budget, b.id)!;
    expect(row.data, {
      'category_id': food.id,
      'amount_minor': 30000,
      'period': 'weekly',
      'alert_thresholds': [50, 100],
    });

    h.backend.serverWrite(email, Entity.budget, 'b-2', {
      'category_id': null,
      'amount_minor': 200000,
      'period': 'monthly',
      'alert_thresholds': [80, 100],
    }, updatedAt: DateTime.now().toUtc());
    await engine.sync();
    final budgets = {for (final x in await store.watchBudgets().first) x.id: x};
    expect(budgets['b-2']!.alertThresholds, '80,100');
    expect(budgets['b-2']!.categoryId, isNull);
  });

  test(
    'goals, contributions, recurring rules and bills sync both ways',
    () async {
      final bank = await store.createAccount(
        name: 'Bank',
        type: 'bank',
        currency: 'USD',
      );
      final rent = await store.createCategory(name: 'Rent', kind: 'expense');
      final goal = await store.createGoal(
        name: 'Trip',
        targetMinor: 90000,
        deadline: '2027-03-01',
      );
      final c = await store.addContribution(
        goalId: goal.id,
        amountMinor: 1500,
        date: DateTime(2026, 11, 3),
      );
      final rule = await store.createRecurringRule(
        kind: 'expense',
        accountId: bank.id,
        categoryId: rent.id,
        amountMinor: 120000,
        currency: 'USD',
        frequency: 'monthly',
        startDate: '2026-10-30',
        remindDaysBefore: 2,
      );
      await store.generateDueBills(DateTime(2026, 11, 18));
      await engine.sync();

      expect(onServer(Entity.goal, goal.id)!.data['deadline'], '2027-03-01');
      expect(
        onServer(Entity.goalContribution, c.id)!.data['amount_minor'],
        1500,
      );
      expect(
        onServer(Entity.recurringRule, rule.id)!.data['remind_days_before'],
        2,
      );
      final bill = onServer(
        Entity.transaction,
        occurrenceId(rule.id, DateTime(2026, 10, 30)),
      )!;
      expect(bill.data['recurring_id'], rule.id);
      expect(bill.data['occurrence_date'], '2026-10-30');

      // A bill the server's worker made comes down with its fields.
      final novId = occurrenceId(rule.id, DateTime(2026, 11, 30));
      h.backend.serverWrite(email, Entity.transaction, novId, {
        ...bill.data,
        'local_date': '2026-11-30',
        'occurrence_date': '2026-11-30',
      }, updatedAt: DateTime.now().toUtc());
      await engine.sync();
      final pulled = await store.getTransaction(novId);
      expect(pulled!.recurringId, rule.id);
      expect(pulled.occurrenceDate, '2026-11-30');
    },
  );

  test(
    'a typed exchange rate reaches the server and survives the pull',
    () async {
      final eur = await store.createAccount(
        name: 'Euro',
        type: 'cash',
        currency: 'EUR',
      );
      final food = await store.createCategory(name: 'Food', kind: 'expense');
      final t = await store.createTransaction(
        kind: TxKind.expense,
        accountId: eur.id,
        amountMinor: 1000,
        currency: 'EUR',
        occurredAt: DateTime.utc(2026, 11, 15, 12),
        categoryId: food.id,
        baseCurrency: 'USD',
        manualRate: '1.25',
      );
      await engine.sync();
      final row = onServer(Entity.transaction, t.id)!;
      expect(row.data['fx_rate_source'], 'manual');
      expect(row.data['amount_base_minor'], 1250);

      final local = await store.getTransaction(t.id);
      expect(
        (local!.amountBaseMinor, local.fxRateToBase, local.fxRateSource),
        (1250, '1.25', 'manual'),
      );
    },
  );

  test('the server fills a missing rate and the phone takes it', () async {
    final eur = await store.createAccount(
      name: 'Euro',
      type: 'cash',
      currency: 'EUR',
    );
    final food = await store.createCategory(name: 'Food', kind: 'expense');
    final t = await store.createTransaction(
      kind: TxKind.expense,
      accountId: eur.id,
      amountMinor: 1000,
      currency: 'EUR',
      occurredAt: DateTime.utc(2026, 11, 15, 12),
      categoryId: food.id,
      baseCurrency: 'USD',
    );
    await engine.sync();
    final row = onServer(Entity.transaction, t.id)!;
    // The fx job on the server found the day's rate.
    h.backend.serverWrite(email, Entity.transaction, t.id, {
      ...row.data,
      'fx_rate_to_base': '1.08',
      'fx_rate_source': 'auto',
      'amount_base_minor': 1080,
    }, updatedAt: row.updatedAt);
    await engine.sync();
    final local = await store.getTransaction(t.id);
    expect((local!.amountBaseMinor, local.fxRateSource), (1080, 'auto'));
  });
}
