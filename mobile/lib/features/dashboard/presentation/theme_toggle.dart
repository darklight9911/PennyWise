import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_icon.dart';
import '../../settings/application/theme_mode.dart';

/// Compact, animated theme toggle switch for the Dashboard AppBar.
/// Toggles between Light and Dark mode with smooth animation and tactile feedback.
class ThemeToggle extends ConsumerWidget {
  const ThemeToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themeModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Tooltip(
      message: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      child: Semantics(
        button: true,
        label: 'Appearance',
        toggled: isDark,
        child: InkWell(
          key: const ValueKey('theme_toggle'),
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticFeedback.selectionClick();
            final next = isDark ? ThemeMode.light : ThemeMode.dark;
            ref.read(themeModeProvider.notifier).set(next);
          },
          child: Container(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              width: 54,
              height: 28,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: isDark
                    ? AppDarkColors.secondary
                    : AppColors.outline.withValues(alpha: 0.6),
                border: Border.all(
                  color: isDark ? AppDarkColors.outline : AppColors.outline,
                  width: 1,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Subtle track icons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 3),
                        child: AppIcon(
                          HugeIcons.strokeRoundedSun01,
                          size: 13,
                          color: isDark
                              ? AppDarkColors.muted.withValues(alpha: 0.5)
                              : AppColors.primary.withValues(alpha: 0.8),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: AppIcon(
                          HugeIcons.strokeRoundedMoon02,
                          size: 13,
                          color: isDark
                              ? AppDarkColors.primary
                              : AppColors.muted.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                  // Sliding thumb with active icon
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    alignment: isDark
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark ? AppDarkColors.surface : Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Center(
                        child: AppIcon(
                          isDark
                              ? HugeIcons.strokeRoundedMoon02
                              : HugeIcons.strokeRoundedSun01,
                          size: 13,
                          color: isDark
                              ? AppDarkColors.primary
                              : AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
