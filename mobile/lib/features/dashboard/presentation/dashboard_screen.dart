import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/amount_text.dart';

/// Home screen. Shows placeholder zeros until accounts and transactions
/// exist (Milestone 2).
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  static const _currency = 'USD';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('pennyWise')),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.lg),
        children: [
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
                    currency: _currency,
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
                  minor: 0,
                  currency: _currency,
                  labelStyle: muted,
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: _MonthFigure(
                  label: 'Spent this month',
                  minor: 0,
                  currency: _currency,
                  labelStyle: muted,
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add transaction',
        onPressed: () {}, // Add-transaction flow arrives in Milestone 2.
        child: const Icon(Icons.add),
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
