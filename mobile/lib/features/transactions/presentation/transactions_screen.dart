import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/app_icon.dart';
import '../../../core/database/app_database.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../ledger/application/ledger_providers.dart';
import '../../ledger/presentation/day_labels.dart';
import '../../ledger/presentation/transaction_tile.dart';
import '../../sync/sync_controller.dart';
import 'empty_transactions_stage.dart';

/// Every transaction, newest first, grouped by day.
class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactions = ref.watch(transactionsProvider(null));
    return Scaffold(
      appBar: AppBar(title: const Text('Transactions')),
      floatingActionButton: FloatingActionButton(
        // Tabs stay alive side by side: no shared hero animation tag.
        heroTag: null,
        tooltip: 'Add transaction',
        onPressed: () => context.push(Routes.newTransaction()),
        child: const AppIcon(HugeIcons.strokeRoundedPlusSign),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(syncControllerProvider.notifier).syncNow(),
        child: transactions.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load: $e')),
          data: (list) => list.isEmpty
              ? ListView(
                  // Scrollable, so pull-to-refresh works on the empty state.
                  children: const [EmptyTransactionsStage()],
                )
              : _GroupedList(transactions: list),
        ),
      ),
    );
  }
}

class _GroupedList extends StatelessWidget {
  const _GroupedList({required this.transactions});

  final List<MoneyTransaction> transactions;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final rows = <Widget>[];
    String? day;
    for (final t in transactions) {
      if (t.localDate != day) {
        day = t.localDate;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.lg,
              Spacing.lg,
              Spacing.xs,
            ),
            child: Text(
              dayLabel(day, now),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }
      rows.add(TransactionTile(transaction: t));
    }
    return ListView(padding: const EdgeInsets.only(bottom: 96), children: rows);
  }
}
