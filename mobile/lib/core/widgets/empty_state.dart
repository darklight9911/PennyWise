import 'package:material_ui/material_ui.dart';

import 'app_icon.dart';
import '../theme/app_theme.dart';
import 'panda_mascot.dart';
import 'responsive_layout.dart';

/// Centered icon (or Penny) + title + message, for screens with no data yet.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.mascot,
    this.action,
  });

  final AppIconData icon;
  final String title;
  final String message;

  /// Penny in this mood replaces [icon] when animations are on.
  final PandaMood? mascot;

  /// Optional call-to-action displayed below [message].
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconWidget = AppIcon(
      icon,
      size: 48,
      color: theme.colorScheme.primary,
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: ContentWidths.narrow),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (mascot case final mood?)
                PandaMascot(mood: mood, size: 120, fallback: iconWidget)
              else
                iconWidget,
              const SizedBox(height: Spacing.md),
              Text(
                title,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: Spacing.lg),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
