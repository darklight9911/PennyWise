import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';

/// Entity names, as the sync API uses them.
abstract final class Entity {
  static const account = 'account';
  static const category = 'category';
  static const transaction = 'transaction';
}

abstract final class TxKind {
  static const income = 'income';
  static const expense = 'expense';
  static const transfer = 'transfer';
}

/// Income and expense totals of one month, in one currency.
class MonthTotals {
  const MonthTotals({this.incomeMinor = 0, this.expenseMinor = 0});
  final int incomeMinor;
  final int expenseMinor;
}

/// Reads and writes accounts, categories and transactions on the phone.
///
/// Every write also queues the row in the outbox, in the same local
/// transaction, so nothing is ever saved without being scheduled for sync.
class LedgerStore {
  LedgerStore(this.db, {DateTime Function()? now, String Function()? newId})
    : _now = now ?? DateTime.now,
      _newId = newId ?? const Uuid().v7;

  final AppDatabase db;
  final DateTime Function() _now;
  final String Function() _newId;

  DateTime _stamp() => _now().toUtc();

  /// Called after every local write (the sync engine listens to push soon).
  void Function()? onLocalWrite;

  // ---------------------------------------------------------------- accounts

  Stream<List<Account>> watchAccounts({bool includeArchived = true}) {
    final q = db.select(db.accounts)
      ..where((a) => a.deletedAt.isNull())
      ..orderBy([
        (a) => OrderingTerm(expression: a.sortOrder),
        (a) => OrderingTerm(expression: a.name),
      ]);
    if (!includeArchived) q.where((a) => a.archived.equals(false));
    return q.watch();
  }

  Future<Account> createAccount({
    required String name,
    required String type,
    required String currency,
    int openingBalanceMinor = 0,
    String icon = '',
    String color = '',
  }) async {
    final row = AccountsCompanion.insert(
      id: _newId(),
      name: name.trim(),
      type: type,
      currency: currency,
      openingBalanceMinor: Value(openingBalanceMinor),
      icon: Value(icon),
      color: Value(color),
      updatedAt: _stamp(),
    );
    return _write(
      Entity.account,
      row.id.value,
      row.updatedAt.value,
      () => db.into(db.accounts).insertReturning(row),
    );
  }

  Future<Account> updateAccount(Account a) {
    final changed = a.copyWith(name: a.name.trim(), updatedAt: _stamp());
    return _write(Entity.account, a.id, changed.updatedAt, () async {
      await db.update(db.accounts).replace(changed);
      return changed;
    });
  }

  /// Deletes the account and every transaction in or out of it.
  Future<void> deleteAccount(String id) => db.transaction(() async {
    final at = _stamp();
    await _softDelete(db.accounts, Entity.account, id, at);
    final linked =
        await (db.select(db.transactions)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  (t.accountId.equals(id) | t.transferAccountId.equals(id)),
            ))
            .get();
    for (final t in linked) {
      await _softDelete(db.transactions, Entity.transaction, t.id, at);
    }
    onLocalWrite?.call();
  });

  /// Balance of every account: opening balance + income − expenses
  /// − transfers out + transfers in. In each account's own currency.
  Stream<Map<String, int>> watchBalances() {
    return db
        .customSelect(
          '''
          SELECT a.id AS id, a.opening_balance_minor
            + COALESCE((SELECT SUM(CASE t.kind WHEN 'income' THEN t.amount_minor ELSE -t.amount_minor END)
                          FROM transactions t
                         WHERE t.account_id = a.id AND t.deleted_at IS NULL), 0)
            + COALESCE((SELECT SUM(t.transfer_amount_minor)
                          FROM transactions t
                         WHERE t.transfer_account_id = a.id AND t.kind = 'transfer' AND t.deleted_at IS NULL), 0)
            AS balance
          FROM accounts a WHERE a.deleted_at IS NULL
          ''',
          readsFrom: {db.accounts, db.transactions},
        )
        .watch()
        .map(
          (rows) => {
            for (final r in rows) r.read<String>('id'): r.read<int>('balance'),
          },
        );
  }

  // -------------------------------------------------------------- categories

  Stream<List<Category>> watchCategories({String? kind}) {
    final q = db.select(db.categories)
      ..where((c) => c.deletedAt.isNull())
      ..orderBy([
        (c) => OrderingTerm(expression: c.sortOrder),
        (c) => OrderingTerm(expression: c.name),
      ]);
    if (kind != null) q.where((c) => c.kind.equals(kind));
    return q.watch();
  }

  /// All categories including deleted ones, so old transactions still show a name.
  Stream<Map<String, Category>> watchCategoryIndex() => db
      .select(db.categories)
      .watch()
      .map((all) => {for (final c in all) c.id: c});

  Future<Category> createCategory({
    required String name,
    required String kind,
    String? parentId,
    String icon = '',
    String color = '',
    int sortOrder = 0,
  }) {
    final row = CategoriesCompanion.insert(
      id: _newId(),
      name: name.trim(),
      kind: kind,
      parentId: Value(parentId),
      icon: Value(icon),
      color: Value(color),
      sortOrder: Value(sortOrder),
      updatedAt: _stamp(),
    );
    return _write(
      Entity.category,
      row.id.value,
      row.updatedAt.value,
      () => db.into(db.categories).insertReturning(row),
    );
  }

  Future<Category> updateCategory(Category c) {
    final changed = c.copyWith(name: c.name.trim(), updatedAt: _stamp());
    return _write(Entity.category, c.id, changed.updatedAt, () async {
      await db.update(db.categories).replace(changed);
      return changed;
    });
  }

  /// Deletes a category and its sub-categories. Old transactions keep
  /// pointing at it (they still show its name).
  Future<void> deleteCategory(String id) => db.transaction(() async {
    final at = _stamp();
    final children = await (db.select(
      db.categories,
    )..where((c) => c.parentId.equals(id) & c.deletedAt.isNull())).get();
    for (final c in children) {
      await _softDelete(db.categories, Entity.category, c.id, at);
    }
    await _softDelete(db.categories, Entity.category, id, at);
    onLocalWrite?.call();
  });

  // ------------------------------------------------------------ transactions

  /// Newest first. Optionally only one account (in or out of it).
  Stream<List<MoneyTransaction>> watchTransactions({
    String? accountId,
    int? limit,
  }) {
    final q = db.select(db.transactions)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.desc(t.localDate),
        (t) => OrderingTerm.desc(t.occurredAt),
      ]);
    if (accountId != null) {
      q.where(
        (t) =>
            t.accountId.equals(accountId) |
            t.transferAccountId.equals(accountId),
      );
    }
    if (limit != null) q.limit(limit);
    return q.watch();
  }

  Future<MoneyTransaction?> getTransaction(String id) => (db.select(
    db.transactions,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<MoneyTransaction> createTransaction({
    required String kind,
    required String accountId,
    required int amountMinor,
    required String currency,
    required DateTime occurredAt,
    String? categoryId,
    String? transferAccountId,
    int? transferAmountMinor,
    String note = '',
  }) {
    final row = TransactionsCompanion.insert(
      id: _newId(),
      kind: kind,
      accountId: accountId,
      categoryId: Value(categoryId),
      amountMinor: amountMinor,
      currency: currency,
      transferAccountId: Value(transferAccountId),
      transferAmountMinor: Value(transferAmountMinor),
      occurredAt: occurredAt.toUtc(),
      localDate: localDateOf(occurredAt),
      note: Value(note.trim()),
      updatedAt: _stamp(),
    );
    return _write(
      Entity.transaction,
      row.id.value,
      row.updatedAt.value,
      () => db.into(db.transactions).insertReturning(row),
    );
  }

  Future<MoneyTransaction> updateTransaction(MoneyTransaction t) {
    final changed = t.copyWith(
      occurredAt: t.occurredAt.toUtc(),
      localDate: localDateOf(t.occurredAt),
      note: t.note.trim(),
      // The server recomputes these from the new amount and currency.
      amountBaseMinor: const Value(null),
      fxRateToBase: const Value(null),
      updatedAt: _stamp(),
    );
    return _write(Entity.transaction, t.id, changed.updatedAt, () async {
      await db.update(db.transactions).replace(changed);
      return changed;
    });
  }

  Future<void> deleteTransaction(String id) => db.transaction(() async {
    await _softDelete(db.transactions, Entity.transaction, id, _stamp());
    onLocalWrite?.call();
  });

  /// Income and expenses of one month (YYYY-MM) in one currency.
  /// Transfers are moves between own accounts, so they are not counted.
  Stream<MonthTotals> watchMonthTotals(String yearMonth, String currency) {
    return db
        .customSelect(
          '''
          SELECT kind, SUM(amount_minor) AS total FROM transactions
           WHERE deleted_at IS NULL AND currency = ? AND substr(local_date, 1, 7) = ?
             AND kind IN ('income', 'expense')
           GROUP BY kind
          ''',
          variables: [
            Variable.withString(currency),
            Variable.withString(yearMonth),
          ],
          readsFrom: {db.transactions},
        )
        .watch()
        .map((rows) {
          var income = 0, expense = 0;
          for (final r in rows) {
            if (r.read<String>('kind') == TxKind.income) {
              income = r.read<int>('total');
            } else {
              expense = r.read<int>('total');
            }
          }
          return MonthTotals(incomeMinor: income, expenseMinor: expense);
        });
  }

  // ------------------------------------------------------------------ outbox

  /// How many local changes are waiting to sync (rejected ones excluded).
  Stream<int> watchPendingCount() =>
      (db.selectOnly(db.outbox)
            ..addColumns([db.outbox.rowId.count()])
            ..where(db.outbox.rejectedCode.isNull()))
          .watchSingle()
          .map((r) => r.read(db.outbox.rowId.count()) ?? 0);

  /// Changes the server refused (shown to the user to fix).
  Stream<List<OutboxData>> watchRejected() =>
      (db.select(db.outbox)..where((o) => o.rejectedCode.isNotNull())).watch();

  // ----------------------------------------------------------------- helpers

  Future<T> _write<T>(
    String entity,
    String id,
    DateTime updatedAt,
    Future<T> Function() write,
  ) async {
    final result = await db.transaction(() async {
      final r = await write();
      await _queue(entity, id, updatedAt);
      return r;
    });
    onLocalWrite?.call();
    return result;
  }

  /// Queues a row for sync. A new edit replaces the old queue entry and
  /// clears an old rejection (the user may have fixed the problem).
  Future<void> _queue(String entity, String id, DateTime updatedAt) => db
      .into(db.outbox)
      .insert(
        OutboxCompanion.insert(
          entity: entity,
          rowId: id,
          queuedUpdatedAt: updatedAt,
        ),
        onConflict: DoUpdate(
          (_) => OutboxCompanion(
            queuedUpdatedAt: Value(updatedAt),
            attempts: const Value(0),
            rejectedCode: const Value(null),
            rejectedMessage: const Value(null),
          ),
        ),
      );

  Future<void> _softDelete<T extends Table, D>(
    TableInfo<T, D> table,
    String entity,
    String id,
    DateTime at,
  ) async {
    await db.customUpdate(
      'UPDATE ${table.actualTableName} SET deleted_at = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL',
      variables: [
        Variable.withDateTime(at),
        Variable.withDateTime(at),
        Variable.withString(id),
      ],
      updates: {table},
    );
    await _queue(entity, id, at);
  }
}

/// The calendar date (YYYY-MM-DD) of [t] in the phone's time zone.
String localDateOf(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year.toString().padLeft(4, '0')}-${two(l.month)}-${two(l.day)}';
}
