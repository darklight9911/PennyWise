import 'package:material_ui/material_ui.dart';

import '../theme/finance_colors.dart';
import '../utils/money.dart';

/// Shows a money amount with a +/− sign, tabular digits and the right colour.
///
/// [large] picks the brighter income green, which is only readable at large
/// sizes (PLAN.md 7b). Small text uses the darker `incomeText` green.
class AmountText extends StatelessWidget {
  const AmountText({
    super.key,
    required this.minor,
    required this.currency,
    this.style,
    this.large = false,
    this.signed = true,
  });

  final int minor;
  final String currency;
  final TextStyle? style;
  final bool large;

  /// False for neutral figures such as a balance, shown without sign or colour.
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final colors = context.financeColors;
    final Color? color = !signed || minor == 0
        ? null
        : minor > 0
        ? (large ? colors.income : colors.incomeText)
        : colors.expense;

    final base = style ?? DefaultTextStyle.of(context).style;
    return Text(
      signed ? formatSigned(minor, currency) : formatMinor(minor, currency),
      style: base.copyWith(
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
