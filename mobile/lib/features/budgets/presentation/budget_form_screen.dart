import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_icon.dart';
import '../../auth/application/auth_controller.dart';
import '../../ledger/application/ledger_providers.dart';
import '../../ledger/data/ledger_store.dart';

/// Add a budget ([budgetId] null) or edit one.
class BudgetFormScreen extends ConsumerStatefulWidget {
  const BudgetFormScreen({super.key, this.budgetId});

  final String? budgetId;

  @override
  ConsumerState<BudgetFormScreen> createState() => _BudgetFormScreenState();
}

/// Value of the "All spending" choice in the category dropdown.
const _all = '';

class _BudgetFormScreenState extends ConsumerState<BudgetFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  String _categoryId = _all;
  String _period = 'monthly';
  bool _alert80 = true;
  bool _alert100 = true;
  Budget? _existing;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.budgetId == null;

  String get _currency {
    final auth = ref.read(authControllerProvider);
    return auth is SignedIn ? auth.user.baseCurrency : 'USD';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_isNew) {
      final store = await ref.read(ledgerStoreProvider.future);
      final b = await store.getBudget(widget.budgetId!);
      if (b != null) {
        _existing = b;
        _categoryId = b.categoryId ?? _all;
        _period = b.period;
        _amount.text = formatMinor(b.amountMinor, _currency);
        final levels = parseLevels(b.alertThresholds);
        _alert80 = levels.contains(80);
        _alert100 = levels.contains(100);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    final amount = parseAmount(_amount.text, _currency).minor!;
    final levels = [if (_alert80) 80, if (_alert100) 100];
    setState(() => _saving = true);
    try {
      final store = await ref.read(ledgerStoreProvider.future);
      final category = _categoryId == _all ? null : _categoryId;
      final e = _existing;
      if (e == null) {
        await store.createBudget(
          categoryId: category,
          amountMinor: amount,
          period: _period,
          alertThresholds: levels,
        );
      } else {
        await store.updateBudget(
          e.copyWith(
            categoryId: Value(category),
            amountMinor: amount,
            period: _period,
            alertThresholds: levels.join(','),
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
        title: const Text('Delete this budget?'),
        content: const Text(
          'Your transactions stay; only the limit and its alerts go.',
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
    await store.deleteBudget(_existing!.id);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final categories =
        ref.watch(categoriesProvider(TxKind.expense)).value ??
        const <Category>[];
    final currency = _currency;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New budget' : 'Edit budget'),
        actions: [
          if (_existing != null)
            IconButton(
              tooltip: 'Delete budget',
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
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _categoryId,
                    decoration: const InputDecoration(labelText: 'Spending on'),
                    items: [
                      const DropdownMenuItem(
                        value: _all,
                        child: Text('All spending'),
                      ),
                      for (final c in categories)
                        DropdownMenuItem(
                          value: c.id,
                          child: Text(c.name, overflow: TextOverflow.ellipsis),
                        ),
                      if (!categories.any((c) => c.id == _categoryId) &&
                          _categoryId != _all)
                        DropdownMenuItem(
                          value: _categoryId,
                          child: const Text('(deleted category)'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _categoryId = v ?? _all),
                  ),
                  const SizedBox(height: Spacing.lg),
                  TextFormField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Limit',
                      suffixText: currency,
                    ),
                    validator: (v) {
                      final r = parseAmount(v ?? '', currency);
                      if (r.error != null) {
                        return amountErrorText(r.error!, currency);
                      }
                      if (r.minor == 0) return 'Enter a limit above zero';
                      return null;
                    },
                  ),
                  const SizedBox(height: Spacing.lg),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'weekly', label: Text('Every week')),
                      ButtonSegment(
                        value: 'monthly',
                        label: Text('Every month'),
                      ),
                    ],
                    selected: {_period},
                    onSelectionChanged: (s) =>
                        setState(() => _period = s.single),
                  ),
                  const SizedBox(height: Spacing.sm),
                  Text(
                    _period == 'weekly'
                        ? 'Weeks start on Monday.'
                        : 'Months start on the 1st.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: Spacing.lg),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Message me at 80 %'),
                    value: _alert80,
                    onChanged: (v) => setState(() => _alert80 = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Message me at 100 %'),
                    value: _alert100,
                    onChanged: (v) => setState(() => _alert100 = v),
                  ),
                  const SizedBox(height: Spacing.lg),
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
                    onPressed: _saving ? null : _save,
                    child: Text(_isNew ? 'Add budget' : 'Save changes'),
                  ),
                ],
              ),
            ),
    );
  }
}
