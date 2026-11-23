import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../auth/application/auth_controller.dart';
import '../../currency/presentation/currency_picker_sheet.dart';
import '../../ledger/application/ledger_providers.dart';
import '../../ledger/data/ledger_store.dart';
import '../../recurring/domain/recurrence.dart';
import 'due_style.dart';

const _reminderChoices = <int?>[null, 0, 1, 3, 7];

/// Add a due ([dueId] null) or edit one.
class DueFormScreen extends ConsumerStatefulWidget {
  const DueFormScreen({
    super.key,
    this.dueId,
    this.initialDirection = DueDirection.owedToMe,
  });

  final String? dueId;
  final String initialDirection;

  @override
  ConsumerState<DueFormScreen> createState() => _DueFormScreenState();
}

class _DueFormScreenState extends ConsumerState<DueFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _person = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _personFocus = FocusNode();

  late String _direction = widget.initialDirection;
  String _kind = DueKind.loan;
  String? _currency;
  String? _accountId;
  String? _categoryId;
  bool _moneyMoved = true;
  late String _start = ymd(DateTime.now());
  String? _dueDate;
  int? _remind = 1;
  Due? _existing;
  List<String> _people = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.dueId == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = await ref.read(ledgerStoreProvider.future);
    _people = await store.duePeople();
    if (!_isNew) {
      final d = await store.getDue(widget.dueId!);
      if (d != null) {
        _existing = d;
        _direction = d.direction;
        _kind = d.kind;
        _person.text = d.person;
        _amount.text = formatMinor(d.amountMinor, d.currency);
        _currency = d.currency;
        _accountId = d.accountId;
        _categoryId = d.categoryId;
        _start = d.startDate;
        _dueDate = d.dueDate;
        _remind = d.remindDaysBefore;
        _note.text = d.note;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _person.dispose();
    _amount.dispose();
    _note.dispose();
    _personFocus.dispose();
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
      lastDate: DateTime(DateTime.now().year + 30),
    );
    return picked == null ? null : ymd(picked);
  }

  Future<void> _pickCurrency(String current) async {
    final picked = await showCurrencyPicker(
      context,
      title: 'Currency of this due',
      selected: current,
    );
    if (picked != null && picked != current) {
      setState(() {
        _currency = picked;
        _accountId = null; // accounts must match the currency
      });
    }
  }

  Future<void> _save(String currency) async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    if (_kind == DueKind.bill && _categoryId == null) {
      setState(() => _error = 'Choose a category for the bill.');
      return;
    }
    if (_isNew && _kind == DueKind.loan && _moneyMoved && _accountId == null) {
      setState(
        () => _error = 'Choose the account the money moved through, or turn off "Money moved now".',
      );
      return;
    }
    final amount = parseAmount(_amount.text, currency).minor!;
    setState(() => _saving = true);
    try {
      final store = await ref.read(ledgerStoreProvider.future);
      final e = _existing;
      if (e == null) {
        final d = await store.createDue(
          direction: _direction,
          kind: _kind,
          person: _person.text,
          amountMinor: amount,
          currency: currency,
          startDate: _start,
          accountId: _accountId,
          categoryId: _categoryId,
          dueDate: _dueDate,
          remindDaysBefore: _remind,
          note: _note.text,
          moneyMovedNow: _kind == DueKind.loan && _moneyMoved,
          baseCurrency: ref.read(baseCurrencyProvider),
        );
        if (mounted) context.pushReplacement(Routes.due(d.id));
      } else {
        await store.updateDue(
          e.copyWith(
            direction: _direction,
            kind: _kind,
            person: _person.text,
            amountMinor: amount,
            currency: currency,
            accountId: Value(_accountId),
            categoryId: Value(_categoryId),
            startDate: _start,
            dueDate: Value(_dueDate),
            remindDaysBefore: Value(_remind),
            note: _note.text,
          ),
        );
        if (mounted) context.pop();
      }
    } on DueException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e, st) {
      if (mounted) setState(() => _error = userMessage(e, st));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = ref.watch(baseCurrencyProvider);
    final accounts = (ref.watch(accountsProvider).value ?? const <Account>[])
        .where((a) => !a.archived)
        .toList();
    final currency = _currency ??=
        accounts.where((a) => a.id == _accountId).firstOrNull?.currency ?? base;
    final usable = accounts.where((a) => a.currency == currency).toList();
    if (_accountId != null && !usable.any((a) => a.id == _accountId)) {
      _accountId = null;
    }
    final catKind = _direction == DueDirection.owedToMe
        ? TxKind.income
        : TxKind.expense;
    final categories =
        ref.watch(categoriesProvider(catKind)).value ?? const <Category>[];
    if (_categoryId != null &&
        categories.isNotEmpty &&
        !categories.any((c) => c.id == _categoryId)) {
      _categoryId = null;
    }
    final owed = _direction == DueDirection.owedToMe;
    final paidSome =
        _existing != null; // payments may exist: direction and kind stay

    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? 'New due' : 'Edit due')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ResponsiveBody(
              maxWidth: ContentWidths.form,
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveLayout.horizontalPadding(context),
                    vertical: Spacing.md,
                  ),
                  children: [
                    if (!paidSome) ...[
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
                        onSelectionChanged: (s) => setState(() {
                          _direction = s.single;
                          _categoryId = null;
                        }),
                      ),
                      const SizedBox(height: Spacing.md),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: DueKind.loan,
                            label: Text('Loan'),
                          ),
                          ButtonSegment(
                            value: DueKind.bill,
                            label: Text('Bill'),
                          ),
                        ],
                        selected: {_kind},
                        onSelectionChanged: (s) =>
                            setState(() => _kind = s.single),
                      ),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        _kind == DueKind.loan
                            ? (owed
                                  ? 'Money you lent. Getting it back is not income.'
                                  : 'Money you borrowed. Paying it back is not spending.')
                            : (owed
                                  ? 'Someone owes you for work or a sale. Receiving it counts as income.'
                                  : 'You owe for something you got. Paying it counts as spending.'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: Spacing.lg),
                    ],
                    RawAutocomplete<String>(
                      textEditingController: _person,
                      focusNode: _personFocus,
                      optionsBuilder: (v) {
                        final q = v.text.trim().toLowerCase();
                        if (q.isEmpty) return const Iterable<String>.empty();
                        return _people.where(
                          (p) =>
                              p.toLowerCase().contains(q) &&
                              p.toLowerCase() != q,
                        );
                      },
                      fieldViewBuilder:
                          (context, controller, focus, onSubmit) =>
                              TextFormField(
                                controller: controller,
                                focusNode: focus,
                                textCapitalization: TextCapitalization.words,
                                decoration: InputDecoration(
                                  labelText: owed
                                      ? 'Who owes you?'
                                      : 'Who do you owe?',
                                  hintText: 'e.g. Rahim',
                                ),
                                validator: (v) {
                                  final n = v?.trim().length ?? 0;
                                  if (n == 0) return 'Enter a name';
                                  if (n > 60) {
                                    return 'Use at most 60 characters';
                                  }
                                  return null;
                                },
                              ),
                      optionsViewBuilder: (context, onSelected, options) =>
                          Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 4,
                              borderRadius: BorderRadius.circular(Radii.button),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxHeight: 220,
                                  maxWidth: ContentWidths.form,
                                ),
                                child: ListView(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  children: [
                                    for (final o in options)
                                      ListTile(
                                        title: Text(o),
                                        onTap: () => onSelected(o),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                    ),
                    const SizedBox(height: Spacing.lg),
                    TextFormField(
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Amount',
                        suffix: InkWell(
                          onTap: paidSome
                              ? null
                              : () => _pickCurrency(currency),
                          child: Text(
                            currency,
                            semanticsLabel: 'Currency $currency',
                          ),
                        ),
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
                    if (!paidSome)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => _pickCurrency(currency),
                          child: Text('Change currency ($currency)'),
                        ),
                      ),
                    const SizedBox(height: Spacing.sm),
                    DropdownButtonFormField<String?>(
                      isExpanded: true,
                      key: ValueKey('acct-$currency'),
                      initialValue: _accountId,
                      decoration: InputDecoration(
                        labelText: 'Account',
                        helperText: usable.isEmpty
                            ? 'You have no account in $currency. Add one in Settings → Accounts to record payments.'
                            : 'Used for payments (and the loan itself).',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('No account yet'),
                        ),
                        for (final a in usable)
                          DropdownMenuItem<String?>(
                            value: a.id,
                            child: Text(
                              a.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _accountId = v),
                    ),
                    if (_isNew && _kind == DueKind.loan)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Money moved now'),
                        subtitle: Text(
                          owed
                              ? 'Take the lent money out of the account.'
                              : 'Add the borrowed money to the account.',
                        ),
                        value: _moneyMoved,
                        onChanged: (v) => setState(() => _moneyMoved = v),
                      ),
                    if (_kind == DueKind.bill) ...[
                      const SizedBox(height: Spacing.lg),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        key: ValueKey('cat-$catKind'),
                        initialValue: _categoryId,
                        decoration: InputDecoration(
                          labelText: owed
                              ? 'Income category'
                              : 'Spending category',
                        ),
                        items: [
                          for (final c in categories)
                            DropdownMenuItem(
                              value: c.id,
                              child: Text(
                                c.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) => setState(() => _categoryId = v),
                      ),
                    ],
                    const SizedBox(height: Spacing.sm),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const AppIcon(HugeIcons.strokeRoundedCalendar03),
                      title: Text('Since ${dueDateLabel(_start)}'),
                      onTap: () async {
                        final d = await _pickDate(_start);
                        if (d == null) return;
                        setState(() {
                          _start = d;
                          if (_dueDate != null && _dueDate!.compareTo(d) < 0) {
                            _dueDate = d;
                          }
                        });
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const AppIcon(HugeIcons.strokeRoundedCalendar03),
                      title: Text(
                        _dueDate == null
                            ? 'No due date'
                            : 'Due ${dueDateLabel(_dueDate!)}',
                      ),
                      subtitle: const Text('Optional'),
                      trailing: _dueDate == null
                          ? null
                          : IconButton(
                              tooltip: 'Remove due date',
                              icon: const AppIcon(
                                HugeIcons.strokeRoundedCancel01,
                              ),
                              onPressed: () => setState(() => _dueDate = null),
                            ),
                      onTap: () async {
                        final d = await _pickDate(_dueDate, notBefore: _start);
                        if (d != null) setState(() => _dueDate = d);
                      },
                    ),
                    if (_dueDate != null) ...[
                      const SizedBox(height: Spacing.sm),
                      DropdownButtonFormField<int?>(
                        isExpanded: true,
                        initialValue: _remind,
                        decoration: const InputDecoration(
                          labelText: 'Reminder',
                        ),
                        items: [
                          for (final r in _reminderChoices)
                            DropdownMenuItem<int?>(
                              value: r,
                              child: Text(reminderLabel(r)),
                            ),
                        ],
                        onChanged: (v) => setState(() => _remind = v),
                      ),
                    ],
                    const SizedBox(height: Spacing.lg),
                    TextFormField(
                      controller: _note,
                      maxLength: 500,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Note (optional)',
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Spacing.md),
                        child: Text(
                          _error!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    FilledButton(
                      onPressed: _saving ? null : () => _save(currency),
                      child: Text(_isNew ? 'Add due' : 'Save changes'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
