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
import '../../../core/utils/money.dart';
import '../../auth/application/auth_controller.dart';
import '../../currency/data/fx_rates.dart';
import '../../currency/presentation/recalculating_banner.dart';
import '../../budgets/presentation/budget_tile.dart';
import '../../ledger/application/ledger_providers.dart';
import '../../ledger/data/ledger_store.dart';
import '../../ledger/presentation/ledger_style.dart';
import '../../ledger/presentation/transaction_tile.dart';
import '../../sync/sync_controller.dart';
import '../../transactions/presentation/empty_transactions_stage.dart';
import '../domain/penny_greeting.dart';

/// Home screen: total balance, this month's money in and out, accounts
/// and the latest transactions. All from the local database (works offline).
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final currency = profile?.baseCurrency ?? 'USD';
    final today = localDateOf(DateTime.now());
    final totals =
        ref.watch(dayTotalsProvider((date: today, currency: currency))).value ??
        const MonthTotals();
    final accounts = (ref.watch(accountsProvider).value ?? const <Account>[])
        .where((a) => !a.archived)
        .toList();
    final balances = ref.watch(balancesProvider).value ?? const <String, int>{};
    final recent = ref.watch(dayTransactionsProvider(today)).value ?? const [];
    final budgets =
        ref.watch(budgetProgressProvider(currency)).value ?? const [];

    // Accounts in other currencies are converted at today's rate when it is
    // known (online); otherwise the total says which ones are left out.
    final rates = accounts.any((a) => a.currency != currency)
        ? ref.watch(fxRatesProvider(currency)).value
        : null;
    var total = 0;
    var converted = 0;
    var otherCurrencies = 0;
    for (final a in accounts) {
      final balance = balances[a.id] ?? a.openingBalanceMinor;
      final rate = rates?.rates[a.currency];
      if (a.currency == currency) {
        total += balance;
      } else if (rate != null) {
        total += convertMinor(balance, a.currency, currency, invertRate(rate));
        converted++;
      } else {
        otherCurrencies++;
      }
    }
    final recalculating = profile?.recalculating ?? false;

    final greeting = pennyGreetingForDay(
      incomeMinor: totals.incomeMinor,
      spentMinor: totals.expenseMinor,
    );

    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          profile == null || profile.name.isEmpty
              ? 'pennyWise'
              : 'Hi, ${profile.name}',
        ),
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
            if (recalculating) ...[
              const RecalculatingBanner(),
              const SizedBox(height: Spacing.md),
            ] else ...[
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
                      if (converted > 0 || otherCurrencies > 0) ...[
                        const SizedBox(height: Spacing.sm),
                        Text(
                          [
                            if (converted > 0)
                              '$converted ${converted == 1 ? 'account' : 'accounts'} '
                                  "converted at today's rate.",
                            if (otherCurrencies > 0)
                              '$otherCurrencies ${otherCurrencies == 1 ? 'account' : 'accounts'} '
                                  'in other currencies not included (no rate yet).',
                          ].join(' '),
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
                      label: 'Income today',
                      minor: totals.incomeMinor,
                      currency: currency,
                      labelStyle: muted,
                    ),
                  ),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: _MonthFigure(
                      label: 'Spent today',
                      minor: -totals.expenseMinor,
                      currency: currency,
                      labelStyle: muted,
                    ),
                  ),
                ],
              ),
              if (totals.missingRate > 0)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.sm),
                  child: Text(
                    '${totals.missingRate} ${totals.missingRate == 1 ? 'transaction' : 'transactions'} '
                    'in other currencies not counted yet: '
                    '${totals.missingRate == 1 ? 'it waits' : 'they wait'} for an exchange rate.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: Spacing.xl),
            ],
            if (budgets.isNotEmpty && !recalculating) ...[
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
                        trailing: TrailingAmount(
                          child: AmountText(
                            minor: balances[a.id] ?? a.openingBalanceMinor,
                            currency: a.currency,
                            signed: false,
                            style: theme.textTheme.titleMedium,
                          ),
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
              EmptyRecentCard(
                hasAccounts: accounts.isNotEmpty,
                onAction: () => context.push(
                  accounts.isEmpty
                      ? Routes.newAccount
                      : Routes.newTransaction(TxKind.expense),
                ),
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
