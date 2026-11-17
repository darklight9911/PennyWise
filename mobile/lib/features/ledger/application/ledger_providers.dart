import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/local_database.dart';
import '../../auth/application/auth_controller.dart';
import '../../../core/database/app_database.dart';
import '../data/ledger_store.dart';

/// The signed-in user's id, or null.
final signedInUserIdProvider = Provider<String?>((ref) {
  final auth = ref.watch(authControllerProvider);
  return auth is SignedIn ? auth.user.id : null;
});

/// The ledger of the signed-in user. Rebuilt when another user signs in,
/// so a screen can never read the previous user's database.
final ledgerStoreProvider = FutureProvider<LedgerStore>((ref) async {
  final userId = ref.watch(signedInUserIdProvider);
  if (userId == null) throw StateError('not signed in');
  final db = await ref.watch(localDatabaseProvider).claimFor(userId);
  return LedgerStore(db);
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

final monthTotalsProvider =
    StreamProvider.family<MonthTotals, ({String month, String currency})>((
      ref,
      key,
    ) async* {
      final store = await ref.watch(ledgerStoreProvider.future);
      yield* store.watchMonthTotals(key.month, key.currency);
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
