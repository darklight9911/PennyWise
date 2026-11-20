import 'package:material_ui/material_ui.dart';

import '../widgets/responsive_layout.dart';
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

  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppDarkColors.primary,
    onPrimary: AppDarkColors.onPrimary,
    secondary: AppDarkColors.secondary,
    onSecondary: AppDarkColors.onSurface,
    secondaryContainer: AppDarkColors.secondary,
    onSecondaryContainer: AppDarkColors.onSurface,
    error: AppDarkColors.expense,
    onError: AppDarkColors.onPrimary,
    surface: AppDarkColors.surface,
    onSurface: AppDarkColors.onSurface,
    onSurfaceVariant: AppDarkColors.muted,
    outline: AppDarkColors.outline,
    outlineVariant: AppDarkColors.outline,
  );

  static ThemeData light() => _build(
    scheme: _lightScheme,
    canvas: AppColors.canvas,
    outline: AppColors.outline,
    finance: FinanceColors.light,
  );

  static ThemeData dark() => _build(
    scheme: _darkScheme,
    canvas: AppDarkColors.canvas,
    outline: AppDarkColors.outline,
    finance: FinanceColors.dark,
  );

  static ThemeData _build({
    required ColorScheme scheme,
    required Color canvas,
    required Color outline,
    required FinanceColors finance,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      fontFamily: AppTypography.fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      extensions: [finance],
    );

    return base.copyWith(
      materialTapTargetSize: MaterialTapTargetSize.padded,
      textTheme: base.textTheme
          .copyWith(bodyLarge: AppTypography.body)
          .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
      appBarTheme: AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 52,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: BorderSide(color: outline),
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
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.button),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.button),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: const VisualDensity(vertical: -1),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.secondaryContainer,
        surfaceTintColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.secondaryContainer,
        labelType: NavigationRailLabelType.all,
        minWidth: 76,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: Spacing.lg),
        minVerticalPadding: 6,
        horizontalTitleGap: Spacing.md,
        minTileHeight: 52,
      ),
      chipTheme: base.chipTheme.copyWith(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm,
          vertical: 4,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        constraints: const BoxConstraints(maxWidth: ContentWidths.form),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.card)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        constraints: const BoxConstraints(maxWidth: ContentWidths.form),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.button),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.button),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.button),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.button),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.button),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        helperMaxLines: 2,
      ),
      dividerTheme: DividerThemeData(color: outline, space: 1, thickness: 1),
    );
  }
}
