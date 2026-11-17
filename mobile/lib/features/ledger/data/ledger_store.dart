import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../recurring/domain/recurrence.dart';

/// Entity names, as the sync API uses them.
abstract final class Entity {
  static const account = 'account';
  static const category = 'category';
  static const transaction = 'transaction';
  static const budget = 'budget';
  static const recurringRule = 'recurring_rule';
  static const goal = 'goal';
  static const goalContribution = 'goal_contribution';
}

abstract final class TxKind {
  static const income = 'income';
  static const expense = 'expense';
  static const transfer = 'transfer';
}

/// A budget with what was spent in its current period.
class BudgetProgress {
  const BudgetProgress({
    required this.budget,
    required this.spentMinor,
    required this.periodStart,
    required this.periodEnd,
  });

  final Budget budget;
  final int spentMinor;

  /// YYYY-MM-DD, inclusive / exclusive.
  final String periodStart;
  final String periodEnd;

  /// Share of the budget used: 0.5 = half, 1.2 = 20 % over.
  double get fraction => spentMinor / budget.amountMinor;
  int get leftMinor => budget.amountMinor - spentMinor;
  bool get over => spentMinor > budget.amountMinor;
}

/// First day of the budget period that contains [today] (a local date):
/// Monday for weekly budgets, the 1st for monthly ones. Same rule as the
/// server, so the phone and the alerts agree.
DateTime budgetPeriodStart(String period, DateTime today) {
  final d = DateTime.utc(today.year, today.month, today.day);
  if (period == 'weekly') return d.subtract(Duration(days: d.weekday - 1));
  return DateTime.utc(d.year, d.month);
}

DateTime budgetPeriodEnd(String period, DateTime start) => period == 'weekly'
    ? start.add(const Duration(days: 7))
    : DateTime.utc(start.year, start.month + 1);

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// A goal with the money saved towards it.
class GoalProgress {
  const GoalProgress({required this.goal, required this.savedMinor});
  final Goal goal;
  final int savedMinor;

  double get fraction => savedMinor / goal.targetMinor;
  int get leftMinor => goal.targetMinor - savedMinor;
  bool get reached => savedMinor >= goal.targetMinor;
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

  Future<Account?> getAccount(String id) =>
      (db.select(db.accounts)..where((a) => a.id.equals(id))).getSingleOrNull();

  /// Number of (not deleted) transactions in or out of an account.
  Future<int> countAccountTransactions(String accountId) async {
    final count = db.transactions.id.count();
    final row =
        await (db.selectOnly(db.transactions)
              ..addColumns([count])
              ..where(
                db.transactions.deletedAt.isNull() &
                    (db.transactions.accountId.equals(accountId) |
                        db.transactions.transferAccountId.equals(accountId)),
              ))
            .getSingle();
    return row.read(count) ?? 0;
  }

  /// Deletes the account and every transaction in or out of it.
  Future<void> deleteAccount(String id) async {
    await db.transaction(() async {
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
    });
    // After the transaction: a timer started inside it would run in the
    // transaction's zone after it closed.
    onLocalWrite?.call();
  }

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
  Future<void> deleteCategory(String id) async {
    await db.transaction(() async {
      final at = _stamp();
      final children = await (db.select(
        db.categories,
      )..where((c) => c.parentId.equals(id) & c.deletedAt.isNull())).get();
      for (final c in children) {
        await _softDelete(db.categories, Entity.category, c.id, at);
      }
      await _softDelete(db.categories, Entity.category, id, at);
    });
    // After the transaction: a timer started inside it would run in the
    // transaction's zone after it closed.
    onLocalWrite?.call();
  }

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

  Future<void> deleteTransaction(String id) async {
    await db.transaction(() async {
      await _softDelete(db.transactions, Entity.transaction, id, _stamp());
    });
    // After the transaction: a timer started inside it would run in the
    // transaction's zone after it closed.
    onLocalWrite?.call();
  }

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

  // ----------------------------------------------------------------- budgets

  Stream<List<Budget>> watchBudgets() =>
      (db.select(db.budgets)..where((b) => b.deletedAt.isNull())).watch();

  Future<Budget?> getBudget(String id) =>
      (db.select(db.budgets)..where((b) => b.id.equals(id))).getSingleOrNull();

  Future<Budget> createBudget({
    String? categoryId,
    required int amountMinor,
    required String period,
    List<int> alertThresholds = const [80, 100],
  }) {
    final row = BudgetsCompanion.insert(
      id: _newId(),
      categoryId: Value(categoryId),
      amountMinor: amountMinor,
      period: period,
      alertThresholds: Value(_levels(alertThresholds)),
      updatedAt: _stamp(),
    );
    return _write(
      Entity.budget,
      row.id.value,
      row.updatedAt.value,
      () => db.into(db.budgets).insertReturning(row),
    );
  }

  Future<Budget> updateBudget(Budget b) {
    final changed = b.copyWith(
      alertThresholds: _levels(parseLevels(b.alertThresholds)),
      updatedAt: _stamp(),
    );
    return _write(Entity.budget, b.id, changed.updatedAt, () async {
      await db.update(db.budgets).replace(changed);
      return changed;
    });
  }

  Future<void> deleteBudget(String id) async {
    await db.transaction(
      () => _softDelete(db.budgets, Entity.budget, id, _stamp()),
    );
    onLocalWrite?.call();
  }

  /// Every live budget with its spending in the current period. Amounts in
  /// [baseCurrency]: the server's base amount when known, otherwise the
  /// amount itself if the transaction is already in the base currency.
  Stream<List<BudgetProgress>> watchBudgetProgress(
    String baseCurrency,
    DateTime today,
  ) {
    final ws = budgetPeriodStart('weekly', today),
        ms = budgetPeriodStart('monthly', today);
    final weekStart = _ymd(ws), weekEnd = _ymd(budgetPeriodEnd('weekly', ws));
    final monthStart = _ymd(ms),
        monthEnd = _ymd(budgetPeriodEnd('monthly', ms));
    return db
        .customSelect(
          '''
          SELECT b.*, (
            SELECT COALESCE(SUM(COALESCE(t.amount_base_minor,
                     CASE WHEN t.currency = ?1 THEN t.amount_minor END)), 0)
              FROM transactions t
              LEFT JOIN categories c ON c.id = t.category_id
             WHERE t.deleted_at IS NULL AND t.kind = 'expense'
               AND t.local_date >= CASE b.period WHEN 'weekly' THEN ?2 ELSE ?4 END
               AND t.local_date <  CASE b.period WHEN 'weekly' THEN ?3 ELSE ?5 END
               AND (b.category_id IS NULL OR t.category_id = b.category_id
                    OR c.parent_id = b.category_id)
          ) AS spent
          FROM budgets b WHERE b.deleted_at IS NULL
          ORDER BY b.category_id IS NOT NULL, b.period, b.amount_minor DESC
          ''',
          variables: [
            Variable.withString(baseCurrency),
            Variable.withString(weekStart),
            Variable.withString(weekEnd),
            Variable.withString(monthStart),
            Variable.withString(monthEnd),
          ],
          readsFrom: {db.budgets, db.transactions, db.categories},
        )
        .watch()
        .asyncMap(
          (rows) async => [
            for (final r in rows)
              () {
                final b = db.budgets.map(r.data);
                final weekly = b.period == 'weekly';
                return BudgetProgress(
                  budget: b,
                  spentMinor: r.read<int>('spent'),
                  periodStart: weekly ? weekStart : monthStart,
                  periodEnd: weekly ? weekEnd : monthEnd,
                );
              }(),
          ],
        );
  }

  static String _levels(List<int> levels) {
    final clean = {...levels.where((l) => l >= 1 && l <= 200)}.toList()..sort();
    return clean.join(',');
  }

  // ------------------------------------------------------------------- goals

  Future<Goal?> getGoal(String id) =>
      (db.select(db.goals)..where((g) => g.id.equals(id))).getSingleOrNull();

  Future<Goal> createGoal({
    required String name,
    required int targetMinor,
    String? deadline,
    String icon = '',
    String color = '',
  }) {
    final row = GoalsCompanion.insert(
      id: _newId(),
      name: name.trim(),
      targetMinor: targetMinor,
      deadline: Value(deadline),
      icon: Value(icon),
      color: Value(color),
      updatedAt: _stamp(),
    );
    return _write(
      Entity.goal,
      row.id.value,
      row.updatedAt.value,
      () => db.into(db.goals).insertReturning(row),
    );
  }

  Future<Goal> updateGoal(Goal g) {
    final changed = g.copyWith(name: g.name.trim(), updatedAt: _stamp());
    return _write(Entity.goal, g.id, changed.updatedAt, () async {
      await db.update(db.goals).replace(changed);
      return changed;
    });
  }

  /// Deletes the goal and its contributions.
  Future<void> deleteGoal(String id) async {
    await db.transaction(() async {
      final at = _stamp();
      final contributions = await (db.select(
        db.goalContributions,
      )..where((c) => c.goalId.equals(id) & c.deletedAt.isNull())).get();
      for (final c in contributions) {
        await _softDelete(
          db.goalContributions,
          Entity.goalContribution,
          c.id,
          at,
        );
      }
      await _softDelete(db.goals, Entity.goal, id, at);
    });
    onLocalWrite?.call();
  }

  Future<GoalContribution> addContribution({
    required String goalId,
    required int amountMinor,
    required DateTime date,
    String note = '',
  }) {
    final row = GoalContributionsCompanion.insert(
      id: _newId(),
      goalId: goalId,
      amountMinor: amountMinor,
      localDate: localDateOf(date),
      note: Value(note.trim()),
      updatedAt: _stamp(),
    );
    return _write(
      Entity.goalContribution,
      row.id.value,
      row.updatedAt.value,
      () => db.into(db.goalContributions).insertReturning(row),
    );
  }

  Future<void> deleteContribution(String id) async {
    await db.transaction(
      () => _softDelete(
        db.goalContributions,
        Entity.goalContribution,
        id,
        _stamp(),
      ),
    );
    onLocalWrite?.call();
  }

  Stream<List<GoalContribution>> watchContributions(String goalId) =>
      (db.select(db.goalContributions)
            ..where((c) => c.goalId.equals(goalId) & c.deletedAt.isNull())
            ..orderBy([
              (c) => OrderingTerm.desc(c.localDate),
              (c) => OrderingTerm.desc(c.updatedAt),
            ]))
          .watch();

  /// Every live goal with the money saved towards it.
  Stream<List<GoalProgress>> watchGoalProgress() => db
      .customSelect(
        '''
        SELECT g.*, COALESCE((SELECT SUM(c.amount_minor) FROM goal_contributions c
                               WHERE c.goal_id = g.id AND c.deleted_at IS NULL), 0) AS saved
          FROM goals g WHERE g.deleted_at IS NULL
         ORDER BY g.archived, g.deadline IS NULL, g.deadline, g.name
        ''',
        readsFrom: {db.goals, db.goalContributions},
      )
      .watch()
      .map(
        (rows) => [
          for (final r in rows)
            GoalProgress(
              goal: db.goals.map(r.data),
              savedMinor: r.read<int>('saved'),
            ),
        ],
      );

  // --------------------------------------------------------------- recurring

  Stream<List<RecurringRule>> watchRecurringRules() =>
      (db.select(db.recurringRules)
            ..where((r) => r.deletedAt.isNull())
            ..orderBy([
              (r) => OrderingTerm.desc(r.active),
              (r) => OrderingTerm(expression: r.startDate),
            ]))
          .watch();

  Future<RecurringRule?> getRecurringRule(String id) => (db.select(
    db.recurringRules,
  )..where((r) => r.id.equals(id))).getSingleOrNull();

  Future<RecurringRule> createRecurringRule({
    required String kind,
    required String accountId,
    required String categoryId,
    required int amountMinor,
    required String currency,
    required String frequency,
    int every = 1,
    required String startDate,
    String? endDate,
    int remindDaysBefore = 0,
    String note = '',
  }) {
    final row = RecurringRulesCompanion.insert(
      id: _newId(),
      kind: kind,
      accountId: accountId,
      categoryId: categoryId,
      amountMinor: amountMinor,
      currency: currency,
      note: Value(note.trim()),
      frequency: frequency,
      every: Value(every),
      startDate: startDate,
      endDate: Value(endDate),
      remindDaysBefore: Value(remindDaysBefore),
      updatedAt: _stamp(),
    );
    return _write(
      Entity.recurringRule,
      row.id.value,
      row.updatedAt.value,
      () => db.into(db.recurringRules).insertReturning(row),
    );
  }

  Future<RecurringRule> updateRecurringRule(RecurringRule r) {
    final changed = r.copyWith(note: r.note.trim(), updatedAt: _stamp());
    return _write(Entity.recurringRule, r.id, changed.updatedAt, () async {
      await db.update(db.recurringRules).replace(changed);
      return changed;
    });
  }

  /// Deletes the rule. Bills already created stay (they happened).
  Future<void> deleteRecurringRule(String id) async {
    await db.transaction(
      () => _softDelete(db.recurringRules, Entity.recurringRule, id, _stamp()),
    );
    onLocalWrite?.call();
  }

  /// Creates the bills that are due up to [today] (a local date) and do not
  /// exist yet, with the same fixed ids the server uses, so the two copies
  /// merge. A bill the user deleted is never created again. Rules whose
  /// account was deleted are skipped. Returns how many were created.
  Future<int> generateDueBills(DateTime today) async {
    final rules = await (db.select(
      db.recurringRules,
    )..where((r) => r.active.equals(true) & r.deletedAt.isNull())).get();
    final liveAccounts = {
      for (final a in await (db.select(
        db.accounts,
      )..where((a) => a.deletedAt.isNull())).get())
        a.id,
    };
    var created = 0;
    await db.transaction(() async {
      for (final r in rules) {
        if (!liveAccounts.contains(r.accountId)) continue;
        final existing = {
          for (final t in await (db.select(
            db.transactions,
          )..where((t) => t.recurringId.equals(r.id))).get())
            t.occurrenceDate,
        };
        final schedule = Recurrence(
          frequency: r.frequency,
          every: r.every,
          start: DateTime.parse(r.startDate),
          end: r.endDate == null ? null : DateTime.parse(r.endDate!),
        );
        for (final day in schedule.dates(schedule.start, today)) {
          final date = ymd(day);
          if (existing.contains(date)) continue;
          final at = _stamp();
          final id = occurrenceId(r.id, day);
          await db
              .into(db.transactions)
              .insert(
                TransactionsCompanion.insert(
                  id: id,
                  kind: r.kind,
                  accountId: r.accountId,
                  categoryId: Value(r.categoryId),
                  amountMinor: r.amountMinor,
                  currency: r.currency,
                  occurredAt: DateTime(
                    day.year,
                    day.month,
                    day.day,
                    12,
                  ).toUtc(),
                  localDate: date,
                  note: Value(r.note),
                  recurringId: Value(r.id),
                  occurrenceDate: Value(date),
                  updatedAt: at,
                ),
                mode: InsertMode.insertOrIgnore,
              );
          await _queue(Entity.transaction, id, at);
          created++;
        }
      }
    });
    if (created > 0) onLocalWrite?.call();
    return created;
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

/// "80,100" -> [80, 100]; bad parts are ignored.
List<int> parseLevels(String s) => [
  for (final p in s.split(',')) ?int.tryParse(p.trim()),
];
