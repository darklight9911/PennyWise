import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/amount_text.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/panda_mascot.dart';
import '../../ledger/application/ledger_providers.dart';
import '../../ledger/data/ledger_store.dart';
import '../../ledger/presentation/day_labels.dart';
import '../domain/recurrence.dart';

/// Bills and income that repeat (rent, salary, subscriptions).
class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(recurringRulesProvider);
    final categories = ref.watch(categoryIndexProvider).value ?? const {};

    return Scaffold(
      appBar: AppBar(title: const Text('Recurring')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => context.push(Routes.newRecurring),
        icon: const AppIcon(HugeIcons.strokeRoundedPlusSign),
        label: const Text('Add recurring'),
      ),
      body: rules.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load: $e')),
        data: (list) => list.isEmpty
            ? const EmptyState(
                mascot: PandaMood.thinking,
                icon: HugeIcons.strokeRoundedRepeat,
                title: 'Nothing recurring yet',
                message:
                    'Add rent, salary or a subscription once. pennyWise then '
                    'adds it on each due date and can remind you before.',
              )
            : ListView(
                padding: const EdgeInsets.only(top: 8, bottom: 96),
                children: [
                  for (final r in list)
                    _RuleTile(rule: r, category: categories[r.categoryId]),
                ],
              ),
      ),
    );
  }
}

class _RuleTile extends StatelessWidget {
  const _RuleTile({required this.rule, required this.category});

  final RecurringRule rule;
  final Category? category;

  @override
  Widget build(BuildContext context) {
    final r = rule;
    final now = DateTime.now();
    final next = r.active ? ruleOf(r).next(now) : null;
    final when = !r.active
        ? 'Paused'
        : next == null
        ? 'Ended'
        : 'Next ${dayLabel(ymd(next), now)}';
    final name = r.note.isNotEmpty ? r.note : (category?.name ?? 'Recurring');
    return ListTile(
      leading: AppIcon(
        r.active ? HugeIcons.strokeRoundedRepeat : HugeIcons.strokeRoundedPause,
      ),
      title: Text(name),
      subtitle: Text('${frequencyLabel(r.frequency, r.every)} · $when'),
      trailing: TrailingAmount(
        child: AmountText(
          minor: r.kind == TxKind.expense ? -r.amountMinor : r.amountMinor,
          currency: r.currency,
          signed: true,
        ),
      ),
      onTap: () => context.push(Routes.editRecurring(r.id)),
    );
  }
}

/// The schedule of a stored rule.
Recurrence ruleOf(RecurringRule r) => Recurrence(
  frequency: r.frequency,
  every: r.every,
  start: DateTime.parse(r.startDate),
  end: r.endDate == null ? null : DateTime.parse(r.endDate!),
);

/// "Every month", "Every 2 weeks".
String frequencyLabel(String frequency, int every) {
  final unit = switch (frequency) {
    'daily' => 'day',
    'weekly' => 'week',
    'yearly' => 'year',
    _ => 'month',
  };
  return every <= 1 ? 'Every $unit' : 'Every $every ${unit}s';
}
