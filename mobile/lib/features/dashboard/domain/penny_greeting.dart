import '../../../core/widgets/panda_mascot.dart';

/// What Penny says on the home screen, and how she looks saying it.
class PennyGreeting {
  const PennyGreeting(this.mood, this.message);

  final PandaMood mood;
  final String message;
}

/// Picks Penny's mood from this month's totals (base currency, minor units).
PennyGreeting pennyGreetingForMonth({
  required int incomeMinor,
  required int spentMinor,
}) {
  if (incomeMinor == 0 && spentMinor == 0) {
    return const PennyGreeting(
      PandaMood.wave,
      "Add your first income or expense and I'll keep an eye on your month.",
    );
  }
  if (spentMinor > incomeMinor) {
    return const PennyGreeting(
      PandaMood.worried,
      "You've spent more than you earned this month. "
      "Let's look at where it went.",
    );
  }
  if (spentMinor * 2 <= incomeMinor) {
    return const PennyGreeting(
      PandaMood.celebrate,
      "Great month so far: you're keeping more than half of what you earned.",
    );
  }
  return const PennyGreeting(
    PandaMood.happy,
    "You're on track this month. Nice work!",
  );
}
