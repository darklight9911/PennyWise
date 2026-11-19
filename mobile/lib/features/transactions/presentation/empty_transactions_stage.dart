import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/panda_mascot.dart';
import '../../auth/application/auth_controller.dart';
import '../../ledger/application/ledger_providers.dart';
import '../../ledger/data/ledger_store.dart';

/// Penny's mood for the empty transactions stage based on account readiness and
/// how many times the user has poked Penny.
PandaMood pennyEmptyMood({required bool hasAccounts, required int pokeCount}) {
  if (!hasAccounts) {
    return pokeCount == 0
        ? PandaMood.wave
        : (pokeCount.isOdd ? PandaMood.happy : PandaMood.celebrate);
  }
  if (pokeCount == 0) return PandaMood.sleeping;
  return switch (pokeCount % 3) {
    1 => PandaMood.wave,
    2 => PandaMood.happy,
    _ => PandaMood.celebrate,
  };
}

/// Penny's speech-bubble message for the empty transactions stage.
String pennyEmptyMessage({required bool hasAccounts, required int pokeCount}) {
  if (!hasAccounts) {
    return pokeCount == 0
        ? "Hi, I'm Penny! Add your first account and I'll keep track of every penny."
        : "Hehe! Set up an account below and we're ready to roll.";
  }
  if (pokeCount == 0) {
    return 'Zzz… your ledger is taking a nap. Tap me or log an entry to wake me up.';
  }
  if (pokeCount == 1) {
    return 'Wide awake! Pick Expense or Income below to log your first one.';
  }
  return 'Ready whenever you are — tap below to add your first entry!';
}

const _sampleCoffeeByCurrency = <String, int>{
  'BDT': -25000,
  'INR': -18000,
  'PKR': -35000,
  'NPR': -25000,
  'LKR': -65000,
  'PHP': -15000,
  'THB': -8500,
  'EGP': -9000,
  'KES': -35000,
  'NGN': -250000,
  'IDR': -3500000,
};

/// Realistic sample coffee expense in minor units for [currency].
int sampleCoffeeMinor(String currency) {
  final code = currency.trim().toUpperCase();
  final specific = _sampleCoffeeByCurrency[code];
  if (specific != null) return specific;
  if (!RegExp(r'^[A-Z]{3}$').hasMatch(code)) return -450;
  return switch (currencyExponent(code)) {
    0 => -550,
    3 => -1500,
    _ => -450,
  };
}

/// Empty Transactions experience combining interactive Wake-Up Penny, a
/// 2-step onboarding launchpad, and a dashed example transaction preview.
class EmptyTransactionsStage extends ConsumerStatefulWidget {
  const EmptyTransactionsStage({super.key});

  @override
  ConsumerState<EmptyTransactionsStage> createState() =>
      _EmptyTransactionsStageState();
}

class _EmptyTransactionsStageState
    extends ConsumerState<EmptyTransactionsStage> {
  int _pokeCount = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accounts = (ref.watch(accountsProvider).value ?? const <Account>[])
        .where((a) => !a.archived)
        .toList();
    final hasAccounts = accounts.isNotEmpty;
    final auth = ref.watch(authControllerProvider);
    final baseCurrency = auth is SignedIn ? auth.user.baseCurrency : 'USD';

    final mood = pennyEmptyMood(
      hasAccounts: hasAccounts,
      pokeCount: _pokeCount,
    );
    final message = pennyEmptyMessage(
      hasAccounts: hasAccounts,
      pokeCount: _pokeCount,
    );
    final sleeping = mood == PandaMood.sleeping;
    final sampleMinor = sampleCoffeeMinor(baseCurrency);
    final sampleAmount =
        '${formatSigned(sampleMinor, baseCurrency)} $baseCurrency';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.xl,
        Spacing.lg,
        96,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Semantics(
              button: true,
              label: sleeping
                  ? 'Tap Penny to wake her up'
                  : 'Tap Penny to make her giggle',
              excludeSemantics: true,
              child: Material(
                shape: const CircleBorder(),
                color: _pokeCount > 0
                    ? scheme.secondaryContainer.withValues(alpha: 0.28)
                    : scheme.surface,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => setState(() => _pokeCount++),
                  child: Container(
                    width: 148,
                    height: 148,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _pokeCount > 0 ? scheme.primary : scheme.outline,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        PandaMascot(
                          mood: mood,
                          size: 128,
                          giggleTrigger: _pokeCount,
                          fallback: AppIcon(
                            hasAccounts
                                ? HugeIcons.strokeRoundedInvoice01
                                : HugeIcons.strokeRoundedWallet01,
                            size: 48,
                            color: scheme.primary,
                          ),
                        ),
                        if (sleeping)
                          Positioned(
                            top: 6,
                            right: 2,
                            child: ExcludeSemantics(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: Spacing.sm,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.surface,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: scheme.outline),
                                ),
                                child: Text(
                                  'Zzz',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            sleeping ? 'Tap Penny to wake her up' : 'Penny is ready!',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Spacing.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'No transactions yet',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: KeyedSubtree(
                      key: ValueKey(message),
                      child: Text(
                        message,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          _LaunchpadCard(
            hasAccounts: hasAccounts,
            accountCount: accounts.length,
            onAddAccount: () => context.push(Routes.newAccount),
            onAddExpense: () =>
                context.push(Routes.newTransaction(TxKind.expense)),
            onAddIncome: () =>
                context.push(Routes.newTransaction(TxKind.income)),
          ),
          const SizedBox(height: Spacing.lg),
          Text(
            'Preview · how entries appear',
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          _GhostPreviewCard(
            accountLabel: hasAccounts ? accounts.first.name : 'Wallet',
            amountLabel: sampleAmount,
            onTap: () => context.push(
              hasAccounts
                  ? Routes.newTransaction(TxKind.expense)
                  : Routes.newAccount,
            ),
          ),
        ],
      ),
    );
  }
}

class _LaunchpadCard extends StatelessWidget {
  const _LaunchpadCard({
    required this.hasAccounts,
    required this.accountCount,
    required this.onAddAccount,
    required this.onAddExpense,
    required this.onAddIncome,
  });

  final bool hasAccounts;
  final int accountCount;
  final VoidCallback onAddAccount;
  final VoidCallback onAddExpense;
  final VoidCallback onAddIncome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.lg,
              Spacing.lg,
              Spacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text('Get started', style: theme.textTheme.titleSmall),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${hasAccounts ? 1 : 0} of 2 done',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            minVerticalPadding: Spacing.sm,
            leading: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasAccounts ? scheme.primary : scheme.secondaryContainer,
              ),
              child: hasAccounts
                  ? AppIcon(
                      HugeIcons.strokeRoundedTick02,
                      size: 16,
                      color: scheme.onPrimary,
                      strokeWidth: AppIcon.selectedStroke,
                    )
                  : Text(
                      '1',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
            title: const Text('Add an account'),
            subtitle: Text(
              hasAccounts
                  ? 'Done · $accountCount ${accountCount == 1 ? 'account' : 'accounts'} ready'
                  : 'Cash, bank, card or wallet',
            ),
            trailing: !hasAccounts
                ? const AppIcon(HugeIcons.strokeRoundedArrowRight01)
                : null,
            onTap: !hasAccounts ? onAddAccount : null,
          ),
          const Divider(height: 1),
          ListTile(
            minVerticalPadding: Spacing.sm,
            leading: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasAccounts
                    ? scheme.secondaryContainer
                    : theme.scaffoldBackgroundColor,
                border: hasAccounts ? null : Border.all(color: scheme.outline),
              ),
              child: Text(
                '2',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: hasAccounts
                      ? scheme.onSecondaryContainer
                      : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            title: const Text('Log your first transaction'),
            subtitle: Text(
              hasAccounts
                  ? 'Choose Expense or Income below'
                  : 'Unlocks once you add an account',
            ),
            trailing: hasAccounts
                ? const AppIcon(HugeIcons.strokeRoundedArrowRight01)
                : null,
            onTap: hasAccounts ? onAddExpense : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.sm,
              Spacing.lg,
              Spacing.lg,
            ),
            child: !hasAccounts
                ? SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const AppIcon(
                        HugeIcons.strokeRoundedWallet01,
                        size: 20,
                      ),
                      label: const Text('Add your first account'),
                      onPressed: onAddAccount,
                    ),
                  )
                : Wrap(
                    spacing: Spacing.sm,
                    runSpacing: Spacing.sm,
                    children: [
                      FilledButton.icon(
                        icon: const AppIcon(
                          HugeIcons.strokeRoundedMinusSign,
                          size: 20,
                        ),
                        label: const Text('Add expense'),
                        onPressed: onAddExpense,
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(64, 48),
                        ),
                        icon: const AppIcon(
                          HugeIcons.strokeRoundedPlusSign,
                          size: 20,
                        ),
                        label: const Text('Add income'),
                        onPressed: onAddIncome,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _GhostPreviewCard extends StatelessWidget {
  const _GhostPreviewCard({
    required this.accountLabel,
    required this.amountLabel,
    required this.onTap,
  });

  final String accountLabel;
  final String amountLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      button: true,
      label: 'Example transaction. Tap to log your first expense',
      excludeSemantics: true,
      child: CustomPaint(
        painter: _DashedRRectPainter(color: scheme.outline, radius: Radii.card),
        child: Material(
          color: theme.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(Radii.card),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(Radii.button),
                      border: Border.all(color: scheme.outline),
                    ),
                    child: AppIcon(
                      HugeIcons.strokeRoundedCoffee01,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: Spacing.sm,
                          runSpacing: Spacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Morning coffee',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: Spacing.sm,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: scheme.outline),
                              ),
                              child: Text(
                                'Example',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Today · $accountLabel',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Flexible(
                    flex: 0,
                    child: Text(
                      amountLabel,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    const dash = 6.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

/// Compact Penny empty card for the Dashboard's Recent section.
class EmptyRecentCard extends StatefulWidget {
  const EmptyRecentCard({
    super.key,
    required this.hasAccounts,
    required this.onAction,
  });

  final bool hasAccounts;
  final VoidCallback onAction;

  @override
  State<EmptyRecentCard> createState() => _EmptyRecentCardState();
}

class _EmptyRecentCardState extends State<EmptyRecentCard> {
  int _pokes = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mood = _pokes > 0
        ? PandaMood.happy
        : (widget.hasAccounts ? PandaMood.sleeping : PandaMood.wave);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              button: true,
              label: widget.hasAccounts && _pokes == 0
                  ? 'Tap Penny to wake her up'
                  : 'Tap Penny to make her giggle',
              excludeSemantics: true,
              child: Material(
                shape: const CircleBorder(),
                color: theme.scaffoldBackgroundColor,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => setState(() => _pokes++),
                  child: Container(
                    width: 76,
                    height: 76,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.outline),
                    ),
                    child: PandaMascot(
                      mood: mood,
                      size: 68,
                      giggleTrigger: _pokes,
                      fallback: AppIcon(
                        widget.hasAccounts
                            ? HugeIcons.strokeRoundedInvoice01
                            : HugeIcons.strokeRoundedWallet01,
                        size: 32,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('No activity yet', style: theme.textTheme.titleSmall),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    widget.hasAccounts
                        ? 'Log your first expense or income and it will show up here.'
                        : 'Add an account above, then record your first transaction.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(64, 48),
                    ),
                    icon: AppIcon(
                      widget.hasAccounts
                          ? HugeIcons.strokeRoundedPlusSign
                          : HugeIcons.strokeRoundedWallet01,
                      size: 18,
                    ),
                    label: Text(
                      widget.hasAccounts ? 'Add expense' : 'Add account',
                    ),
                    onPressed: widget.onAction,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
