import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Viewport width breakpoints for responsive layouts.
abstract final class Breakpoints {
  /// Extra-narrow phones (320 px class).
  static const narrow = 360.0;

  /// Compact phone upper bound.
  static const compact = 600.0;

  /// Switch from bottom `NavigationBar` to side `NavigationRail`.
  static const rail = 720.0;
}

/// Maximum readable content widths on wide viewports.
abstract final class ContentWidths {
  /// Centered narrow flows: auth screens, PIN lock, empty stages.
  static const narrow = 440.0;

  /// Forms, dialogs and modal sheets.
  static const form = 560.0;

  /// Primary screens, lists and detail pages.
  static const content = 720.0;
}

/// Shared layout queries and adaptive spacing helpers.
abstract final class ResponsiveLayout {
  static double horizontalPadding(BuildContext context) =>
      MediaQuery.sizeOf(context).width < Breakpoints.narrow
      ? Spacing.md
      : Spacing.lg;

  static bool useRail(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= Breakpoints.rail;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < Breakpoints.compact;
}

/// Caps horizontal width on tablets and desktop browsers while preserving
/// top-aligned scrolling height for `ListView` and `Expanded` children.
class ResponsiveBody extends StatelessWidget {
  const ResponsiveBody({
    super.key,
    required this.child,
    this.maxWidth = ContentWidths.content,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
