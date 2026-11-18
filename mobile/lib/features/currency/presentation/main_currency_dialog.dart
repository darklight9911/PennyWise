import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/device/device_profile.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/auth_controller.dart';

/// Lets the user pick a new main currency, explains what happens, and
/// asks the server to convert everything.
Future<void> showMainCurrencyDialog(BuildContext context, String current) =>
    showDialog<void>(
      context: context,
      builder: (_) => _MainCurrencyDialog(current: current),
    );

class _MainCurrencyDialog extends ConsumerStatefulWidget {
  const _MainCurrencyDialog({required this.current});

  final String current;

  @override
  ConsumerState<_MainCurrencyDialog> createState() =>
      _MainCurrencyDialogState();
}

class _MainCurrencyDialogState extends ConsumerState<_MainCurrencyDialog> {
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
    final codes = {widget.current, ...supportedCurrencies}.toList();
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Main currency'),
      contentPadding: const EdgeInsets.fromLTRB(0, Spacing.lg, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
              child: Text(
                'Totals, budgets and goals are shown in this currency. '
                'Changing it converts them with the rate of each day.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Flexible(
              child: RadioGroup<String>(
                groupValue: _picked,
                onChanged: (v) {
                  if (!_busy && v != null) setState(() => _picked = v);
                },
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in codes)
                      RadioListTile<String>(value: c, title: Text(c)),
                  ],
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.xl,
                  Spacing.sm,
                  Spacing.xl,
                  0,
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Change'),
        ),
      ],
    );
  }
}
