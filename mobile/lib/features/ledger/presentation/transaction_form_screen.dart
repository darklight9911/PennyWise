import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/app_icon.dart';
import '../../../core/database/app_database.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../auth/application/auth_controller.dart';
import '../../receipts/data/receipt_picker.dart';
import '../../receipts/presentation/receipts_section.dart';
import '../application/ledger_providers.dart';
import '../data/ledger_store.dart';
import 'day_labels.dart';
import 'ledger_style.dart';

/// Add a transaction ([transactionId] null) or edit one.
class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({
    super.key,
    this.transactionId,
    this.initialKind = TxKind.expense,
  });

  final String? transactionId;
  final String initialKind;

  @override
  ConsumerState<TransactionFormScreen> createState() =>
      _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _received = TextEditingController();
  final _note = TextEditingController();
  final _rate = TextEditingController();
  List<PickedPhoto> _photos = []; // picked before the first save

  late String _kind = widget.initialKind;
  String? _accountId;
  String? _toAccountId;
  String? _categoryId;
  DateTime _when = DateTime.now();
  MoneyTransaction? _existing;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.transactionId == null;
  bool get _isTransfer => _kind == TxKind.transfer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_isNew) {
      final store = await ref.read(ledgerStoreProvider.future);
      final t = await store.getTransaction(widget.transactionId!);
      if (t != null) {
        _existing = t;
        _kind = t.kind;
        _accountId = t.accountId;
        _toAccountId = t.transferAccountId;
        _categoryId = t.categoryId;
        _when = t.occurredAt.toLocal();
        _amount.text = formatMinor(t.amountMinor, t.currency);
        if (t.transferAmountMinor != null) {
          _received.text = formatMinor(t.transferAmountMinor!, t.currency);
        }
        _note.text = t.note;
        if (t.fxRateSource == 'manual' && t.fxRateToBase != null) {
          _rate.text = t.fxRateToBase!;
        }
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _amount.dispose();
    _received.dispose();
    _note.dispose();
    _rate.dispose();
    super.dispose();
  }

  String get _baseCurrency {
    return ref.read(baseCurrencyProvider);
  }

  Account? _find(List<Account> accounts, String? id) =>
      accounts.where((a) => a.id == id).firstOrNull;

  String? _amountError(String? v, String currency) {
    final r = parseAmount(v ?? '', currency);
    if (r.error != null) return amountErrorText(r.error!, currency);
    if (r.minor == 0) return 'Enter an amount above zero';
    return null;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 366)),
    );
    if (picked != null) {
      setState(
        () => _when = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _when.hour,
          _when.minute,
        ),
      );
    }
  }

  Future<void> _save(List<Account> accounts) async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    if (!_isTransfer && _categoryId == null) {
      setState(() => _error = 'Pick a category');
      return;
    }
    final from = _find(accounts, _accountId)!;
    final to = _isTransfer ? _find(accounts, _toAccountId) : null;
    final amount = parseAmount(_amount.text, from.currency).minor!;
    final received = to == null
        ? null
        : to.currency == from.currency
        ? amount // same currency: the same amount arrives
        : parseAmount(_received.text, to.currency).minor!;

    final base = _baseCurrency;
    final manualRate = _isTransfer || from.currency == base
        ? null
        : parseRate(_rate.text);

    setState(() => _saving = true);
    try {
      final store = await ref.read(ledgerStoreProvider.future);
      final existing = _existing;
      if (existing == null) {
        final created = await store.createTransaction(
          kind: _kind,
          accountId: from.id,
          amountMinor: amount,
          currency: from.currency,
          occurredAt: _when,
          categoryId: _isTransfer ? null : _categoryId,
          transferAccountId: to?.id,
          transferAmountMinor: received,
          note: _note.text,
          baseCurrency: base,
          manualRate: manualRate,
        );
        if (_photos.isNotEmpty && !_isTransfer) {
          final receipts = await ref.read(receiptStoreProvider.future);
          for (final p in _photos) {
            await receipts.add(created.id, p.bytes, p.contentType);
          }
        }
      } else {
        await store.updateTransaction(
          existing.copyWith(
            kind: _kind,
            accountId: from.id,
            amountMinor: amount,
            currency: from.currency,
            occurredAt: _when,
            categoryId: Value(_isTransfer ? null : _categoryId),
            transferAccountId: Value(to?.id),
            transferAmountMinor: Value(received),
            note: _note.text,
          ),
          baseCurrency: base,
          manualRate: manualRate,
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
        title: const Text('Delete this transaction?'),
        content: const Text('This cannot be undone.'),
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
    await store.deleteTransaction(_existing!.id);
    // Its photos go too (the server removes its copies by itself).
    final receipts = await ref.read(receiptStoreProvider.future);
    await receipts.deleteAllOf(_existing!.id);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = (ref.watch(accountsProvider).value ?? const <Account>[])
        .where((a) => !a.archived || a.id == _accountId || a.id == _toAccountId)
        .toList();
    final title = _isNew
        ? switch (_kind) {
            TxKind.income => 'New income',
            TxKind.transfer => 'New transfer',
            _ => 'New expense',
          }
        : 'Edit transaction';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (!_isNew && _existing != null)
            IconButton(
              tooltip: 'Delete transaction',
              icon: const AppIcon(HugeIcons.strokeRoundedDelete02),
              onPressed: _delete,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : accounts.isEmpty
          ? _NoAccounts()
          : _form(accounts),
    );
  }

  Widget _form(List<Account> accounts) {
    _accountId ??= accounts.first.id;
    final from = _find(accounts, _accountId) ?? accounts.first;
    final targets = accounts.where((a) => a.id != from.id).toList();
    if (_toAccountId == from.id) _toAccountId = null;
    final to = _find(targets, _toAccountId);
    final needsReceived =
        _isTransfer && to != null && to.currency != from.currency;

    return ResponsiveBody(
      maxWidth: ContentWidths.form,
      child: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveLayout.horizontalPadding(context),
            vertical: Spacing.md,
          ),
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: TxKind.expense,
                  label: Text('Expense'),
                  icon: AppIcon(HugeIcons.strokeRoundedMinusSign),
                ),
                ButtonSegment(
                  value: TxKind.income,
                  label: Text('Income'),
                  icon: AppIcon(HugeIcons.strokeRoundedPlusSign),
                ),
                ButtonSegment(
                  value: TxKind.transfer,
                  label: Text('Transfer'),
                  icon: AppIcon(
                    HugeIcons.strokeRoundedArrowDataTransferHorizontal,
                  ),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() {
                _kind = s.single;
                _categoryId = null; // categories differ per kind
              }),
            ),
            const SizedBox(height: Spacing.xl),
            TextFormField(
              controller: _amount,
              autofocus: _isNew,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: Theme.of(context).textTheme.headlineMedium,
              decoration: InputDecoration(
                labelText: 'Amount',
                suffixText: from.currency,
              ),
              validator: (v) => _amountError(v, from.currency),
            ),
            const SizedBox(height: Spacing.lg),
            DropdownButtonFormField<String>(
              isExpanded: true,
              key: ValueKey('from-$_kind'),
              initialValue: from.id,
              decoration: InputDecoration(
                labelText: _isTransfer ? 'From account' : 'Account',
              ),
              items: [
                for (final a in accounts)
                  DropdownMenuItem(
                    value: a.id,
                    child: Text(
                      '${a.name} (${a.currency})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _accountId = v),
            ),
            const SizedBox(height: Spacing.lg),
            if (_isTransfer) ...[
              if (targets.isEmpty)
                const Text(
                  'Add a second account to move money between accounts.',
                )
              else
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  key: ValueKey('to-${from.id}'),
                  initialValue: to?.id,
                  decoration: const InputDecoration(labelText: 'To account'),
                  items: [
                    for (final a in targets)
                      DropdownMenuItem(
                        value: a.id,
                        child: Text(
                          '${a.name} (${a.currency})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  validator: (v) =>
                      v == null ? 'Pick where the money goes' : null,
                  onChanged: (v) => setState(() => _toAccountId = v),
                ),
              if (needsReceived) ...[
                const SizedBox(height: Spacing.lg),
                TextFormField(
                  controller: _received,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Amount received',
                    suffixText: to.currency,
                    helperText:
                        'What arrived in ${to.name}, in ${to.currency}.',
                  ),
                  validator: (v) => _amountError(v, to.currency),
                ),
              ],
            ] else ...[
              if (from.currency != _baseCurrency) ...[
                TextFormField(
                  controller: _rate,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Exchange rate (optional)',
                    prefixText: '1 ${from.currency} = ',
                    suffixText: _baseCurrency,
                    helperText:
                        "Leave empty to use the day's rate. Type one for "
                        'currencies without a daily rate.',
                    helperMaxLines: 2,
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty || parseRate(v!) != null
                      ? null
                      : 'Use a number above zero, like 1.08',
                ),
                const SizedBox(height: Spacing.lg),
              ],
              _CategoryPicker(
                kind: _kind,
                selected: _categoryId,
                onSelected: (id) => setState(() => _categoryId = id),
              ),
            ],
            const SizedBox(height: Spacing.lg),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const AppIcon(HugeIcons.strokeRoundedCalendar03),
              title: Text(dayLabel(localDateOf(_when), DateTime.now())),
              subtitle: const Text('Date'),
              trailing: const AppIcon(HugeIcons.strokeRoundedCalendar01),
              onTap: _pickDate,
            ),
            TextFormField(
              controller: _note,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            if (!_isTransfer) ...[
              const SizedBox(height: Spacing.sm),
              ReceiptsSection(
                transactionId: _existing?.id,
                pending: _photos,
                onPendingChanged: (list) => setState(() => _photos = list),
              ),
            ],
            const SizedBox(height: Spacing.lg),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.lg),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton(
              onPressed: _saving || (_isTransfer && targets.isEmpty)
                  ? null
                  : () => _save(accounts),
              child: Text(_isNew ? 'Save' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryPicker extends ConsumerWidget {
  const _CategoryPicker({
    required this.kind,
    required this.selected,
    required this.onSelected,
  });

  final String kind;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider(kind)).value ?? const [];
    final scheme = Theme.of(context).colorScheme;
    if (categories.isEmpty) {
      return const Text(
        'No categories yet. Add some in Settings → Categories.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Category', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: Spacing.sm),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            for (final c in categories)
              ChoiceChip(
                avatar: AppIcon(
                  categoryIcon(c.icon),
                  size: 18,
                  color: colorFromHex(c.color, scheme.primary),
                ),
                label: Text(c.name, overflow: TextOverflow.ellipsis),
                selected: c.id == selected,
                onSelected: (_) => onSelected(c.id),
              ),
          ],
        ),
      ],
    );
  }
}

class _NoAccounts extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: ContentWidths.narrow),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppIcon(HugeIcons.strokeRoundedWallet01, size: 48),
              const SizedBox(height: Spacing.md),
              const Text('First, add an account', textAlign: TextAlign.center),
              const SizedBox(height: Spacing.sm),
              const Text(
                'Every transaction belongs to an account, like your wallet or bank.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Spacing.lg),
              FilledButton(
                onPressed: () => context.push(Routes.newAccount),
                child: const Text('Add an account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
