import 'package:material_ui/material_ui.dart';

/// Raw colour tokens from PLAN.md section 7b.
///
/// Widgets should not use these directly. Use `Theme.of(context).colorScheme`
/// or `context.financeColors` so dark mode can swap them later.
abstract final class AppColors {
  // Given palette
  static const primary = Color(0xFF2C706E);
  static const secondary = Color(0xFF729D99); // fills only, never text
  static const canvas = Color(0xFFEEE9E0);

  // Derived
  static const surface = Color(0xFFFBF9F5);
  static const onSurface = Color(0xDE000000); // black at 87%, main text
  static const muted = Color(0xFF5C6B69);
  static const outline = Color(0xFFD9D2C5);

  // Money
  static const income = Color(0xFF388D3D); // large amounts, icons, charts
  static const incomeText = Color(0xFF2F7734); // small income text
  static const expense = Color(0xFFBA1120);

  /// Amber for "close to the limit" (budgets at 80 %). 5:1 on canvas.
  static const warning = Color(0xFF8F5400);
}

/// Dark-mode tokens: the same teal palette, lightened for a dark canvas.
/// Every text colour reaches at least 4.5:1 on canvas and surface (checked
/// with the WCAG formula when they were chosen).
abstract final class AppDarkColors {
  static const primary = Color(0xFF7CC4BF); // 7.9:1 on surface
  static const onPrimary = Color(0xFF0B2B29);
  static const secondary = Color(0xFF3E6663); // fills only
  static const canvas = Color(0xFF121917);
  static const surface = Color(0xFF1B2422);
  static const onSurface = Color(0xFFE9E5DD);
  static const muted = Color(0xFFA9B5B2);
  static const outline = Color(0xFF33403E);
  static const income = Color(0xFF6FC774);
  static const incomeText = Color(0xFF7ED183);
  static const expense = Color(0xFFFF7A80);
  static const warning = Color(0xFFF0B45C);
}
