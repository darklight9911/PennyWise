import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pennywise/core/theme/app_colors.dart';
import 'package:pennywise/core/theme/app_theme.dart';

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
}
