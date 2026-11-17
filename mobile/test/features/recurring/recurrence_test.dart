import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/features/recurring/domain/recurrence.dart';

DateTime d(String s) => DateTime.parse('${s}T00:00:00Z');

void main() {
  test('occurrence id matches the server (pinned in occurrence_test.go)', () {
    expect(
      occurrenceId(
        '01934f2a-0000-7000-8000-000000000001',
        DateTime(2026, 11, 18, 13, 5),
      ),
      '91d57823-5af7-50f8-8ba5-02fa79d1df94',
    );
  });

  // The same cases as backend/internal/recurring/dates_test.go.
  final cases = <(String, Recurrence, String, String, String)>[
    (
      'daily',
      Recurrence(frequency: 'daily', start: d('2026-01-30')),
      '2026-01-01',
      '2026-02-02',
      '2026-01-30 2026-01-31 2026-02-01 2026-02-02',
    ),
    (
      'every 3 days from the middle',
      Recurrence(frequency: 'daily', every: 3, start: d('2026-01-01')),
      '2026-01-05',
      '2026-01-12',
      '2026-01-07 2026-01-10',
    ),
    (
      'weekly',
      Recurrence(frequency: 'weekly', start: d('2026-11-02')),
      '2026-11-01',
      '2026-11-30',
      '2026-11-02 2026-11-09 2026-11-16 2026-11-23 2026-11-30',
    ),
    (
      'every 2 weeks',
      Recurrence(frequency: 'weekly', every: 2, start: d('2026-11-02')),
      '2026-11-01',
      '2026-11-30',
      '2026-11-02 2026-11-16 2026-11-30',
    ),
    (
      'monthly on the 31st',
      Recurrence(frequency: 'monthly', start: d('2026-01-31')),
      '2026-01-01',
      '2026-05-31',
      '2026-01-31 2026-02-28 2026-03-31 2026-04-30 2026-05-31',
    ),
    (
      'monthly in a leap year',
      Recurrence(frequency: 'monthly', start: d('2028-01-31')),
      '2028-02-01',
      '2028-02-29',
      '2028-02-29',
    ),
    (
      'every 3 months over a year end',
      Recurrence(frequency: 'monthly', every: 3, start: d('2026-11-15')),
      '2026-01-01',
      '2027-12-31',
      '2026-11-15 2027-02-15 2027-05-15 2027-08-15 2027-11-15',
    ),
    (
      'yearly on 29 Feb',
      Recurrence(frequency: 'yearly', start: d('2028-02-29')),
      '2028-01-01',
      '2032-12-31',
      '2028-02-29 2029-02-28 2030-02-28 2031-02-28 2032-02-29',
    ),
    (
      'ends',
      Recurrence(
        frequency: 'monthly',
        start: d('2026-04-01'),
        end: d('2026-06-30'),
      ),
      '2026-01-01',
      '2026-12-31',
      '2026-04-01 2026-05-01 2026-06-01',
    ),
    (
      'not started yet',
      Recurrence(frequency: 'daily', start: d('2027-01-01')),
      '2026-01-01',
      '2026-12-31',
      '',
    ),
  ];
  for (final (name, r, from, to, want) in cases) {
    test(name, () {
      expect(r.dates(d(from), d(to)).map(ymd).join(' '), want);
    });
  }

  test('next', () {
    final r = Recurrence(frequency: 'monthly', start: d('2026-01-31'));
    expect(ymd(r.next(d('2026-02-01'))!), '2026-02-28');
    final ended = Recurrence(
      frequency: 'monthly',
      start: d('2026-01-31'),
      end: d('2026-03-01'),
    );
    expect(ended.next(d('2026-03-02')), isNull);
  });
}
