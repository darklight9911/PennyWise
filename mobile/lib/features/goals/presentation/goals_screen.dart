import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/finance_colors.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/panda_mascot.dart';
import '../../auth/application/auth_controller.dart';
import '../../ledger/application/ledger_providers.dart';
import '../../ledger/data/ledger_store.dart';
import '../../ledger/presentation/day_labels.dart';

/// Savings goals with how much is saved.
class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(baseCurrencyProvider);
    final goals = ref.watch(goalProgressProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Goals')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => context.push(Routes.newGoal),
        icon: const AppIcon(HugeIcons.strokeRoundedPlusSign),
        label: const Text('Add goal'),
      ),
      body: goals.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load goals: $e')),
        data: (list) => list.isEmpty
            ? const EmptyState(
                mascot: PandaMood.happy,
                icon: HugeIcons.strokeRoundedPiggyBank,
                title: 'No goals yet',
                message:
                    'Saving for a laptop, a trip or a rainy day? Add a goal and '
                    'put money towards it whenever you can.',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  Spacing.lg,
                  Spacing.lg,
                  96,
                ),
                children: [
                  for (final g in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.md),
                      child: GoalCard(progress: g, currency: currency),
                    ),
                ],
              ),
      ),
    );
  }
}

/// One goal: name, progress bar, saved / target, deadline.
class GoalCard extends StatelessWidget {
  const GoalCard({super.key, required this.progress, required this.currency});

  final GoalProgress progress;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final theme = Theme.of(context);
    final income = context.financeColors.incomeText;
    final pct = (p.fraction * 100).floor().clamp(0, 999);
    final deadline = p.goal.deadline;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.card),
        onTap: () => context.push(Routes.goal(p.goal.id)),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      p.goal.name,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (p.reached)
                    Text(
                      'Reached',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: income,
                      ),
                    )
                  else
                    Text('$pct%', style: theme.textTheme.labelLarge),
                ],
              ),
              const SizedBox(height: Spacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: p.fraction.clamp(0, 1).toDouble(),
                  minHeight: 8,
                  color: p.reached ? income : theme.colorScheme.primary,
                  backgroundColor: theme.colorScheme.outlineVariant,
                  semanticsLabel: '${p.goal.name} goal, $pct percent saved',
                  semanticsValue: '${pct.clamp(0, 100)}',
                ),
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                '${formatMinor(p.savedMinor, currency)} saved of '
                '${formatMinor(p.goal.targetMinor, currency)}'
                '${deadline == null ? '' : ' · by ${dayLabel(deadline, DateTime.now())}'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
