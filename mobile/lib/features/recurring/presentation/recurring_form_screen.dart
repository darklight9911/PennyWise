import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_icon.dart';
import '../../ledger/application/ledger_providers.dart';
import '../../ledger/data/ledger_store.dart';
import '../../ledger/presentation/day_labels.dart';
import '../domain/recurrence.dart';

/// Add a recurring bill or income ([ruleId] null) or edit one.
class RecurringFormScreen extends ConsumerStatefulWidget {
  const RecurringFormScreen({super.key, this.ruleId});

  final String? ruleId;

  @override
  ConsumerState<RecurringFormScreen> createState() =>
      _RecurringFormScreenState();
}

class _RecurringFormScreenState extends ConsumerState<RecurringFormScreen> {
  static const _frequencies = {
    'daily': 'Day',
    'weekly': 'Week',
    'monthly': 'Month',
    'yearly': 'Year',
  };
  static const _reminders = {
    0: 'No reminder',
    1: '1 day before',
    3: '3 days before',
    7: '1 week before',
  };

  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _every = TextEditingController(text: '1');
  final _note = TextEditingController();
  String _kind = TxKind.expense;
  String? _accountId;
  String? _categoryId;
  String _frequency = 'monthly';
  late String _start = ymd(DateTime.now());
  String? _end;
  int _remind = 0;
  bool _active = true;
  RecurringRule? _existing;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.ruleId == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_isNew) {
      final store = await ref.read(ledgerStoreProvider.future);
      final r = await store.getRecurringRule(widget.ruleId!);
      if (r != null) {
        _existing = r;
        _kind = r.kind;
        _accountId = r.accountId;
        _categoryId = r.categoryId;
        _amount.text = formatMinor(r.amountMinor, r.currency);
        _every.text = '${r.every}';
        _note.text = r.note;
        _frequency = r.frequency;
        _start = r.startDate;
        _end = r.endDate;
        _remind = r.remindDaysBefore;
        _active = r.active;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _amount.dispose();
    _every.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<String?> _pickDate(String? current, {String? notBefore}) async {
    final first = notBefore == null
        ? DateTime(2000)
        : DateTime.parse(notBefore);
    var initial = current == null ? DateTime.now() : DateTime.parse(current);
    if (initial.isBefore(first)) initial = first;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: DateTime(DateTime.now().year + 50),
    );
    return picked == null ? null : ymd(picked);
  }

  Future<void> _save(Map<String, Account> accounts) async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    final account = accounts[_accountId]!;
    final amount = parseAmount(_amount.text, account.currency).minor!;
    final every = int.parse(_every.text.trim());
    setState(() => _saving = true);
    try {
      final store = await ref.read(ledgerStoreProvider.future);
      final e = _existing;
      if (e == null) {
        await store.createRecurringRule(
          kind: _kind,
          accountId: account.id,
          categoryId: _categoryId!,
          amountMinor: amount,
          currency: account.currency,
          frequency: _frequency,
          every: every,
          startDate: _start,
          endDate: _end,
          remindDaysBefore: _remind,
          note: _note.text,
        );
      } else {
        await store.updateRecurringRule(
          e.copyWith(
            kind: _kind,
            accountId: account.id,
            categoryId: _categoryId,
            amountMinor: amount,
            currency: account.currency,
            frequency: _frequency,
            every: every,
            startDate: _start,
            endDate: Value(_end),
            remindDaysBefore: _remind,
            note: _note.text,
            active: _active,
          ),
        );
      }
      if (mounted) context.pop();
    } on Object catch (e, st) {
      if (mounted) setState(() => _error = userMessage(e, st));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this recurring item?'),
        content: const Text(
          'No new entries are added. Entries already added stay.',
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
    await store.deleteRecurringRule(_existing!.id);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final allAccounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final accountIndex = {for (final a in allAccounts) a.id: a};
    final accounts = [
      for (final a in allAccounts)
        if (!a.archived || a.id == _accountId) a,
    ];
    final categories =
        ref.watch(categoriesProvider(_kind)).value ?? const <Category>[];
    final currency = accountIndex[_accountId]?.currency;
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New recurring' : 'Edit recurring'),
        actions: [
          if (_existing != null)
            IconButton(
              tooltip: 'Delete recurring',
              icon: const AppIcon(HugeIcons.strokeRoundedDelete02),
              onPressed: _delete,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(Spacing.lg),
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: TxKind.expense,
                        label: Text('Expense'),
                      ),
                      ButtonSegment(
                        value: TxKind.income,
                        label: Text('Income'),
                      ),
                    ],
                    selected: {_kind},
                    onSelectionChanged: (s) => setState(() {
                      _kind = s.single;
                      _categoryId = null;
                    }),
                  ),
                  const SizedBox(height: Spacing.lg),
                  TextFormField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      suffixText: currency,
                    ),
                    validator: (v) {
                      final c = currency;
                      if (c == null) return null; // the account field says it
                      final r = parseAmount(v ?? '', c);
                      if (r.error != null) return amountErrorText(r.error!, c);
                      if (r.minor == 0) return 'Enter an amount above zero';
                      return null;
                    },
                  ),
                  const SizedBox(height: Spacing.lg),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _accountId,
                    decoration: const InputDecoration(labelText: 'Account'),
                    items: [
                      for (final a in accounts)
                        DropdownMenuItem(
                          value: a.id,
                          child: Text(a.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    validator: (v) => v == null ? 'Choose an account' : null,
                    onChanged: (v) => setState(() => _accountId = v),
                  ),
                  const SizedBox(height: Spacing.lg),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    // A new key when the kind changes resets the field.
                    key: ValueKey(_kind),
                    initialValue: categories.any((c) => c.id == _categoryId)
                        ? _categoryId
                        : null,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [
                      for (final c in categories)
                        DropdownMenuItem(
                          value: c.id,
                          child: Text(c.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    validator: (v) => v == null ? 'Choose a category' : null,
                    onChanged: (v) => setState(() => _categoryId = v),
                  ),
                  const SizedBox(height: Spacing.lg),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 96,
                        child: TextFormField(
                          controller: _every,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Every'),
                          validator: (v) {
                            final n = int.tryParse(v?.trim() ?? '');
                            if (n == null || n < 1 || n > 365) return '1–365';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: Spacing.md),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _frequency,
                          decoration: const InputDecoration(
                            labelText: 'Repeats',
                          ),
                          items: [
                            for (final f in _frequencies.entries)
                              DropdownMenuItem(
                                value: f.key,
                                child: Text(f.value),
                              ),
                          ],
                          onChanged: (v) =>
                              setState(() => _frequency = v ?? 'monthly'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.sm),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const AppIcon(HugeIcons.strokeRoundedCalendar03),
                    title: Text('Starts ${dayLabel(_start, now)}'),
                    onTap: () async {
                      final d = await _pickDate(_start);
                      if (d == null) return;
                      setState(() {
                        _start = d;
                        if (_end != null && _end!.compareTo(d) < 0) _end = d;
                      });
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const AppIcon(HugeIcons.strokeRoundedCalendar03),
                    title: Text(
                      _end == null
                          ? 'No end date'
                          : 'Ends ${dayLabel(_end!, now)}',
                    ),
                    trailing: _end == null
                        ? null
                        : IconButton(
                            tooltip: 'Remove end date',
                            icon: const AppIcon(
                              HugeIcons.strokeRoundedCancel01,
                            ),
                            onPressed: () => setState(() => _end = null),
                          ),
                    onTap: () async {
                      final d = await _pickDate(_end, notBefore: _start);
                      if (d != null) setState(() => _end = d);
                    },
                  ),
                  const SizedBox(height: Spacing.sm),
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: _reminders.containsKey(_remind) ? _remind : 0,
                    decoration: const InputDecoration(labelText: 'Reminder'),
                    items: [
                      for (final r in _reminders.entries)
                        DropdownMenuItem(value: r.key, child: Text(r.value)),
                    ],
                    onChanged: (v) => setState(() => _remind = v ?? 0),
                  ),
                  const SizedBox(height: Spacing.lg),
                  TextFormField(
                    controller: _note,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Name (optional)',
                      hintText: 'e.g. Rent, Netflix',
                    ),
                    validator: (v) => (v?.trim().length ?? 0) > 200
                        ? 'Use at most 200 characters'
                        : null,
                  ),
                  if (_existing != null)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active'),
                      subtitle: const Text('Off pauses new entries'),
                      value: _active,
                      onChanged: (v) => setState(() => _active = v),
                    ),
                  const SizedBox(height: Spacing.xl),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.lg),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  FilledButton(
                    onPressed: _saving ? null : () => _save(accountIndex),
                    child: Text(_isNew ? 'Add recurring' : 'Save changes'),
                  ),
                ],
              ),
            ),
    );
  }
}
