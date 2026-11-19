import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/auth_controller.dart';
import '../../sync/sync_controller.dart';

/// How often to ask the server whether the conversion has finished.
final recalcPollProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 4),
);

/// Shown instead of totals while the server converts every amount to a new
/// main currency. It checks back every few seconds and syncs the new
/// amounts when the server is done.
class RecalculatingBanner extends ConsumerStatefulWidget {
  const RecalculatingBanner({super.key});

  @override
  ConsumerState<RecalculatingBanner> createState() =>
      _RecalculatingBannerState();
}

class _RecalculatingBannerState extends ConsumerState<RecalculatingBanner> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(ref.read(recalcPollProvider), (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    try {
      await ref.read(authControllerProvider.notifier).refreshUser();
    } on ApiException {
      return; // offline: try again next tick
    }
    if (!mounted) return;
    final auth = ref.read(authControllerProvider);
    if (auth is SignedIn && !auth.user.recalculating) {
      _timer?.cancel();
      await ref.read(syncControllerProvider.notifier).syncNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(profileProvider)?.baseCurrency ?? '';
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Text(
                'Recalculating totals in $currency… This takes a moment.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
