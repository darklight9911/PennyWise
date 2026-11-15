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
  static const onSurface = Color(0xFF1F2A29);
  static const muted = Color(0xFF5C6B69);
  static const outline = Color(0xFFD9D2C5);

  // Money
  static const income = Color(0xFF388D3D); // large amounts, icons, charts
  static const incomeText = Color(0xFF2F7734); // small income text
  static const expense = Color(0xFFBA1120);
}
