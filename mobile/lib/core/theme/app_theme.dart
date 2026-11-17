import 'package:material_ui/material_ui.dart';

import 'app_colors.dart';
import 'finance_colors.dart';

/// Spacing scale from PLAN.md section 7b.
abstract final class Spacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class Radii {
  static const card = 16.0;
  static const button = 12.0;
}

/// Text style: Onest, 16 px regular with a 24 px line for body text.
abstract final class AppTypography {
  static const fontFamily = 'Onest';

  static const body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 24 / 16,
    letterSpacing: 0,
    color: AppColors.onSurface,
  );
}

abstract final class AppTheme {
  /// The colour scheme is filled from our tokens, not generated from a seed,
  /// so the exact palette is kept.
  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.primary,
    onPrimary: Colors.white,
    secondary: AppColors.secondary,
    onSecondary: AppColors.onSurface, // dark text on the light teal fill
    secondaryContainer: AppColors.secondary,
    onSecondaryContainer: AppColors.onSurface,
    error: AppColors.expense,
    onError: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.onSurface,
    onSurfaceVariant: AppColors.muted,
    outline: AppColors.outline,
    outlineVariant: AppColors.outline,
  );

  static ThemeData light() {
    const scheme = _lightScheme;
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: AppTypography.fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.canvas,
      extensions: const [FinanceColors.light],
    );

    return base.copyWith(
      textTheme: base.textTheme
          .copyWith(bodyLarge: AppTypography.body)
          .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.canvas,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: const BorderSide(color: AppColors.outline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // 48 dp tall (good touch target). Width is natural, so dialog
          // buttons sit side by side; form buttons stretch via their Column.
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.button),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: AppColors.secondary,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.button),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.button),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.button),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.button),
          borderSide: const BorderSide(color: AppColors.expense),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.button),
          borderSide: const BorderSide(color: AppColors.expense, width: 2),
        ),
        helperMaxLines: 2,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.outline,
        space: 1,
        thickness: 1,
      ),
    );
  }
}
