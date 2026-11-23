import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/amount_text.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/panda_mascot.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../ledger/application/ledger_providers.dart';
import '../../ledger/data/ledger_store.dart';
import 'due_style.dart';

/// Money the user owes and money owed to them, open ones by due date.
class DuesScreen extends ConsumerStatefulWidget {
  const DuesScreen({super.key, this.initialDirection = DueDirection.owedToMe});

  final String initialDirection;

  @override
  ConsumerState<DuesScreen> createState() => _DuesScreenState();
}

class _DuesScreenState extends ConsumerState<DuesScreen> {
  late String _direction = widget.initialDirection;
  bool _showSettled = false;

  @override
  Widget build(BuildContext context) {
    final dues = ref.watch(duesProvider);
    final today = todayYmd();
    final pad = ResponsiveLayout.horizontalPadding(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Dues')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => context.push(Routes.newDueFor(_direction)),
        icon: const AppIcon(HugeIcons.strokeRoundedPlusSign),
        label: const Text('Add due'),
      ),
      body: ResponsiveBody(
        child: dues.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load dues: $e')),
          data: (all) {
            final mine = all
                .where((p) => p.due.direction == _direction)
                .toList();
            final open = mine.where((p) => !p.settled).toList();
            final overdue = open
                .where((p) => p.status(today) == DueStatus.overdue)
                .toList();
            final upcoming = open
                .where(
                  (p) =>
                      p.status(today) == DueStatus.open &&
                      p.due.dueDate != null,
                )
                .toList();
            final noDate = open.where((p) => p.due.dueDate == null).toList();
            final settled = mine.where((p) => p.settled).toList();
            final owed = _direction == DueDirection.owedToMe;

            return ListView(
              padding: EdgeInsets.fromLTRB(pad, Spacing.md, pad, 88),
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: DueDirection.owedToMe,
                      label: Text('Owed to me'),
                    ),
                    ButtonSegment(
                      value: DueDirection.iOwe,
                      label: Text('I owe'),
                    ),
                  ],
                  selected: {_direction},
                  onSelectionChanged: (s) =>
                      setState(() => _direction = s.single),
                ),
                const SizedBox(height: Spacing.md),
                if (mine.isEmpty)
                  EmptyState(
                    mascot: PandaMood.thinking,
                    icon: HugeIcons.strokeRoundedHandshake,
                    title: owed ? 'Nobody owes you' : 'You owe nobody',
                    message: owed
                        ? 'Lent money to a friend, or waiting to be paid for work? '
                              'Add it here and mark it received when it comes back.'
                        : 'Borrowed money, or a bill to pay later? Add it here and '
                              'mark it paid when you settle it.',
                  )
                else ...[
                  _Summary(open: open, overdue: overdue.length, owed: owed),
                  _Section(title: 'Overdue', items: overdue, today: today),
                  _Section(title: 'Upcoming', items: upcoming, today: today),
                  _Section(title: 'No due date', items: noDate, today: today),
                  if (settled.isNotEmpty) ...[
                    const SizedBox(height: Spacing.sm),
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _showSettled = !_showSettled),
                      icon: AppIcon(
                        _showSettled
                            ? HugeIcons.strokeRoundedArrowUp01
                            : HugeIcons.strokeRoundedArrowDown01,
                        size: 18,
                      ),
                      label: Text(
                        '${_showSettled ? 'Hide' : 'Show'} settled (${settled.length})',
                      ),
                    ),
                    if (_showSettled)
                      _Section(title: null, items: settled, today: today),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// "Left to get back: 1200.00 USD · 50.00 EUR · 2 overdue".
class _Summary extends StatelessWidget {
  const _Summary({
    required this.open,
    required this.overdue,
    required this.owed,
  });

  final List<DueProgress> open;
  final int overdue;
  final bool owed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byCurrency = <String, int>{};
    for (final p in open) {
      byCurrency[p.due.currency] =
          (byCurrency[p.due.currency] ?? 0) + p.leftMinor;
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              owed ? 'Left to get back' : 'Left to pay',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            if (byCurrency.isEmpty)
              Text('All settled', style: theme.textTheme.titleMedium)
            else
              Wrap(
                spacing: Spacing.md,
                runSpacing: Spacing.xs,
                children: [
                  for (final e in byCurrency.entries)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        moneyLabel(e.value, e.key),
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                ],
              ),
            if (overdue > 0) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                '$overdue overdue',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.items,
    required this.today,
  });

  final String? title;
  final List<DueProgress> items;
  final String today;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, Spacing.lg, 0, Spacing.xs),
            child: Text(title!, style: Theme.of(context).textTheme.titleSmall),
          ),
        Card(
          child: Column(
            children: [
              for (final p in items) DueTile(progress: p, today: today),
            ],
          ),
        ),
      ],
    );
  }
}

/// One due: person, kind, when, amount left and progress.
class DueTile extends StatelessWidget {
  const DueTile({super.key, required this.progress, required this.today});

  final DueProgress progress;
  final String today;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final theme = Theme.of(context);
    final when = dueWhenLabel(p, today);
    return ListTile(
      leading: AppIcon(
        dueKindIcon(p.due.kind),
        color: theme.colorScheme.primary,
      ),
      title: Text(p.due.person, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '${dueKindLabel(p.due.kind)} · '),
                TextSpan(
                  text: when,
                  style: TextStyle(color: dueWhenColor(context, p, today)),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (p.paidMinor > 0 && !p.settled) ...[
            const SizedBox(height: Spacing.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: p.fraction,
                minHeight: 5,
                backgroundColor: theme.colorScheme.outlineVariant,
                semanticsLabel:
                    '${p.due.person}, ${(p.fraction * 100).round()} percent paid',
              ),
            ),
          ],
        ],
      ),
      trailing: TrailingAmount(
        child: AmountText(
          minor: p.settled ? p.due.amountMinor : p.leftMinor,
          currency: p.due.currency,
          signed: false,
          style: theme.textTheme.titleMedium,
        ),
      ),
      onTap: () => context.push(Routes.due(p.due.id)),
    );
  }
}
