import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/app_icon.dart';
import '../../../core/database/app_database.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/amount_text.dart';
import '../../../core/widgets/panda_mascot.dart';
import '../../auth/application/auth_controller.dart';
import '../../budgets/presentation/budget_tile.dart';
import '../../ledger/application/ledger_providers.dart';
import '../../ledger/data/ledger_store.dart';
import '../../ledger/presentation/ledger_style.dart';
import '../../ledger/presentation/transaction_tile.dart';
import '../../sync/sync_controller.dart';
import '../domain/penny_greeting.dart';

/// Home screen: total balance, this month's money in and out, accounts
/// and the latest transactions. All from the local database (works offline).
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final user = auth is SignedIn ? auth.user : null;
    final currency = user?.baseCurrency ?? 'USD';
    final month = localDateOf(DateTime.now()).substring(0, 7);
    final totals =
        ref
            .watch(monthTotalsProvider((month: month, currency: currency)))
            .value ??
        const MonthTotals();
    final accounts = (ref.watch(accountsProvider).value ?? const <Account>[])
        .where((a) => !a.archived)
        .toList();
    final balances = ref.watch(balancesProvider).value ?? const <String, int>{};
    final recent = ref.watch(transactionsProvider(5)).value ?? const [];
    final budgets =
        ref.watch(budgetProgressProvider(currency)).value ?? const [];

    // Accounts in other currencies need exchange rates (Milestone 6), so the
    // total covers the main currency only and says so.
    var total = 0;
    var otherCurrencies = 0;
    for (final a in accounts) {
      if (a.currency == currency) {
        total += balances[a.id] ?? a.openingBalanceMinor;
      } else {
        otherCurrencies++;
      }
    }

    final greeting = pennyGreetingForMonth(
      incomeMinor: totals.incomeMinor,
      spentMinor: totals.expenseMinor,
    );

    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(user == null ? 'pennyWise' : 'Hi, ${user.displayName}'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(syncControllerProvider.notifier).syncNow();
          try {
            await ref.read(authControllerProvider.notifier).refreshUser();
          } on ApiException {
            // Offline: keep showing what we have.
          }
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            Spacing.lg,
            Spacing.lg,
            96,
          ),
          children: [
            _PennyCard(greeting: greeting),
            const SizedBox(height: Spacing.md),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total balance', style: muted),
                    const SizedBox(height: Spacing.sm),
                    AmountText(
                      minor: total,
                      currency: currency,
                      signed: false,
                      large: true,
                      style: theme.textTheme.displaySmall,
                    ),
                    if (otherCurrencies > 0) ...[
                      const SizedBox(height: Spacing.sm),
                      Text(
                        '$currency accounts only. $otherCurrencies '
                        '${otherCurrencies == 1 ? 'account' : 'accounts'} in other '
                        'currencies not included yet.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),
            Row(
              children: [
                Expanded(
                  child: _MonthFigure(
                    label: 'Income this month',
                    minor: totals.incomeMinor,
                    currency: currency,
                    labelStyle: muted,
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: _MonthFigure(
                    label: 'Spent this month',
                    minor: -totals.expenseMinor,
                    currency: currency,
                    labelStyle: muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.xl),
            if (budgets.isNotEmpty) ...[
              _SectionHeader(
                title: 'Budgets',
                action: 'Manage',
                onAction: () => context.push(Routes.budgets),
              ),
              Card(
                child: Column(
                  children: [
                    for (final b in budgets.take(3))
                      BudgetTile(progress: b, currency: currency),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.xl),
            ],
            _SectionHeader(
              title: 'Accounts',
              action: 'Manage',
              onAction: () => context.push(Routes.accounts),
            ),
            if (accounts.isEmpty)
              Card(
                child: ListTile(
                  leading: const AppIcon(HugeIcons.strokeRoundedWallet02),
                  title: const Text('Add your first account'),
                  subtitle: const Text(
                    'Cash, a bank account, a card or a mobile wallet.',
                  ),
                  onTap: () => context.push(Routes.newAccount),
                ),
              )
            else
              Card(
                child: Column(
                  children: [
                    for (final a in accounts)
                      ListTile(
                        leading: AppIcon(accountIcon(a.type)),
                        title: Text(a.name),
                        trailing: AmountText(
                          minor: balances[a.id] ?? a.openingBalanceMinor,
                          currency: a.currency,
                          signed: false,
                          style: theme.textTheme.titleMedium,
                        ),
                        onTap: () => context.push(Routes.editAccount(a.id)),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: Spacing.xl),
            _SectionHeader(
              title: 'Recent',
              action: 'See all',
              onAction: () => context.go(Routes.transactions),
            ),
            if (recent.isEmpty)
              Text(
                'Nothing yet. Tap + to add income or an expense.',
                style: muted,
              )
            else
              Card(
                child: Column(
                  children: [
                    for (final t in recent) TransactionTile(transaction: t),
                  ],
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        // Tabs stay alive side by side: no shared hero animation tag.
        heroTag: null,
        tooltip: 'Add transaction',
        onPressed: () => context.push(
          accounts.isEmpty ? Routes.newAccount : Routes.newTransaction(),
        ),
        child: const AppIcon(HugeIcons.strokeRoundedPlusSign),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.action,
    required this.onAction,
  });

  final String title;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        TextButton(onPressed: onAction, child: Text(action)),
      ],
    );
  }
}

/// Penny the panda with a short note about the month.
class _PennyCard extends StatelessWidget {
  const _PennyCard({required this.greeting});

  final PennyGreeting greeting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.sm,
          Spacing.sm,
          Spacing.lg,
          Spacing.sm,
        ),
        child: Row(
          children: [
            PandaMascot(mood: greeting.mood, size: 88),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(greeting.message, style: theme.textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthFigure extends StatelessWidget {
  const _MonthFigure({
    required this.label,
    required this.minor,
    required this.currency,
    this.labelStyle,
  });

  final String label;
  final int minor;
  final String currency;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: labelStyle),
            const SizedBox(height: Spacing.xs),
            AmountText(
              minor: minor,
              currency: currency,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      ),
    );
  }
}
