import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/finance_colors.dart';
import '../../../core/utils/money.dart';
import '../../ledger/application/ledger_providers.dart';
import '../../ledger/data/ledger_store.dart';

/// Amber used when a budget is at 80 % or more (dark enough for text).
const budgetWarning = AppColors.warning;

/// One budget: name, progress bar and what is left.
class BudgetTile extends ConsumerWidget {
  const BudgetTile({super.key, required this.progress, required this.currency});

  final BudgetProgress progress;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = progress;
    final theme = Theme.of(context);
    final categories = ref.watch(categoryIndexProvider).value ?? const {};
    final name = p.budget.categoryId == null
        ? 'All spending'
        : categories[p.budget.categoryId]?.name ?? 'Category';
    final when = p.budget.period == 'weekly' ? 'this week' : 'this month';

    final Color color;
    final String status;
    if (p.over) {
      color = context.financeColors.expense;
      status = '${formatMinor(-p.leftMinor, currency)} over $when';
    } else {
      color = p.fraction >= 0.8
          ? context.financeColors.warning
          : theme.colorScheme.primary;
      status =
          '${formatMinor(p.leftMinor, currency)} left of '
          '${formatMinor(p.budget.amountMinor, currency)} $when';
    }

    return InkWell(
      onTap: () => context.push(Routes.editBudget(p.budget.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(name, style: theme.textTheme.titleMedium)),
                Text(
                  '${(p.fraction * 100).floor()}%',
                  style: theme.textTheme.titleSmall?.copyWith(color: color),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: p.fraction.clamp(0, 1).toDouble(),
                minHeight: 8,
                color: color,
                backgroundColor: theme.colorScheme.outlineVariant,
                // Screen readers: the value must be a number from 0 to 100;
                // the real share (which can pass 100) is in the label.
                semanticsLabel:
                    '$name budget, ${(p.fraction * 100).floor()} percent used',
                semanticsValue: '${(p.fraction * 100).floor().clamp(0, 100)}',
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              status,
              style: theme.textTheme.bodySmall?.copyWith(
                color: p.over ? color : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
