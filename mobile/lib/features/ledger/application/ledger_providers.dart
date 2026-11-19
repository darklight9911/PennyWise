import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/local_database.dart';
import '../../auth/application/auth_controller.dart';
import '../../../core/database/app_database.dart';
import '../../receipts/data/receipt_files.dart';
import '../../receipts/data/receipt_store.dart';
import '../data/ledger_store.dart';

/// Whose data the phone shows: the signed-in user's id, [LocalDatabase.guestOwner]
/// without an account, or null while starting up.
final dataOwnerProvider = Provider<String?>((ref) {
  return switch (ref.watch(authControllerProvider)) {
    SignedIn(:final user) => user.id,
    Guest() => LocalDatabase.guestOwner,
    _ => null,
  };
});

/// The ledger on this phone. Rebuilt when the owner changes, so a screen
/// can never read the previous user's database.
final ledgerStoreProvider = FutureProvider<LedgerStore>((ref) async {
  final owner = ref.watch(dataOwnerProvider);
  ref.watch(localDataEpochProvider);
  if (owner == null) throw StateError('starting up');
  final db = await ref.watch(localDatabaseProvider).claimFor(owner);
  final store = LedgerStore(db);
  if (owner == LocalDatabase.guestOwner) await store.seedDefaultCategories();
  return store;
});

// Live views of the local data. They update by themselves whenever the
// database changes (local edits or rows arriving through sync).

final accountsProvider = StreamProvider<List<Account>>((ref) async* {
  final store = await ref.watch(ledgerStoreProvider.future);
  yield* store.watchAccounts();
});

final balancesProvider = StreamProvider<Map<String, int>>((ref) async* {
  final store = await ref.watch(ledgerStoreProvider.future);
  yield* store.watchBalances();
});

/// Categories of one kind ('income' / 'expense'), or all with null.
final categoriesProvider = StreamProvider.family<List<Category>, String?>((
  ref,
  kind,
) async* {
  final store = await ref.watch(ledgerStoreProvider.future);
  yield* store.watchCategories(kind: kind);
});

/// Every category by id, deleted ones included (old transactions show names).
final categoryIndexProvider = StreamProvider<Map<String, Category>>((
  ref,
) async* {
  final store = await ref.watch(ledgerStoreProvider.future);
  yield* store.watchCategoryIndex();
});

/// Newest first; limit null = all.
final transactionsProvider =
    StreamProvider.family<List<MoneyTransaction>, int?>((ref, limit) async* {
      final store = await ref.watch(ledgerStoreProvider.future);
      yield* store.watchTransactions(limit: limit);
    });

/// Transactions recorded on a single calendar date (YYYY-MM-DD), newest first.
final dayTransactionsProvider =
    StreamProvider.family<List<MoneyTransaction>, String>((ref, date) async* {
      final store = await ref.watch(ledgerStoreProvider.future);
      yield* store.watchTransactions(localDate: date);
    });

final monthTotalsProvider =
    StreamProvider.family<MonthTotals, ({String month, String currency})>((
      ref,
      key,
    ) async* {
      final store = await ref.watch(ledgerStoreProvider.future);
      yield* store.watchMonthTotals(key.month, key.currency);
    });

final dayTotalsProvider =
    StreamProvider.family<MonthTotals, ({String date, String currency})>((
      ref,
      key,
    ) async* {
      final store = await ref.watch(ledgerStoreProvider.future);
      yield* store.watchDayTotals(key.date, key.currency);
    });

final pendingChangesProvider = StreamProvider<int>((ref) async* {
  final store = await ref.watch(ledgerStoreProvider.future);
  yield* store.watchPendingCount();
});

/// Every budget with its spending in the current week or month, in the
/// given main currency.
final budgetProgressProvider =
    StreamProvider.family<List<BudgetProgress>, String>((ref, currency) async* {
      final store = await ref.watch(ledgerStoreProvider.future);
      yield* store.watchBudgetProgress(currency, DateTime.now());
    });

final goalProgressProvider = StreamProvider<List<GoalProgress>>((ref) async* {
  final store = await ref.watch(ledgerStoreProvider.future);
  yield* store.watchGoalProgress();
});

final contributionsProvider =
    StreamProvider.family<List<GoalContribution>, String>((ref, goalId) async* {
      final store = await ref.watch(ledgerStoreProvider.future);
      yield* store.watchContributions(goalId);
    });

final recurringRulesProvider = StreamProvider<List<RecurringRule>>((
  ref,
) async* {
  final store = await ref.watch(ledgerStoreProvider.future);
  yield* store.watchRecurringRules();
});

/// Report: totals per top-level category for a date range.
final categoryTotalsProvider =
    StreamProvider.family<
      List<CategoryTotal>,
      ({String from, String to, String base, String kind})
    >((ref, k) async* {
      final store = await ref.watch(ledgerStoreProvider.future);
      yield* store.watchCategoryTotals(
        from: k.from,
        to: k.to,
        baseCurrency: k.base,
        kind: k.kind,
      );
    });

/// Report: money in and out per month.
final monthlyFlowProvider =
    StreamProvider.family<
      List<MonthFlow>,
      ({String from, String to, String base})
    >((ref, k) async* {
      final store = await ref.watch(ledgerStoreProvider.future);
      yield* store.watchMonthlyFlow(
        fromMonth: k.from,
        toMonth: k.to,
        baseCurrency: k.base,
      );
    });

/// Receipt photos on this phone (the same database as the ledger).
final receiptStoreProvider = FutureProvider<ReceiptStore>((ref) async {
  final ledger = await ref.watch(ledgerStoreProvider.future);
  return ReceiptStore(
    ledger.db,
    ref.watch(receiptFilesProvider),
    onChange: () => ledger.onLocalWrite?.call(),
  );
});

/// The live receipts of one transaction.
final receiptsProvider = StreamProvider.family<List<Receipt>, String>((
  ref,
  transactionId,
) async* {
  final store = await ref.watch(receiptStoreProvider.future);
  yield* store.watch(transactionId);
});
