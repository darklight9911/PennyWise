import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/device/device_profile.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/utils/money.dart';
import '../../auth/application/auth_controller.dart';
import '../../ledger/application/ledger_providers.dart';
import '../data/fx_rates.dart';
import 'currency_picker_sheet.dart';

/// Opens a searchable bottom sheet to pick a new main currency, previews its
/// FX coverage and balance impact, and asks the server to convert everything.
Future<void> showMainCurrencyDialog(BuildContext context, String current) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: scheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.card)),
    ),
    builder: (_) => _MainCurrencySheet(current: current),
  );
}

/// Estimates the total balance across [accounts] in [target] currency using
/// exact integer math. Returns the converted sum, how many foreign accounts
/// converted, and how many could not convert because [rates] lacked a rate.
({int total, int converted, int missing}) estimateTotalIn(
  String target,
  List<Account> accounts,
  Map<String, int> balances,
  FxRates? rates,
) {
  var total = 0;
  var converted = 0;
  var missing = 0;
  for (final a in accounts) {
    final balance = balances[a.id] ?? a.openingBalanceMinor;
    if (a.currency == target) {
      total += balance;
    } else {
      final rate = rates?.rates[a.currency];
      if (rate != null && parseRate(rate) != null) {
        total += convertMinor(balance, a.currency, target, invertRate(rate));
        converted++;
      } else {
        missing++;
      }
    }
  }
  return (total: total, converted: converted, missing: missing);
}

class _MainCurrencySheet extends ConsumerStatefulWidget {
  const _MainCurrencySheet({required this.current});

  final String current;

  @override
  ConsumerState<_MainCurrencySheet> createState() => _MainCurrencySheetState();
}

class _MainCurrencySheetState extends ConsumerState<_MainCurrencySheet> {
  late String _picked = widget.current;
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (_picked == widget.current) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .changeBaseCurrency(_picked);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.code == 'recalculating'
            ? 'The last change is still being applied. Try again in a minute.'
            : e.isNetworkError
            ? 'No connection. Changing the main currency needs the internet.'
            : e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final device = ref.watch(deviceProfileProvider);
    final auth = ref.watch(authControllerProvider);
    final userTz = auth is SignedIn ? auth.user.timezone : null;
    final detectedCode =
        ref.watch(detectedCurrencyProvider).value ??
        detectCurrency(timezone: userTz, countryCode: device.countryCode);
    final accounts = (ref.watch(accountsProvider).value ?? const <Account>[])
        .where((a) => !a.archived)
        .toList();
    final balances = ref.watch(balancesProvider).value ?? const <String, int>{};
    final accountCodes = [for (final a in accounts) a.currency];

    final currentRates = accounts.any((a) => a.currency != widget.current)
        ? ref.watch(fxRatesProvider(widget.current)).value
        : null;
    final pickedRates = _picked != widget.current
        ? ref.watch(fxRatesProvider(_picked)).value
        : null;

    final curEst = estimateTotalIn(
      widget.current,
      accounts,
      balances,
      currentRates,
    );
    final newEst = _picked == widget.current
        ? curEst
        : estimateTotalIn(_picked, accounts, balances, pickedRates);

    final showPreview =
        _picked != widget.current && accounts.isNotEmpty && newEst.missing == 0;
    final previewLine = !showPreview
        ? null
        : curEst.missing == 0
        ? 'Est. total: ${formatMinor(curEst.total, widget.current)} ${widget.current} '
              '→ ≈ ${formatMinor(newEst.total, _picked)} $_picked'
        : 'Est. total: ≈ ${formatMinor(newEst.total, _picked)} $_picked';

    final hasAuto = currencyInfo(_picked).autoRates || pickedRates != null;
    final note = _picked == widget.current
        ? (hasAuto
              ? 'Totals, budgets and goals use $_picked. Daily exchange rates update automatically.'
              : 'Totals, budgets and goals use $_picked. Enter rates by hand on foreign transactions.')
        : hasAuto
        ? "Daily rates update automatically for $_picked. Past transactions convert using each day's rate."
        : 'No automatic daily rate for $_picked. You can type rates by hand on foreign transactions.';

    final footer = Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.xl,
        Spacing.md,
        Spacing.xl,
        Spacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(Radii.button),
              border: Border.all(color: scheme.outline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (previewLine != null) ...[
                  Text(
                    previewLine,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                ],
                Text(
                  note,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: Spacing.sm),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
          const SizedBox(height: Spacing.md),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: Spacing.sm,
            runSpacing: Spacing.xs,
            children: [
              TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'Saving…' : 'Change'),
              ),
            ],
          ),
        ],
      ),
    );

    return CurrencyPickerSheet(
      title: 'Main currency',
      selected: _picked,
      detectedCode: detectedCode,
      accountCodes: accountCodes,
      enabled: !_busy,
      onSelect: (c) {
        if (_busy) return;
        setState(() {
          _picked = c;
          _error = null;
        });
      },
      footer: footer,
    );
  }
}
