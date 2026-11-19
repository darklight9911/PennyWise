import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/amount_text.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/panda_mascot.dart';
import '../../auth/application/auth_controller.dart';
import '../../ledger/application/ledger_providers.dart';
import '../../ledger/presentation/day_labels.dart';
import '../../ledger/presentation/transaction_tile.dart';
import '../../sync/sync_controller.dart';
import '../domain/transaction_search.dart';
import 'empty_transactions_stage.dart';

/// Every transaction, newest first, with date-wise and keyword search.
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  TransactionDateFilter _dateFilter = const TransactionDateFilter.all();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _dateFilter = const TransactionDateFilter.all();
    });
  }

  DateTime _clampDate(DateTime date, DateTime first, DateTime last) {
    if (date.isBefore(first)) return first;
    if (date.isAfter(last)) return last;
    return date;
  }

  DateTime _pickerFirstDate() => DateTime(2000);

  DateTime _pickerLastDate(DateTime now) => DateTime(now.year + 5, 12, 31);

  Future<void> _pickSingleDate(BuildContext context, DateTime now) async {
    final first = _pickerFirstDate();
    final last = _pickerLastDate(now);
    final current = _dateFilter.fromDate != null
        ? DateTime.tryParse(_dateFilter.fromDate!) ?? now
        : now;
    final picked = await showDatePicker(
      context: context,
      initialDate: _clampDate(current, first, last),
      firstDate: first,
      lastDate: last,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _dateFilter = TransactionDateFilter.singleDate(formatYmd(picked));
    });
  }

  Future<void> _pickDateRange(BuildContext context, DateTime now) async {
    final first = _pickerFirstDate();
    final last = _pickerLastDate(now);
    DateTimeRange? initialRange;
    if (_dateFilter.fromDate != null && _dateFilter.toDate != null) {
      final start = DateTime.tryParse(_dateFilter.fromDate!);
      final end = DateTime.tryParse(_dateFilter.toDate!);
      if (start != null && end != null && !start.isAfter(end)) {
        initialRange = DateTimeRange(
          start: _clampDate(start, first, last),
          end: _clampDate(end, first, last),
        );
      }
    }
    final picked = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDateRange: initialRange,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _dateFilter = TransactionDateFilter.range(
        formatYmd(picked.start),
        formatYmd(picked.end),
      );
    });
  }

  String _presetChipLabel(DateFilterPreset preset) {
    switch (preset) {
      case DateFilterPreset.all:
        return 'All';
      case DateFilterPreset.today:
        return 'Today';
      case DateFilterPreset.yesterday:
        return 'Yesterday';
      case DateFilterPreset.thisWeek:
        return 'This week';
      case DateFilterPreset.thisMonth:
        return 'This month';
      case DateFilterPreset.customDate:
        return 'Pick date';
      case DateFilterPreset.customRange:
        return 'Date range';
    }
  }

  String _summaryHeader(TransactionSearchResult result, DateTime now) {
    final count = result.items.length;
    final countLabel = '$count ${count == 1 ? 'transaction' : 'transactions'}';
    if (_dateFilter.isActive) {
      return '${_dateFilter.label(now)} · $countLabel';
    }
    if (result.matchedDateQuery &&
        result.effectiveFrom != null &&
        result.effectiveTo != null) {
      final from = result.effectiveFrom!;
      final to = result.effectiveTo!;
      final scope = from == to
          ? dayLabel(from, now)
          : '${dayLabel(from, now)} – ${dayLabel(to, now)}';
      return '$scope · $countLabel';
    }
    return countLabel;
  }

  String _noMatchMessage(DateTime now) {
    final trimmed = _query.trim();
    if (_dateFilter.isActive && trimmed.isNotEmpty) {
      return 'Nothing found for "$trimmed" in ${_dateFilter.label(now)}.';
    }
    if (_dateFilter.isActive) {
      return 'No transactions recorded for ${_dateFilter.label(now)}.';
    }
    return 'No transactions match "$trimmed". Try a date like "today" or "2026-11-16", a note, or an amount.';
  }

  Widget _buildLoadedBody(BuildContext context, List<MoneyTransaction> list) {
    final now = DateTime.now();
    final auth = ref.watch(authControllerProvider);
    final baseCurrency = auth is SignedIn ? auth.user.baseCurrency : 'USD';
    final categories =
        ref.watch(categoryIndexProvider).value ?? const <String, Category>{};
    final accounts = <String, Account>{
      for (final a in ref.watch(accountsProvider).value ?? const <Account>[])
        a.id: a,
    };

    final result = filterTransactions(
      transactions: list,
      now: now,
      baseCurrency: baseCurrency,
      dateFilter: _dateFilter,
      query: _query,
      categories: categories,
      accounts: accounts,
    );
    final hasActiveFilter = _dateFilter.isActive || _query.trim().isNotEmpty;
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            Spacing.sm,
            Spacing.lg,
            Spacing.xs,
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search date, note, category or amount',
              prefixIcon: const AppIcon(HugeIcons.strokeRoundedSearch01),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const AppIcon(HugeIcons.strokeRoundedCancel01),
                    )
                  : null,
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: Spacing.xs,
          ),
          child: Row(
            children: [
              for (final preset in const [
                DateFilterPreset.all,
                DateFilterPreset.today,
                DateFilterPreset.yesterday,
                DateFilterPreset.thisWeek,
                DateFilterPreset.thisMonth,
              ]) ...[
                ChoiceChip(
                  label: Text(_presetChipLabel(preset)),
                  selected: _dateFilter.preset == preset,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (_) => setState(() {
                    _dateFilter = preset == DateFilterPreset.all
                        ? const TransactionDateFilter.all()
                        : TransactionDateFilter.forPreset(preset, now);
                  }),
                ),
                const SizedBox(width: Spacing.sm),
              ],
              ChoiceChip(
                avatar: const AppIcon(
                  HugeIcons.strokeRoundedCalendar01,
                  size: 18,
                ),
                label: Text(
                  _dateFilter.preset == DateFilterPreset.customDate
                      ? _dateFilter.label(now)
                      : 'Pick date',
                ),
                selected: _dateFilter.preset == DateFilterPreset.customDate,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (_) => _pickSingleDate(context, now),
              ),
              const SizedBox(width: Spacing.sm),
              ChoiceChip(
                avatar: const AppIcon(
                  HugeIcons.strokeRoundedCalendar03,
                  size: 18,
                ),
                label: Text(
                  _dateFilter.preset == DateFilterPreset.customRange
                      ? _dateFilter.label(now)
                      : 'Date range',
                ),
                selected: _dateFilter.preset == DateFilterPreset.customRange,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (_) => _pickDateRange(context, now),
              ),
            ],
          ),
        ),
        if (hasActiveFilter && result.items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.xs,
              Spacing.lg,
              Spacing.xs,
            ),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: Spacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _summaryHeader(result, now),
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: _resetFilters,
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: Spacing.lg,
                      runSpacing: Spacing.xs,
                      children: [
                        _FilterFigure(
                          label: 'Income',
                          minor: result.incomeMinor,
                          currency: baseCurrency,
                        ),
                        _FilterFigure(
                          label: 'Spent',
                          minor: -result.expenseMinor,
                          currency: baseCurrency,
                        ),
                      ],
                    ),
                    if (result.missingRate > 0) ...[
                      const SizedBox(height: Spacing.xs),
                      Text(
                        '${result.missingRate} '
                        '${result.missingRate == 1 ? 'transaction' : 'transactions'} '
                        'waiting for an exchange rate',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child: result.items.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    EmptyState(
                      mascot: PandaMood.thinking,
                      icon: HugeIcons.strokeRoundedSearch01,
                      title: 'No matching transactions',
                      message: _noMatchMessage(now),
                      action: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(64, 48),
                        ),
                        onPressed: _resetFilters,
                        child: const Text('Reset filters'),
                      ),
                    ),
                  ],
                )
              : _GroupedList(transactions: result.items),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final transactions = ref.watch(transactionsProvider(null));
    return Scaffold(
      appBar: AppBar(title: const Text('Transactions')),
      floatingActionButton: FloatingActionButton(
        // Tabs stay alive side by side: no shared hero animation tag.
        heroTag: null,
        tooltip: 'Add transaction',
        onPressed: () => context.push(Routes.newTransaction()),
        child: const AppIcon(HugeIcons.strokeRoundedPlusSign),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(syncControllerProvider.notifier).syncNow(),
        child: transactions.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load: $e')),
          data: (list) => list.isEmpty
              ? ListView(
                  // Scrollable, so pull-to-refresh works on the empty state.
                  children: const [EmptyTransactionsStage()],
                )
              : _buildLoadedBody(context, list),
        ),
      ),
    );
  }
}

class _FilterFigure extends StatelessWidget {
  const _FilterFigure({
    required this.label,
    required this.minor,
    required this.currency,
  });

  final String label;
  final int minor;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        AmountText(
          minor: minor,
          currency: currency,
          style: theme.textTheme.labelLarge,
        ),
      ],
    );
  }
}

class _GroupedList extends StatelessWidget {
  const _GroupedList({required this.transactions});

  final List<MoneyTransaction> transactions;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final rows = <Widget>[];
    String? day;
    for (final t in transactions) {
      if (t.localDate != day) {
        day = t.localDate;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.lg,
              Spacing.lg,
              Spacing.xs,
            ),
            child: Text(
              dayLabel(day, now),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }
      rows.add(TransactionTile(transaction: t));
    }
    return ListView(padding: const EdgeInsets.only(bottom: 96), children: rows);
  }
}
