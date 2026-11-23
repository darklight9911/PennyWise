import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/finance_colors.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/amount_text.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../auth/application/auth_controller.dart';
import '../../ledger/application/ledger_providers.dart';
import '../../ledger/data/ledger_store.dart';
import '../../ledger/presentation/day_labels.dart';
import '../../recurring/domain/recurrence.dart';
import 'due_style.dart';

/// One due: what is left, paying it (in full or in part), forgiving it,
/// and its history.
class DueDetailScreen extends ConsumerWidget {
  const DueDetailScreen({super.key, required this.dueId});

  final String dueId;

  Future<void> _pay(
    BuildContext context,
    WidgetRef ref,
    DueProgress p, {
    required bool full,
  }) async {
    final accounts = (ref.read(accountsProvider).value ?? const <Account>[])
        .where((a) => !a.archived && a.currency == p.due.currency)
        .toList();
    final messenger = ScaffoldMessenger.of(context);
    if (accounts.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Add an account in ${p.due.currency} first (Settings → Accounts).',
          ),
        ),
      );
      return;
    }
    final entry = await showModalBottomSheet<_Payment>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) =>
          _PaymentSheet(progress: p, accounts: accounts, full: full),
    );
    if (entry == null) return;
    try {
      final store = await ref.read(ledgerStoreProvider.future);
      await store.recordDuePayment(
        p.due,
        amountMinor: entry.amountMinor,
        accountId: entry.accountId,
        date: entry.date,
        note: entry.note,
        baseCurrency: ref.read(baseCurrencyProvider),
      );
    } on DueException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Due d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this due?'),
        content: const Text(
          'Payments already recorded stay in your transactions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final store = await ref.read(ledgerStoreProvider.future);
    await store.deleteDue(d.id);
    if (context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(duesProvider).value;
    final p = all?.where((x) => x.due.id == dueId).firstOrNull;
    final history =
        ref.watch(dueTransactionsProvider(dueId)).value ??
        const <MoneyTransaction>[];
    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: all == null
              ? const CircularProgressIndicator()
              : const Text('This due was deleted.'),
        ),
      );
    }
    final d = p.due;
    final theme = Theme.of(context);
    final today = todayYmd();
    final owed = d.direction == DueDirection.owedToMe;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(d.person, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Edit due',
            icon: const AppIcon(HugeIcons.strokeRoundedPencilEdit02),
            onPressed: () => context.push(Routes.editDue(d.id)),
          ),
          IconButton(
            tooltip: 'Delete due',
            icon: const AppIcon(HugeIcons.strokeRoundedDelete02),
            onPressed: () => _delete(context, ref, d),
          ),
        ],
      ),
      body: ResponsiveBody(
        child: ListView(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveLayout.horizontalPadding(context),
            vertical: Spacing.md,
          ),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AppIcon(
                          dueKindIcon(d.kind),
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: Spacing.sm),
                        Expanded(
                          child: Text(
                            dueHeadline(d),
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        Text(
                          dueKindLabel(d.kind),
                          style: theme.textTheme.labelLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: Spacing.md),
                    Text(
                      p.settled ? (p.forgiven ? 'Closed' : 'Settled') : 'Left',
                      style: muted,
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: AmountText(
                        minor: p.settled ? d.amountMinor : p.leftMinor,
                        currency: d.currency,
                        signed: false,
                        large: true,
                        style: theme.textTheme.headlineMedium,
                      ),
                    ),
                    const SizedBox(height: Spacing.sm),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: p.fraction,
                        minHeight: 8,
                        color: p.settled
                            ? context.financeColors.income
                            : theme.colorScheme.primary,
                        backgroundColor: theme.colorScheme.outlineVariant,
                        semanticsLabel:
                            '${(p.fraction * 100).round()} percent paid',
                      ),
                    ),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      '${formatMinor(p.paidMinor, d.currency)} ${owed ? 'received' : 'paid'} of '
                      '${moneyLabel(d.amountMinor, d.currency)}',
                      style: muted,
                    ),
                    const SizedBox(height: Spacing.sm),
                    Text(
                      dueWhenLabel(p, today),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: dueWhenColor(context, p, today),
                      ),
                    ),
                    if (d.dueDate != null)
                      Text(
                        'Due ${dueDateLabel(d.dueDate!)} · Reminder: ${reminderLabel(d.remindDaysBefore).toLowerCase()}',
                        style: muted,
                      ),
                    if (d.note.isNotEmpty) ...[
                      const SizedBox(height: Spacing.sm),
                      Text(d.note),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),
            if (!p.settled) ...[
              FilledButton(
                onPressed: () => _pay(context, ref, p, full: true),
                child: Text(owed ? 'Mark received' : 'Mark paid'),
              ),
              const SizedBox(height: Spacing.sm),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(64, 48),
                ),
                onPressed: () => _pay(context, ref, p, full: false),
                child: const Text('Add part payment'),
              ),
              TextButton(
                onPressed: () async {
                  final store = await ref.read(ledgerStoreProvider.future);
                  await store.forgiveDue(d);
                },
                child: Text(owed ? 'Forgive the rest' : 'Close without paying'),
              ),
            ] else if (p.forgiven)
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(64, 48),
                ),
                onPressed: () async {
                  final store = await ref.read(ledgerStoreProvider.future);
                  await store.reopenDue(d);
                },
                child: const Text('Reopen'),
              ),
            const SizedBox(height: Spacing.lg),
            Text('History', style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.xs),
            if (history.isEmpty)
              Text('Nothing recorded yet.', style: muted)
            else
              Card(
                child: Column(
                  children: [
                    for (final t in history)
                      ListTile(
                        title: Text(dueEntryLabel(d, t)),
                        subtitle: Text(dayLabel(t.localDate, DateTime.now())),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TrailingAmount(
                              child: AmountText(
                                minor: t.amountMinor,
                                currency: t.currency,
                                signed: false,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Delete this entry',
                              icon: const AppIcon(
                                HugeIcons.strokeRoundedDelete02,
                                size: 20,
                              ),
                              onPressed: () async {
                                final store = await ref.read(
                                  ledgerStoreProvider.future,
                                );
                                await store.deleteTransaction(t.id);
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

typedef _Payment = ({
  int amountMinor,
  String accountId,
  DateTime date,
  String note,
});

/// Amount (all that is left, or a part), account, date and note.
class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({
    required this.progress,
    required this.accounts,
    required this.full,
  });

  final DueProgress progress;
  final List<Account> accounts;
  final bool full;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: widget.full
        ? formatMinor(widget.progress.leftMinor, widget.progress.due.currency)
        : '',
  );
  final _note = TextEditingController();
  late String _accountId =
      widget.accounts.any((a) => a.id == widget.progress.due.accountId)
      ? widget.progress.due.accountId!
      : widget.accounts.first.id;
  DateTime _date = DateTime.now();

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.progress;
    final currency = p.due.currency;
    final owed = p.due.direction == DueDirection.owedToMe;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      // As tall as its content (ResponsiveBody would fill the screen).
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: ContentWidths.form),
          child: Form(
            key: _formKey,
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(
                ResponsiveLayout.horizontalPadding(context),
                0,
                ResponsiveLayout.horizontalPadding(context),
                Spacing.lg,
              ),
              children: [
                Text(
                  widget.full
                      ? (owed ? 'Mark received' : 'Mark paid')
                      : 'Part payment',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text('${moneyLabel(p.leftMinor, currency)} left'),
                const SizedBox(height: Spacing.md),
                TextFormField(
                  controller: _amount,
                  autofocus: !widget.full,
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
                    if (r.minor! > p.leftMinor) {
                      return 'Only ${moneyLabel(p.leftMinor, currency)} is left';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: Spacing.md),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _accountId,
                  decoration: InputDecoration(
                    labelText: owed ? 'Into account' : 'From account',
                  ),
                  items: [
                    for (final a in widget.accounts)
                      DropdownMenuItem(
                        value: a.id,
                        child: Text(a.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) =>
                      setState(() => _accountId = v ?? _accountId),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const AppIcon(HugeIcons.strokeRoundedCalendar03),
                  title: Text(dayLabel(ymd(_date), DateTime.now())),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 366)),
                    );
                    if (picked != null) {
                      setState(
                        () => _date = DateTime(
                          picked.year,
                          picked.month,
                          picked.day,
                          12,
                        ),
                      );
                    }
                  },
                ),
                TextFormField(
                  controller: _note,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                FilledButton(
                  onPressed: () {
                    if (!_formKey.currentState!.validate()) return;
                    Navigator.pop<_Payment>(context, (
                      amountMinor: parseAmount(_amount.text, currency).minor!,
                      accountId: _accountId,
                      date: _date,
                      note: _note.text,
                    ));
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
