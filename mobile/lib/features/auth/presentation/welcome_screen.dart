import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/device/device_profile.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../currency/presentation/currency_picker_sheet.dart';
import '../application/auth_controller.dart';
import 'auth_widgets.dart';

/// First launch. The app works without an account, so the only question
/// is the main currency. Logging in or creating an account is optional
/// (here, or later from Settings).
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  late String _currency = ref.read(deviceProfileProvider).defaultCurrency;
  bool _pickedByUser = false;
  bool _starting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _detect();
  }

  Future<void> _detect() async {
    final detected = await ref.read(detectedCurrencyProvider.future);
    if (mounted && !_pickedByUser) setState(() => _currency = detected);
  }

  Future<void> _pick() async {
    final detected =
        ref.read(detectedCurrencyProvider).value ??
        ref.read(deviceProfileProvider).defaultCurrency;
    final picked = await showCurrencyPicker(
      context,
      title: 'Main currency',
      subtitle: 'Totals and budgets use this currency.',
      selected: _currency,
      detectedCode: detected,
    );
    if (picked != null && mounted) {
      setState(() {
        _currency = picked;
        _pickedByUser = true;
      });
    }
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .startAsGuest(baseCurrency: _currency);
    } on Object catch (e, st) {
      if (mounted) setState(() => _error = userMessage(e, st));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Welcome to pennyWise',
      subtitle:
          'Start tracking right away. No account needed: your money stays '
          'on this phone and works offline. Sign in any time to back it up '
          'and sync.',
      children: [
        CurrencyField(
          label: 'Main currency',
          value: _currency,
          helperText: 'Totals and budgets use this currency.',
          enabled: !_starting,
          onTap: _pick,
        ),
        const SizedBox(height: Spacing.xl),
        if (_error case final error?) ...[
          FormErrorText(error),
          const SizedBox(height: Spacing.md),
        ],
        LoadingButton(label: 'Start', loading: _starting, onPressed: _start),
        const SizedBox(height: Spacing.lg),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Already have an account?'),
            TextButton(
              onPressed: _starting ? null : () => context.push(Routes.login),
              child: const Text('Log in'),
            ),
          ],
        ),
      ],
    );
  }
}
