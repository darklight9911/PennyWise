import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/panda_mascot.dart';
import '../../auth/application/auth_controller.dart';
import '../../ledger/application/ledger_providers.dart';
import 'budget_tile.dart';

/// All budgets with how much is used this week / month.
class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final currency = auth is SignedIn ? auth.user.baseCurrency : 'USD';
    final budgets = ref.watch(budgetProgressProvider(currency));

    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => context.push(Routes.newBudget),
        icon: const AppIcon(HugeIcons.strokeRoundedPlusSign),
        label: const Text('Add budget'),
      ),
      body: budgets.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load budgets: $e')),
        data: (list) => list.isEmpty
            ? const EmptyState(
                mascot: PandaMood.thinking,
                icon: HugeIcons.strokeRoundedTarget02,
                title: 'No budgets yet',
                message:
                    'Set a limit for a week or a month, for one category or '
                    'all spending. You get a message at 80 % and 100 %.',
              )
            : ListView(
                padding: const EdgeInsets.only(top: 8, bottom: 96),
                children: [
                  for (final p in list)
                    BudgetTile(progress: p, currency: currency),
                ],
              ),
      ),
    );
  }
}
