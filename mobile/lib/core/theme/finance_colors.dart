import 'package:material_ui/material_ui.dart';

import 'app_colors.dart';

/// Colours that Material's ColorScheme has no slot for.
@immutable
class FinanceColors extends ThemeExtension<FinanceColors> {
  const FinanceColors({
    required this.income,
    required this.incomeText,
    required this.expense,
    required this.muted,
    required this.warning,
  });

  /// Large income amounts (24 px+, or 18.7 px+ bold), icons and charts.
  final Color income;

  /// Small income text. Passes 4.5:1 contrast on canvas and surface.
  final Color incomeText;

  /// Expense amounts, any size.
  final Color expense;

  /// Secondary text such as labels and dates.
  final Color muted;

  /// Close to a limit (budgets at 80 %).
  final Color warning;

  static const light = FinanceColors(
    income: AppColors.income,
    incomeText: AppColors.incomeText,
    expense: AppColors.expense,
    muted: AppColors.muted,
    warning: AppColors.warning,
  );

  static const dark = FinanceColors(
    income: AppDarkColors.income,
    incomeText: AppDarkColors.incomeText,
    expense: AppDarkColors.expense,
    muted: AppDarkColors.muted,
    warning: AppDarkColors.warning,
  );

  @override
  FinanceColors copyWith({
    Color? income,
    Color? incomeText,
    Color? expense,
    Color? muted,
    Color? warning,
  }) {
    return FinanceColors(
      income: income ?? this.income,
      incomeText: incomeText ?? this.incomeText,
      expense: expense ?? this.expense,
      muted: muted ?? this.muted,
      warning: warning ?? this.warning,
    );
  }

  @override
  FinanceColors lerp(FinanceColors? other, double t) {
    if (other == null) return this;
    return FinanceColors(
      income: Color.lerp(income, other.income, t)!,
      incomeText: Color.lerp(incomeText, other.incomeText, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}

extension FinanceColorsX on BuildContext {
  FinanceColors get financeColors =>
      Theme.of(this).extension<FinanceColors>() ?? FinanceColors.light;
}
