import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/app_icon.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/amount_text.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/panda_mascot.dart';
import '../application/ledger_providers.dart';
import 'ledger_style.dart';

/// All accounts with their current balance.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    final balances = ref.watch(balancesProvider).value ?? const {};
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => context.push(Routes.newAccount),
        icon: const AppIcon(HugeIcons.strokeRoundedPlusSign),
        label: const Text('Add account'),
      ),
      body: accounts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load accounts: $e')),
        data: (list) => list.isEmpty
            ? const EmptyState(
                mascot: PandaMood.wave,
                icon: HugeIcons.strokeRoundedWallet01,
                title: 'No accounts yet',
                message: 'Add where your money lives: cash, a bank account, a card or a mobile wallet.',
              )
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(indent: 72),
                itemBuilder: (context, i) {
                  final a = list[i];
                  return ListTile(
                    leading: IconBadge(
                      icon: accountIcon(a.type),
                      color: scheme.primary,
                    ),
                    title: Text(a.name),
                    subtitle: Text(
                      '${accountTypes[a.type]?.$1 ?? a.type} · ${a.currency}',
                    ),
                    trailing: AmountText(
                      minor: balances[a.id] ?? a.openingBalanceMinor,
                      currency: a.currency,
                      signed: false,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    onTap: () => context.push(Routes.editAccount(a.id)),
                  );
                },
              ),
      ),
    );
  }
}

/// Spacing helper kept here so the list and form match.
const accountFormPadding = EdgeInsets.all(Spacing.lg);
