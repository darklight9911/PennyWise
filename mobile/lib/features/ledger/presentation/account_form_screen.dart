import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/app_icon.dart';
import '../../../core/database/app_database.dart';
import '../../../core/device/device_profile.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../auth/application/auth_controller.dart';
import '../../currency/presentation/currency_picker_sheet.dart';
import '../application/ledger_providers.dart';
import 'ledger_style.dart';

/// Add a new account ([accountId] null) or edit one.
class AccountFormScreen extends ConsumerStatefulWidget {
  const AccountFormScreen({super.key, this.accountId});

  final String? accountId;

  @override
  ConsumerState<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends ConsumerState<AccountFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _opening = TextEditingController();
  String _type = 'bank';
  String _currency = 'USD';
  Account? _existing;
  int _transactionCount = 0;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.accountId == null;

  /// The currency cannot change once money has moved in or out.
  bool get _currencyLocked => _transactionCount > 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = await ref.read(ledgerStoreProvider.future);
    _currency = ref.read(baseCurrencyProvider);
    if (!_isNew) {
      _existing = await store.getAccount(widget.accountId!);
      final a = _existing;
      if (a != null) {
        _name.text = a.name;
        _type = a.type;
        _currency = a.currency;
        _opening.text = formatMinor(a.openingBalanceMinor, a.currency);
        _transactionCount = await store.countAccountTransactions(a.id);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    super.dispose();
  }

  String? _validateOpening(String? v) {
    if (v == null || v.trim().isEmpty) return null; // empty = 0
    final r = parseAmount(v, _currency, allowNegative: true);
    return r.error == null ? null : amountErrorText(r.error!, _currency);
  }

  Future<void> _pickCurrency() async {
    final profile = ref.read(profileProvider);
    final base = profile?.baseCurrency;
    final userTz = profile?.timezone;
    final device = ref.read(deviceProfileProvider);
    final detected =
        ref.read(detectedCurrencyProvider).value ??
        detectCurrency(timezone: userTz, countryCode: device.countryCode);
    final accounts = ref.read(accountsProvider).value ?? const <Account>[];
    final accountCodes = [
      ?base,
      for (final a in accounts)
        if (!a.archived) a.currency,
    ];
    final picked = await showCurrencyPicker(
      context,
      title: 'Account currency',
      selected: _currency,
      detectedCode: detected,
      accountCodes: accountCodes,
    );
    if (picked != null && mounted) {
      setState(() => _currency = picked);
    }
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final store = await ref.read(ledgerStoreProvider.future);
      final opening = _opening.text.trim().isEmpty
          ? 0
          : parseAmount(_opening.text, _currency, allowNegative: true).minor!;
      final existing = _existing;
      if (existing == null) {
        await store.createAccount(
          name: _name.text,
          type: _type,
          currency: _currency,
          openingBalanceMinor: opening,
        );
      } else {
        await store.updateAccount(
          existing.copyWith(
            name: _name.text,
            type: _type,
            currency: _currency,
            openingBalanceMinor: opening,
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
    final a = _existing!;
    final n = _transactionCount;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${a.name}?'),
        content: Text(
          n == 0
              ? 'This account has no transactions.'
              : 'Its $n ${n == 1 ? 'transaction is' : 'transactions are'} deleted too. This cannot be undone.',
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
    await store.deleteAccount(a.id);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New account' : 'Edit account'),
        actions: [
          if (!_isNew && _existing != null)
            IconButton(
              tooltip: 'Delete account',
              icon: const AppIcon(HugeIcons.strokeRoundedDelete02),
              onPressed: _delete,
            ),
        ],
      ),
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
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        hintText: 'e.g. Wallet, City Bank',
                      ),
                      validator: (v) {
                        final n = v?.trim().length ?? 0;
                        if (n == 0) return 'Give the account a name';
                        if (n > 60) return 'Use at most 60 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: Spacing.lg),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _type,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: [
                        for (final e in accountTypes.entries)
                          DropdownMenuItem(
                            value: e.key,
                            child: Row(
                              children: [
                                AppIcon(e.value.$2, size: 20),
                                const SizedBox(width: Spacing.md),
                                Text(e.value.$1),
                              ],
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _type = v ?? _type),
                    ),
                    const SizedBox(height: Spacing.lg),
                    CurrencyField(
                      label: 'Currency',
                      value: _currency,
                      helperText: _currencyLocked
                          ? 'Locked: this account already has transactions.'
                          : 'Cannot be changed once you add transactions.',
                      enabled: !_currencyLocked && !_saving,
                      onTap: _pickCurrency,
                    ),
                    const SizedBox(height: Spacing.lg),
                    TextFormField(
                      controller: _opening,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Starting balance',
                        hintText: '0',
                        suffixText: _currency,
                        helperText: 'What is in this account today. Can be negative (e.g. a card).',
                        helperMaxLines: 2,
                      ),
                      validator: _validateOpening,
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
                      onPressed: _saving ? null : _save,
                      child: Text(_isNew ? 'Add account' : 'Save changes'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
