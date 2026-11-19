import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/amount_text.dart';
import '../../../core/widgets/app_icon.dart';
import '../../auth/application/auth_controller.dart';
import '../../ledger/application/ledger_providers.dart';
import '../../ledger/presentation/day_labels.dart';
import 'goals_screen.dart';

/// One goal: progress, add or take out money, and its history.
class GoalDetailScreen extends ConsumerWidget {
  const GoalDetailScreen({super.key, required this.goalId});

  final String goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(baseCurrencyProvider);
    final progress = (ref.watch(goalProgressProvider).value ?? const [])
        .where((g) => g.goal.id == goalId)
        .firstOrNull;
    final history = ref.watch(contributionsProvider(goalId)).value ?? const [];

    if (progress == null) {
      return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(progress.goal.name),
        actions: [
          IconButton(
            tooltip: 'Edit goal',
            icon: const AppIcon(HugeIcons.strokeRoundedPencilEdit02),
            onPressed: () async {
              final deleted = await context.push<bool>(Routes.editGoal(goalId));
              if (deleted == true && context.mounted) context.pop();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.lg),
        children: [
          GoalCard(progress: progress, currency: currency),
          const SizedBox(height: Spacing.md),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () =>
                      _changeMoney(context, ref, currency, add: true),
                  child: const Text('Add money'),
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(64, 48),
                  ),
                  onPressed: progress.savedMinor <= 0
                      ? null
                      : () => _changeMoney(context, ref, currency, add: false),
                  child: const Text('Take out'),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.xl),
          Text('History', style: Theme.of(context).textTheme.titleMedium),
          if (history.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: Spacing.sm),
              child: Text('Nothing yet.'),
            ),
          for (final c in history)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(dayLabel(c.localDate, DateTime.now())),
              subtitle: c.note.isEmpty ? null : Text(c.note),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TrailingAmount(
                    child: AmountText(minor: c.amountMinor, currency: currency),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    icon: const AppIcon(
                      HugeIcons.strokeRoundedDelete02,
                      size: 20,
                    ),
                    onPressed: () async {
                      final store = await ref.read(ledgerStoreProvider.future);
                      await store.deleteContribution(c.id);
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _changeMoney(
    BuildContext context,
    WidgetRef ref,
    String currency, {
    required bool add,
  }) async {
    final result = await showDialog<(int, String)>(
      context: context,
      builder: (_) => _MoneyDialog(add: add, currency: currency),
    );
    if (result == null) return;
    final (minor, note) = result;
    final store = await ref.read(ledgerStoreProvider.future);
    await store.addContribution(
      goalId: goalId,
      amountMinor: add ? minor : -minor,
      date: DateTime.now(),
      note: note,
    );
  }
}

/// Asks for an amount and a note. Pops `(minor units, note)` or null.
/// A widget of its own so the text fields live exactly as long as the
/// dialog, including its closing animation.
class _MoneyDialog extends StatefulWidget {
  const _MoneyDialog({required this.add, required this.currency});

  final bool add;
  final String currency;

  @override
  State<_MoneyDialog> createState() => _MoneyDialogState();
}

class _MoneyDialogState extends State<_MoneyDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final minor = parseAmount(_amount.text, widget.currency).minor!;
    Navigator.pop(context, (minor, _note.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final currency = widget.currency;
    return AlertDialog(
      title: Text(widget.add ? 'Add money' : 'Take money out'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount',
                suffixText: currency,
              ),
              validator: (v) {
                final r = parseAmount(v ?? '', currency);
                if (r.error != null) {
                  return amountErrorText(r.error!, currency);
                }
                if (r.minor == 0) return 'Enter an amount above zero';
                return null;
              },
            ),
            TextFormField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
