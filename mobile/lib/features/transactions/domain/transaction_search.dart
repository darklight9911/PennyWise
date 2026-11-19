import '../../../core/database/app_database.dart';
import '../../../core/utils/money.dart';
import '../../ledger/data/ledger_store.dart';
import '../../ledger/presentation/day_labels.dart';

/// Quick or custom date filters for the Transactions list.
enum DateFilterPreset {
  all,
  today,
  yesterday,
  thisWeek,
  thisMonth,
  customDate,
  customRange,
}

/// Formats [d] as a `YYYY-MM-DD` local date string.
String formatYmd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Inclusive date-range filter (`fromDate`..`toDate` in `YYYY-MM-DD`).
class TransactionDateFilter {
  const TransactionDateFilter({
    this.preset = DateFilterPreset.all,
    this.fromDate,
    this.toDate,
  });

  const TransactionDateFilter.all() : this();

  factory TransactionDateFilter.forPreset(
    DateFilterPreset preset,
    DateTime now,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (preset) {
      DateFilterPreset.all => const TransactionDateFilter.all(),
      DateFilterPreset.today => () {
        final ymd = formatYmd(today);
        return TransactionDateFilter(
          preset: DateFilterPreset.today,
          fromDate: ymd,
          toDate: ymd,
        );
      }(),
      DateFilterPreset.yesterday => () {
        final d = DateTime(today.year, today.month, today.day - 1);
        final ymd = formatYmd(d);
        return TransactionDateFilter(
          preset: DateFilterPreset.yesterday,
          fromDate: ymd,
          toDate: ymd,
        );
      }(),
      DateFilterPreset.thisWeek => () {
        final monday = DateTime(
          today.year,
          today.month,
          today.day - (today.weekday - 1),
        );
        final sunday = DateTime(monday.year, monday.month, monday.day + 6);
        return TransactionDateFilter(
          preset: DateFilterPreset.thisWeek,
          fromDate: formatYmd(monday),
          toDate: formatYmd(sunday),
        );
      }(),
      DateFilterPreset.thisMonth => () {
        final start = DateTime(today.year, today.month, 1);
        final end = DateTime(today.year, today.month + 1, 0);
        return TransactionDateFilter(
          preset: DateFilterPreset.thisMonth,
          fromDate: formatYmd(start),
          toDate: formatYmd(end),
        );
      }(),
      DateFilterPreset.customDate ||
      DateFilterPreset.customRange => const TransactionDateFilter.all(),
    };
  }

  factory TransactionDateFilter.singleDate(String ymd) => TransactionDateFilter(
    preset: DateFilterPreset.customDate,
    fromDate: ymd,
    toDate: ymd,
  );

  factory TransactionDateFilter.range(String a, String b) {
    final ordered = a.compareTo(b) <= 0 ? (a, b) : (b, a);
    return TransactionDateFilter(
      preset: DateFilterPreset.customRange,
      fromDate: ordered.$1,
      toDate: ordered.$2,
    );
  }

  final DateFilterPreset preset;
  final String? fromDate;
  final String? toDate;

  bool get isActive => fromDate != null || toDate != null;

  String label(DateTime now) {
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
        final d = fromDate;
        return d == null ? 'Pick date' : _shortDate(d, now);
      case DateFilterPreset.customRange:
        final f = fromDate;
        final t = toDate;
        if (f == null || t == null) return 'Date range';
        return '${_shortDate(f, now)} – ${_shortDate(t, now)}';
    }
  }

  @override
  bool operator ==(Object other) =>
      other is TransactionDateFilter &&
      other.preset == preset &&
      other.fromDate == fromDate &&
      other.toDate == toDate;

  @override
  int get hashCode => Object.hash(preset, fromDate, toDate);
}

const _shortMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _shortDate(String ymd, DateTime now) {
  final d = DateTime.parse(ymd);
  final base = '${d.day} ${_shortMonths[d.month - 1]}';
  return d.year == now.year ? base : '$base ${d.year}';
}

/// Returns the sublist of [sortedDesc] (ordered descending by `localDate`)
/// whose `localDate` lies within inclusive `[fromDate, toDate]` in `O(log N)`.
List<MoneyTransaction> sliceByDateRange(
  List<MoneyTransaction> sortedDesc, {
  String? fromDate,
  String? toDate,
}) {
  if (sortedDesc.isEmpty) return const [];
  if (fromDate != null && toDate != null && fromDate.compareTo(toDate) > 0) {
    return const [];
  }

  var start = 0;
  if (toDate != null) {
    var lo = 0;
    var hi = sortedDesc.length;
    while (lo < hi) {
      final mid = lo + ((hi - lo) >> 1);
      if (sortedDesc[mid].localDate.compareTo(toDate) <= 0) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    start = lo;
  }

  var end = sortedDesc.length;
  if (fromDate != null) {
    var lo = start;
    var hi = sortedDesc.length;
    while (lo < hi) {
      final mid = lo + ((hi - lo) >> 1);
      if (sortedDesc[mid].localDate.compareTo(fromDate) < 0) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    end = lo;
  }

  return sortedDesc.sublist(start, end);
}

const _monthLookup = <String, int>{
  'jan': 1,
  'january': 1,
  'feb': 2,
  'february': 2,
  'mar': 3,
  'march': 3,
  'apr': 4,
  'april': 4,
  'may': 5,
  'jun': 6,
  'june': 6,
  'jul': 7,
  'july': 7,
  'aug': 8,
  'august': 8,
  'sep': 9,
  'sept': 9,
  'september': 9,
  'oct': 10,
  'october': 10,
  'nov': 11,
  'november': 11,
  'dec': 12,
  'december': 12,
};

DateTime? _validDate(int y, int m, int d) {
  if (y < 1970 || y > 2100 || m < 1 || m > 12 || d < 1 || d > 31) {
    return null;
  }
  final dt = DateTime(y, m, d);
  if (dt.year != y || dt.month != m || dt.day != d) return null;
  return dt;
}

({String fromDate, String toDate})? _monthSpan(int y, int m) {
  if (y < 1970 || y > 2100 || m < 1 || m > 12) return null;
  final first = DateTime(y, m, 1);
  final last = DateTime(y, m + 1, 0);
  return (fromDate: formatYmd(first), toDate: formatYmd(last));
}

/// Parses natural and structured date queries (`today`, `yesterday`,
/// `this week`, `last week`, `this month`, `last month`, `2026-11-20`,
/// `20/11/2026`, `2026-11`, `2026`, `20 nov`, `nov 20, 2025`, `november`).
/// Returns `null` when [raw] is not a valid date query.
({String fromDate, String toDate})? parseDateQuery(String raw, DateTime now) {
  final q = raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (q.isEmpty) return null;

  final today = DateTime(now.year, now.month, now.day);
  switch (q) {
    case 'today':
      final ymd = formatYmd(today);
      return (fromDate: ymd, toDate: ymd);
    case 'yesterday':
      final ymd = formatYmd(DateTime(today.year, today.month, today.day - 1));
      return (fromDate: ymd, toDate: ymd);
    case 'this week':
      final f = TransactionDateFilter.forPreset(DateFilterPreset.thisWeek, now);
      return (fromDate: f.fromDate!, toDate: f.toDate!);
    case 'last week':
      final mondayThis = DateTime(
        today.year,
        today.month,
        today.day - (today.weekday - 1),
      );
      final mondayLast = DateTime(
        mondayThis.year,
        mondayThis.month,
        mondayThis.day - 7,
      );
      final sundayLast = DateTime(
        mondayThis.year,
        mondayThis.month,
        mondayThis.day - 1,
      );
      return (fromDate: formatYmd(mondayLast), toDate: formatYmd(sundayLast));
    case 'this month':
      final f = TransactionDateFilter.forPreset(
        DateFilterPreset.thisMonth,
        now,
      );
      return (fromDate: f.fromDate!, toDate: f.toDate!);
    case 'last month':
      final first = DateTime(today.year, today.month - 1, 1);
      final last = DateTime(today.year, today.month, 0);
      return (fromDate: formatYmd(first), toDate: formatYmd(last));
  }

  // YYYY-MM-DD or YYYY/MM/DD
  final isoDay = RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})$').firstMatch(q);
  if (isoDay != null) {
    final dt = _validDate(
      int.parse(isoDay.group(1)!),
      int.parse(isoDay.group(2)!),
      int.parse(isoDay.group(3)!),
    );
    if (dt == null) return null;
    final ymd = formatYmd(dt);
    return (fromDate: ymd, toDate: ymd);
  }

  // DD/MM/YYYY or DD-MM-YYYY
  final dmyDay = RegExp(r'^(\d{1,2})[-/](\d{1,2})[-/](\d{4})$').firstMatch(q);
  if (dmyDay != null) {
    final dt = _validDate(
      int.parse(dmyDay.group(3)!),
      int.parse(dmyDay.group(2)!),
      int.parse(dmyDay.group(1)!),
    );
    if (dt == null) return null;
    final ymd = formatYmd(dt);
    return (fromDate: ymd, toDate: ymd);
  }

  // YYYY-MM or YYYY/MM
  final ym = RegExp(r'^(\d{4})[-/](\d{1,2})$').firstMatch(q);
  if (ym != null) {
    return _monthSpan(int.parse(ym.group(1)!), int.parse(ym.group(2)!));
  }

  // YYYY
  final yearOnly = RegExp(r'^(\d{4})$').firstMatch(q);
  if (yearOnly != null) {
    final y = int.parse(yearOnly.group(1)!);
    if (y < 1970 || y > 2100) return null;
    return (fromDate: '$y-01-01', toDate: '$y-12-31');
  }

  // DD Mon [YYYY]
  final dayMonth = RegExp(r'^(\d{1,2}) ([a-z]+)(?: (\d{4}))?$').firstMatch(q);
  if (dayMonth != null) {
    final m = _monthLookup[dayMonth.group(2)!];
    if (m == null) return null;
    final y = dayMonth.group(3) != null
        ? int.parse(dayMonth.group(3)!)
        : now.year;
    final dt = _validDate(y, m, int.parse(dayMonth.group(1)!));
    if (dt == null) return null;
    final ymd = formatYmd(dt);
    return (fromDate: ymd, toDate: ymd);
  }

  // Mon DD[,] [YYYY]
  final monthDay = RegExp(r'^([a-z]+) (\d{1,2})(?:,? (\d{4}))?$').firstMatch(q);
  if (monthDay != null) {
    final m = _monthLookup[monthDay.group(1)!];
    if (m == null) return null;
    final y = monthDay.group(3) != null
        ? int.parse(monthDay.group(3)!)
        : now.year;
    final dt = _validDate(y, m, int.parse(monthDay.group(2)!));
    if (dt == null) return null;
    final ymd = formatYmd(dt);
    return (fromDate: ymd, toDate: ymd);
  }

  // Month [YYYY]
  final monthOnly = RegExp(r'^([a-z]+)(?: (\d{4}))?$').firstMatch(q);
  if (monthOnly != null) {
    final m = _monthLookup[monthOnly.group(1)!];
    if (m == null) return null;
    final y = monthOnly.group(2) != null
        ? int.parse(monthOnly.group(2)!)
        : now.year;
    return _monthSpan(y, m);
  }

  return null;
}

/// Output of [filterTransactions] along with integer summary totals in the
/// user's main currency.
class TransactionSearchResult {
  const TransactionSearchResult({
    required this.items,
    required this.incomeMinor,
    required this.expenseMinor,
    required this.missingRate,
    this.effectiveFrom,
    this.effectiveTo,
    this.matchedDateQuery = false,
  });

  final List<MoneyTransaction> items;
  final int incomeMinor;
  final int expenseMinor;
  final int missingRate;
  final String? effectiveFrom;
  final String? effectiveTo;
  final bool matchedDateQuery;
}

String? _maxDate(String? a, String? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.compareTo(b) >= 0 ? a : b;
}

String? _minDate(String? a, String? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.compareTo(b) <= 0 ? a : b;
}

/// Filters [transactions] (ordered descending by `localDate`) by [dateFilter]
/// and [query], slicing the date bounds in `O(log N)` before running multi-token
/// text matching and exact integer aggregation in [baseCurrency].
TransactionSearchResult filterTransactions({
  required List<MoneyTransaction> transactions,
  required DateTime now,
  required String baseCurrency,
  TransactionDateFilter dateFilter = const TransactionDateFilter.all(),
  String query = '',
  Map<String, Category> categories = const {},
  Map<String, Account> accounts = const {},
}) {
  final trimmed = query.trim();
  final queryDate = parseDateQuery(trimmed, now);

  final effectiveFrom = _maxDate(dateFilter.fromDate, queryDate?.fromDate);
  final effectiveTo = _minDate(dateFilter.toDate, queryDate?.toDate);

  var items = sliceByDateRange(
    transactions,
    fromDate: effectiveFrom,
    toDate: effectiveTo,
  );

  if (trimmed.isNotEmpty && queryDate == null && items.isNotEmpty) {
    final tokens = trimmed.toLowerCase().split(RegExp(r'\s+'));
    items = [
      for (final t in items)
        if (_matchesAllTokens(
          t,
          tokens,
          now: now,
          categories: categories,
          accounts: accounts,
        ))
          t,
    ];
  }

  var income = 0;
  var expense = 0;
  var missing = 0;
  for (final t in items) {
    if (t.kind != TxKind.income && t.kind != TxKind.expense) continue;
    final baseAmount =
        t.amountBaseMinor ??
        (t.currency == baseCurrency ? t.amountMinor : null);
    if (baseAmount == null) {
      missing++;
      continue;
    }
    if (t.kind == TxKind.income) {
      income += baseAmount;
    } else {
      expense += baseAmount;
    }
  }

  return TransactionSearchResult(
    items: items,
    incomeMinor: income,
    expenseMinor: expense,
    missingRate: missing,
    effectiveFrom: effectiveFrom,
    effectiveTo: effectiveTo,
    matchedDateQuery: queryDate != null,
  );
}

bool _matchesAllTokens(
  MoneyTransaction t,
  List<String> tokens, {
  required DateTime now,
  required Map<String, Category> categories,
  required Map<String, Account> accounts,
}) {
  final cat = t.categoryId != null ? categories[t.categoryId] : null;
  final parentCat = cat?.parentId != null ? categories[cat!.parentId] : null;
  final acct = accounts[t.accountId];
  final transferAcct = t.transferAccountId != null
      ? accounts[t.transferAccountId]
      : null;

  final haystack = [
    t.note,
    ?cat?.name,
    ?parentCat?.name,
    ?acct?.name,
    ?transferAcct?.name,
    t.kind,
    t.currency,
    formatMinor(t.amountMinor, t.currency),
    t.localDate,
    dayLabel(t.localDate, now),
  ].join(' ').toLowerCase();

  return tokens.every(haystack.contains);
}
