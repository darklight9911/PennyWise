import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../application/app_lock.dart';
import 'pin_pad.dart';

/// Chooses a PIN (4 to 6 digits), typed twice, and turns the lock on.
class SetPinScreen extends ConsumerStatefulWidget {
  const SetPinScreen({super.key});

  @override
  ConsumerState<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends ConsumerState<SetPinScreen> {
  String _pin = '';
  String? _first; // set after the first entry
  String? _error;
  bool _saving = false;

  int get _maxLength => _first?.length ?? 6;

  Future<void> _digit(String d) async {
    if (_saving || _pin.length >= _maxLength) return;
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_first != null && _pin.length == _first!.length) await _confirm();
  }

  void _next() {
    if (_pin.length < 4) {
      setState(() => _error = 'Use at least 4 digits');
      return;
    }
    setState(() {
      _first = _pin;
      _pin = '';
    });
  }

  Future<void> _confirm() async {
    if (_pin != _first) {
      setState(() {
        _error = "The PINs don't match. Start again.";
        _first = null;
        _pin = '';
      });
      return;
    }
    setState(() => _saving = true);
    await ref.read(appLockProvider.notifier).enable(_pin);
    if (mounted) context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final confirming = _first != null;
    return Scaffold(
      appBar: AppBar(title: const Text('App lock')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveLayout.horizontalPadding(context),
              vertical: Spacing.lg,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: ContentWidths.narrow),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    confirming ? 'Enter the PIN again' : 'Choose a PIN',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: Spacing.sm),
                  Text(
                    confirming ? 'To make sure it is the one you meant.' : '4 to 6 digits. You need it each time you open pennyWise.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Spacing.xl),
                  PinDots(
                    filled: _pin.length,
                    length: confirming
                        ? _first!.length
                        : (_pin.length < 4 ? 4 : _pin.length),
                  ),
                  SizedBox(
                    height: 40,
                    child: Center(
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _error ?? '',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ),
                  ),
                  PinPad(
                    enabled: !_saving,
                    onDigit: _digit,
                    onBackspace: () => setState(() {
                      if (_pin.isNotEmpty) {
                        _pin = _pin.substring(0, _pin.length - 1);
                      }
                    }),
                  ),
                  if (!confirming) ...[
                    const SizedBox(height: Spacing.lg),
                    FilledButton(onPressed: _next, child: const Text('Next')),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
