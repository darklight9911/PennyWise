import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/amount_text.dart';
import '../../../core/widgets/app_icon.dart';
import '../../currency/data/fx_rates.dart';
import '../../ledger/application/ledger_providers.dart';
import '../../ledger/data/ledger_store.dart';
import 'due_style.dart';

/// Dashboard card: what is owed to the user and what they owe, in the
/// main currency (other currencies at today's rate when known). Hidden
/// when nothing is open.
class DuesCard extends ConsumerWidget {
  const DuesCard({super.key, required this.baseCurrency});

  final String baseCurrency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = (ref.watch(duesProvider).value ?? const <DueProgress>[])
        .where((p) => !p.settled)
        .toList();
    if (open.isEmpty) return const SizedBox.shrink();

    final needRates = open.any((p) => p.due.currency != baseCurrency);
    final rates = needRates
        ? ref.watch(fxRatesProvider(baseCurrency)).value
        : null;
    var owedToMe = 0, iOwe = 0, unconverted = 0;
    for (final p in open) {
      int? v;
      if (p.due.currency == baseCurrency) {
        v = p.leftMinor;
      } else if (rates?.rates[p.due.currency] case final rate?) {
        v = convertMinor(
          p.leftMinor,
          p.due.currency,
          baseCurrency,
          invertRate(rate),
        );
      }
      if (v == null) {
        unconverted++;
      } else if (p.due.direction == DueDirection.owedToMe) {
        owedToMe += v;
      } else {
        iOwe += v;
      }
    }
    final today = todayYmd();
    final overdue = open
        .where((p) => p.status(today) == DueStatus.overdue)
        .length;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    Widget figure(String label, int minor) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: muted),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AmountText(
              minor: minor,
              currency: baseCurrency,
              signed: false,
              style: theme.textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.card),
          onTap: () => context.push(Routes.dues),
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppIcon(
                      HugeIcons.strokeRoundedHandshake,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Text('Dues', style: theme.textTheme.titleMedium),
                    ),
                    if (overdue > 0)
                      Text(
                        '$overdue overdue',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: Spacing.sm),
                Row(
                  children: [
                    figure('Owed to you', owedToMe),
                    const SizedBox(width: Spacing.md),
                    figure('You owe', iOwe),
                  ],
                ),
                if (unconverted > 0) ...[
                  const SizedBox(height: Spacing.xs),
                  Text(
                    '+ $unconverted in other currencies (no rate yet)',
                    style: muted,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
