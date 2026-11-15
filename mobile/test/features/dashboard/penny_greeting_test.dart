import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/core/widgets/panda_mascot.dart';
import 'package:pennywise/features/dashboard/domain/penny_greeting.dart';

void main() {
  PandaMood moodFor(int income, int spent) =>
      pennyGreetingForMonth(incomeMinor: income, spentMinor: spent).mood;

  test('waves hello before there is any money in the month', () {
    expect(moodFor(0, 0), PandaMood.wave);
  });

  test('is worried when spending is above income', () {
    expect(moodFor(100000, 100001), PandaMood.worried);
    expect(moodFor(0, 500), PandaMood.worried);
  });

  test('celebrates when at least half the income is kept', () {
    expect(moodFor(100000, 50000), PandaMood.celebrate);
    expect(moodFor(100000, 0), PandaMood.celebrate);
  });

  test('is happy when spending is under income but over half', () {
    expect(moodFor(100000, 50001), PandaMood.happy);
    expect(moodFor(100000, 100000), PandaMood.happy);
  });

  test('every greeting has a message', () {
    for (final (income, spent) in [(0, 0), (1, 2), (2, 1), (4, 3)]) {
      final g = pennyGreetingForMonth(incomeMinor: income, spentMinor: spent);
      expect(g.message, isNotEmpty);
    }
  });
}
