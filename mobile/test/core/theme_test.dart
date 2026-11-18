import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pennywise/core/theme/app_colors.dart';
import 'package:pennywise/core/theme/app_theme.dart';
import 'package:pennywise/core/theme/finance_colors.dart';

void main() {
  final theme = AppTheme.light();

  test('all text uses the bundled Onest font', () {
    final t = theme.textTheme;
    for (final style in [
      t.displaySmall,
      t.titleLarge,
      t.titleSmall,
      t.bodyLarge,
      t.bodyMedium,
      t.bodySmall,
      t.labelLarge,
    ]) {
      expect(style?.fontFamily, 'Onest');
    }
  });

  test('body text is 16 px regular on a 24 px line, black at 87%', () {
    final body = theme.textTheme.bodyLarge!;
    expect(body.fontSize, 16);
    expect(body.fontWeight, FontWeight.w400);
    expect(body.fontSize! * body.height!, 24);
    expect(body.color, const Color(0xDE000000));
    expect(theme.colorScheme.onSurface, AppColors.onSurface);
  });

  test('the dark theme is dark and keeps the font', () {
    final dark = AppTheme.dark();
    expect(dark.brightness, Brightness.dark);
    expect(dark.textTheme.bodyLarge?.fontFamily, 'Onest');
    expect(dark.colorScheme.onSurface, AppDarkColors.onSurface);
  });

  _contrastGroup('light', AppTheme.light());
  _contrastGroup('dark', AppTheme.dark());
}

/// WCAG 2 contrast ratio of two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

// Every colour used for text must stay readable (4.5:1) on the canvas and
// on cards, in both themes.
void _contrastGroup(String name, ThemeData t) {
  group('$name theme contrast', () {
    final fin = t.extension<FinanceColors>()!;
    final backgrounds = {
      'canvas': t.scaffoldBackgroundColor,
      'surface': t.colorScheme.surface,
    };
    final texts = {
      'onSurface': t.colorScheme.onSurface.withValues(alpha: 1),
      'muted': t.colorScheme.onSurfaceVariant,
      'primary': t.colorScheme.primary,
      'incomeText': fin.incomeText,
      'expense': fin.expense,
      'warning': fin.warning,
    };
    for (final bg in backgrounds.entries) {
      for (final fg in texts.entries) {
        test('${fg.key} on ${bg.key}', () {
          expect(contrast(fg.value, bg.value), greaterThanOrEqualTo(4.5));
        });
      }
    }
    test('button text on primary', () {
      expect(
        contrast(t.colorScheme.onPrimary, t.colorScheme.primary),
        greaterThanOrEqualTo(4.5),
      );
    });
  });
}
