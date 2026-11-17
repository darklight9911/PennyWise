import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/app_icon.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/amount_text.dart';
import '../../../core/widgets/panda_mascot.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/penny_greeting.dart';

/// Home screen. Shows placeholder zeros until accounts and transactions
/// exist (Milestone 2).
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final user = auth is SignedIn ? auth.user : null;
    final currency = user?.baseCurrency ?? 'USD';
    // Placeholder totals until transactions are wired in (Milestone 2).
    const incomeMinor = 0;
    const spentMinor = 0;
    final greeting = pennyGreetingForMonth(
      incomeMinor: incomeMinor,
      spentMinor: spentMinor,
    );

    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(user == null ? 'pennyWise' : 'Hi, ${user.displayName}'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          try {
            await ref.read(authControllerProvider.notifier).refreshUser();
          } on ApiException {
            // Offline: keep showing what we have.
          }
        },
        child: ListView(
          padding: const EdgeInsets.all(Spacing.lg),
          children: [
            _PennyCard(greeting: greeting),
            const SizedBox(height: Spacing.md),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total balance', style: muted),
                    const SizedBox(height: Spacing.sm),
                    AmountText(
                      minor: 0,
                      currency: currency,
                      signed: false,
                      large: true,
                      style: theme.textTheme.displaySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),
            Row(
              children: [
                Expanded(
                  child: _MonthFigure(
                    label: 'Income this month',
                    minor: incomeMinor,
                    currency: currency,
                    labelStyle: muted,
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: _MonthFigure(
                    label: 'Spent this month',
                    minor: spentMinor,
                    currency: currency,
                    labelStyle: muted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        // Tabs stay alive side by side: no shared hero animation tag.
        heroTag: null,
        tooltip: 'Add transaction',
        onPressed: () {}, // Add-transaction flow arrives in Milestone 2.
        child: const AppIcon(HugeIcons.strokeRoundedPlusSign),
      ),
    );
  }
}

/// Penny the panda with a short note about the month.
class _PennyCard extends StatelessWidget {
  const _PennyCard({required this.greeting});

  final PennyGreeting greeting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.sm,
          Spacing.sm,
          Spacing.lg,
          Spacing.sm,
        ),
        child: Row(
          children: [
            PandaMascot(mood: greeting.mood, size: 88),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(greeting.message, style: theme.textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthFigure extends StatelessWidget {
  const _MonthFigure({
    required this.label,
    required this.minor,
    required this.currency,
    this.labelStyle,
  });

  final String label;
  final int minor;
  final String currency;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: labelStyle),
            const SizedBox(height: Spacing.xs),
            AmountText(
              minor: minor,
              currency: currency,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      ),
    );
  }
}
