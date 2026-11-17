import 'dart:math' as math;

import 'package:uuid/uuid.dart';

/// Namespace for occurrence IDs. NEVER change it: the server
/// (backend/internal/recurring) uses the same value; a change would make the
/// phone and the server create duplicate bills.
const occurrenceNamespace = '3b8f1c2a-7d4e-4f6a-9c1b-2e5d8a7f6c90';

/// The fixed ID of a rule's occurrence on [date]:
/// `UUIDv5(namespace, "<rule id>:<YYYY-MM-DD>")`. Same as the server.
String occurrenceId(String ruleId, DateTime date) =>
    const Uuid().v5(occurrenceNamespace, '$ruleId:${ymd(date)}');

/// YYYY-MM-DD of a calendar day.
String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// A calendar day as UTC midnight (no time-zone surprises in arithmetic).
DateTime calendarDay(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// The schedule of a recurring rule.
class Recurrence {
  const Recurrence({
    required this.frequency,
    this.every = 1,
    required this.start,
    this.end,
  });

  /// daily, weekly, monthly or yearly
  final String frequency;
  final int every;
  final DateTime start;

  /// Inclusive; null = no end.
  final DateTime? end;

  static const _maxSteps = 10000;

  /// Occurrence dates within [from, to] (both inclusive), oldest first.
  /// Same rules as the server: monthly on the 31st falls on the last day
  /// of shorter months; 29 Feb falls on 28 Feb in other years.
  List<DateTime> dates(DateTime from, DateTime to) {
    final s = calendarDay(start);
    final f = calendarDay(from);
    var t = calendarDay(to);
    if (end != null && calendarDay(end!).isBefore(t)) t = calendarDay(end!);
    final step = math.max(every, 1);
    final out = <DateTime>[];
    for (var k = 0; k < _maxSteps; k++) {
      final d = _nth(s, k * step);
      if (d.isAfter(t)) break;
      if (!d.isBefore(f)) out.add(d);
    }
    return out;
  }

  /// The first occurrence on or after [from], or null.
  DateTime? next(DateTime from) {
    final years = frequency == 'yearly' ? 365 : 5;
    final f = calendarDay(from);
    final ds = dates(f, DateTime.utc(f.year + years, f.month, f.day));
    return ds.isEmpty ? null : ds.first;
  }

  DateTime _nth(DateTime s, int n) => switch (frequency) {
    'daily' => DateTime.utc(s.year, s.month, s.day + n),
    'weekly' => DateTime.utc(s.year, s.month, s.day + 7 * n),
    'yearly' => _clamped(s.year + n, s.month, s.day),
    _ => _clamped(
      s.year + (s.month - 1 + n) ~/ 12,
      (s.month - 1 + n) % 12 + 1,
      s.day,
    ),
  };

  static DateTime _clamped(int y, int m, int d) {
    final last = DateTime.utc(y, m + 1, 0).day;
    return DateTime.utc(y, m, math.min(d, last));
  }
}
