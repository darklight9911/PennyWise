import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../auth/application/auth_controller.dart';
import '../application/app_lock.dart';
import 'pin_pad.dart';

/// Puts the lock screen (or a plain cover) above the whole app.
class LockGate extends ConsumerWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);
    // Locks the app's data, with or without an account.
    final auth = ref.watch(authControllerProvider);
    final hasData = auth is SignedIn || auth is Guest;
    final Widget? over = !lock.ready
        ? const _Cover()
        : lock.enabled && hasData && lock.locked
        ? const LockScreen()
        : lock.enabled && lock.covered
        ? const _Cover()
        : null;
    return Stack(
      children: [
        // Hidden from touch and screen readers while locked.
        ExcludeSemantics(
          excluding: over != null,
          child: AbsorbPointer(absorbing: over != null, child: child),
        ),
        ?over,
      ],
    );
  }
}

/// Hides the app's content (app switcher, start-up).
class _Cover extends StatelessWidget {
  const _Cover();

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
  );
}

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String _pin = '';
  String? _message;
  bool _checking = false;
  bool _confirmLogout = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Offer fingerprint or face at once, if the user turned it on.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(appLockProvider).biometric) {
        unawaited(ref.read(appLockProvider.notifier).unlockWithBiometrics());
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _digit(String d) async {
    final len = ref.read(appLockProvider).pinLength;
    if (_checking || _pin.length >= len) return;
    setState(() {
      _pin += d;
      _message = null;
    });
    if (_pin.length < len) return;
    setState(() => _checking = true);
    final result = await ref.read(appLockProvider.notifier).unlockWithPin(_pin);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _pin = '';
      _message = switch (result) {
        UnlockResult.unlocked => null,
        UnlockResult.wrong => 'Wrong PIN. Try again.',
        UnlockResult.wait => 'Too many tries. Wait 30 seconds.',
      };
    });
    if (result == UnlockResult.wait) {
      _tick?.cancel();
      _tick = Timer(tryAgainAfter, () {
        if (mounted) setState(() => _message = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lock = ref.watch(appLockProvider);
    final now = ref.read(lockClockProvider)();
    final waiting = lock.waitUntil != null && now.isBefore(lock.waitUntil!);
    return Positioned.fill(
      child: Material(
        color: theme.scaffoldBackgroundColor,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveLayout.horizontalPadding(context),
                vertical: Spacing.lg,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: ContentWidths.narrow,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      HugeIcons.strokeRoundedSquareLock02,
                      size: 40,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: Spacing.lg),
                    Text(
                      'pennyWise is locked',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: Spacing.sm),
                    Text('Enter your PIN', style: theme.textTheme.bodyMedium),
                    const SizedBox(height: Spacing.xl),
                    PinDots(filled: _pin.length, length: lock.pinLength),
                    SizedBox(
                      height: 40,
                      child: Center(
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _message ?? '',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      ),
                    ),
                    PinPad(
                      enabled: !_checking && !waiting,
                      onDigit: _digit,
                      onBackspace: () => setState(() {
                        if (_pin.isNotEmpty) {
                          _pin = _pin.substring(0, _pin.length - 1);
                        }
                      }),
                      extra: lock.biometric
                          ? Semantics(
                              button: true,
                              label: 'Unlock with fingerprint or face',
                              excludeSemantics: true,
                              child: IconButton(
                                iconSize: 32,
                                icon: AppIcon(
                                  HugeIcons.strokeRoundedFingerPrint,
                                  color: theme.colorScheme.primary,
                                ),
                                onPressed: () => ref
                                    .read(appLockProvider.notifier)
                                    .unlockWithBiometrics(),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: Spacing.lg),
                    if (!_confirmLogout)
                      TextButton(
                        onPressed: () => setState(() => _confirmLogout = true),
                        child: const Text('Forgot PIN?'),
                      )
                    else ...[
                      Text(
                        'Log out to remove the lock. Changes not yet synced on this '
                        'phone are lost; everything synced comes back when you log in.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: Spacing.sm),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () =>
                                setState(() => _confirmLogout = false),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: Spacing.sm),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: theme.colorScheme.error,
                            ),
                            onPressed: () => ref
                                .read(authControllerProvider.notifier)
                                .logout(),
                            child: const Text('Log out'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
