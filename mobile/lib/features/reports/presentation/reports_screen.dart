import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/finance_colors.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/amount_text.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/panda_mascot.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../auth/application/auth_controller.dart';
import '../../currency/presentation/recalculating_banner.dart';
import '../../ledger/application/ledger_providers.dart';
import '../../ledger/data/ledger_store.dart';
import '../../ledger/presentation/ledger_style.dart';
import 'charts.dart';

enum ReportPeriod { month, quarter, year }

/// First and last local date (YYYY-MM-DD) of a period ending this month.
({String from, String to, String label}) periodRange(
  ReportPeriod p,
  DateTime now,
) {
  String ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  final endOfMonth = DateTime(now.year, now.month + 1, 0);
  return switch (p) {
    ReportPeriod.month => (
      from: ymd(DateTime(now.year, now.month, 1)),
      to: ymd(endOfMonth),
      label: 'this month',
    ),
    ReportPeriod.quarter => (
      from: ymd(DateTime(now.year, now.month - 2, 1)),
      to: ymd(endOfMonth),
      label: 'the last 3 months',
    ),
    ReportPeriod.year => (
      from: ymd(DateTime(now.year, 1, 1)),
      to: ymd(DateTime(now.year, 12, 31)),
      label: 'this year',
    ),
  };
}

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Colours for categories without their own colour, then grey for "Other".
const _palette = [
  Color(0xFF2C706E), Color(0xFF729D99), Color(0xFFB4654A), Color(0xFF4F6D9A), //
  Color(0xFF9A5B00), Color(0xFF8E5C9E), Color(0xFF6B8E3D),
];
const _otherColor = Color(0xFFB9B4AA);
const _maxSlices = 6;

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportPeriod _period = ReportPeriod.month;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final base = profile?.baseCurrency ?? 'USD';
    final now = DateTime.now();
    final range = periodRange(_period, now);
    final spending = ref.watch(
      categoryTotalsProvider((
        from: range.from,
        to: range.to,
        base: base,
        kind: 'expense',
      )),
    );
    final income = ref.watch(
      categoryTotalsProvider((
        from: range.from,
        to: range.to,
        base: base,
        kind: 'income',
      )),
    );
    final sixAgo = DateTime(now.year, now.month - 5, 1);
    final flow = ref.watch(
      monthlyFlowProvider((
        from: '${sixAgo.year}-${sixAgo.month.toString().padLeft(2, '0')}',
        to: '${now.year}-${now.month.toString().padLeft(2, '0')}',
        base: base,
      )),
    );

    final cats = spending.value ?? const <CategoryTotal>[];
    final spent = cats.fold<int>(0, (a, c) => a + c.totalMinor);
    final earned = (income.value ?? const <CategoryTotal>[]).fold<int>(
      0,
      (a, c) => a + c.totalMinor,
    );
    final accounts = (ref.watch(accountsProvider).value ?? const <Account>[])
        .where((a) => !a.archived)
        .toList();

    final hPad = ResponsiveLayout.horizontalPadding(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(
            tooltip: 'Export',
            icon: const AppIcon(HugeIcons.strokeRoundedDownload04),
            onPressed: () => context.push(Routes.export),
          ),
        ],
      ),
      body: ResponsiveBody(
        child: ListView(
          padding: EdgeInsets.fromLTRB(hPad, Spacing.md, hPad, 88),
          children: [
            SegmentedButton<ReportPeriod>(
              segments: const [
                ButtonSegment(value: ReportPeriod.month, label: Text('Month')),
                ButtonSegment(
                  value: ReportPeriod.quarter,
                  label: Text('3 months'),
                ),
                ButtonSegment(value: ReportPeriod.year, label: Text('Year')),
              ],
              selected: {_period},
              onSelectionChanged: (s) => setState(() => _period = s.single),
            ),
            const SizedBox(height: Spacing.md),
            if (profile?.recalculating ?? false)
              const RecalculatingBanner()
            else if (spending.isLoading && !spending.hasValue)
              const Padding(
                padding: EdgeInsets.all(Spacing.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (spent == 0 && earned == 0)
              EmptyState(
                mascot: PandaMood.thinking,
                icon: HugeIcons.strokeRoundedPieChart,
                title: 'Nothing to show yet',
                message:
                    'No income or spending ${range.label}. Charts appear once you add transactions.',
                action: FilledButton.icon(
                  icon: AppIcon(
                    accounts.isEmpty
                        ? HugeIcons.strokeRoundedWallet01
                        : HugeIcons.strokeRoundedPlusSign,
                    size: 20,
                  ),
                  label: Text(
                    accounts.isEmpty
                        ? 'Add your first account'
                        : 'Add transaction',
                  ),
                  onPressed: () => context.push(
                    accounts.isEmpty
                        ? Routes.newAccount
                        : Routes.newTransaction(),
                  ),
                ),
              )
            else ...[
              _Totals(income: earned, spent: spent, currency: base),
              const SizedBox(height: Spacing.md),
              if (cats.isNotEmpty)
                _SpendingCard(
                  cats: cats,
                  total: spent,
                  currency: base,
                  label: range.label,
                ),
              const SizedBox(height: Spacing.md),
              if (flow.value case final months?)
                _FlowCard(months: months, currency: base),
            ],
          ],
        ),
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({
    required this.income,
    required this.spent,
    required this.currency,
  });

  final int income, spent;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    Widget figure(String label, int minor) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: muted),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AmountText(
              minor: minor,
              currency: currency,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Row(
          children: [
            figure('Income', income),
            const SizedBox(width: Spacing.sm),
            figure('Spent', -spent),
            const SizedBox(width: Spacing.sm),
            figure('Net', income - spent),
          ],
        ),
      ),
    );
  }
}

class _SpendingCard extends StatelessWidget {
  const _SpendingCard({
    required this.cats,
    required this.total,
    required this.currency,
    required this.label,
  });

  final List<CategoryTotal> cats;
  final int total;
  final String currency;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Top categories get a slice each; the rest share "Other".
    final shown = cats.take(_maxSlices).toList();
    final rest = cats.skip(_maxSlices).fold<int>(0, (a, c) => a + c.totalMinor);
    final colors = [
      for (var i = 0; i < shown.length; i++)
        colorFromHex(shown[i].color, _palette[i % _palette.length]),
      if (rest > 0) _otherColor,
    ];
    final rows = [
      for (final c in shown) (c.name, c.totalMinor),
      if (rest > 0) ('Other', rest),
    ];
    String pct(int v) => total == 0 ? '0%' : '${(v * 100 / total).round()}%';

    Widget buildChart(double width) => SizedBox(
      width: width,
      child: DonutChart(
        values: [for (final r in rows) r.$2],
        colors: colors,
        semanticsLabel:
            'Spending $label: '
            '${[for (final r in rows) '${r.$1} ${pct(r.$2)}'].join(', ')}',
        center: Padding(
          padding: EdgeInsets.all(width * 0.22),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Spent', style: theme.textTheme.bodySmall),
                Text(
                  formatMinor(total, currency),
                  style: theme.textTheme.titleMedium,
                ),
                Text(currency, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );

    final largeText = MediaQuery.textScalerOf(context).scale(14) > 18;

    Widget buildLegendRow(int i, {required bool stack}) {
      final dot = Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: colors[i], shape: BoxShape.circle),
      );
      final nameWidget = Text(
        rows[i].$1,
        maxLines: stack ? 2 : 1,
        overflow: TextOverflow.ellipsis,
      );
      final amountText = Text(formatMinor(rows[i].$2, currency));
      final pctText = ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 40),
        child: Text(
          pct(rows[i].$2),
          textAlign: TextAlign.end,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );

      if (stack) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  dot,
                  const SizedBox(width: Spacing.md),
                  Expanded(child: nameWidget),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: amountText,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  pctText,
                ],
              ),
            ],
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            dot,
            const SizedBox(width: Spacing.md),
            Expanded(flex: 3, child: nameWidget),
            const SizedBox(width: Spacing.sm),
            Flexible(
              flex: 2,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    amountText,
                    const SizedBox(width: Spacing.xs),
                    pctText,
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Spending by category', style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.md),
            LayoutBuilder(
              builder: (context, constraints) {
                final sideBySide = constraints.maxWidth >= 520;
                final stackLegend =
                    !sideBySide && constraints.maxWidth < 320 && largeText;
                final legendRows = [
                  for (var i = 0; i < rows.length; i++)
                    buildLegendRow(i, stack: stackLegend),
                ];
                if (sideBySide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      buildChart(160),
                      const SizedBox(width: Spacing.lg),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: legendRows,
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  children: [
                    Center(child: buildChart(156)),
                    const SizedBox(height: Spacing.md),
                    ...legendRows,
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FlowCard extends StatelessWidget {
  const _FlowCard({required this.months, required this.currency});

  final List<MonthFlow> months;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fin = context.financeColors;
    String name(String ym) => _monthNames[int.parse(ym.substring(5, 7)) - 1];
    Widget key(Color c, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Money in and out', style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.lg,
              children: [key(fin.income, 'In'), key(fin.expense, 'Out')],
            ),
            const SizedBox(height: Spacing.md),
            PairedBarChart(
              labels: [for (final m in months) name(m.month)],
              first: [for (final m in months) m.incomeMinor],
              second: [for (final m in months) m.expenseMinor],
              firstColor: fin.income,
              secondColor: fin.expense,
              semanticsLabel:
                  'Last ${months.length} months, in $currency: '
                  '${[for (final m in months) '${name(m.month)} in ${formatMinor(m.incomeMinor, currency)}, out ${formatMinor(m.expenseMinor, currency)}'].join('; ')}',
            ),
          ],
        ),
      ),
    );
  }
}
