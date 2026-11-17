import 'package:hugeicons/hugeicons.dart';
import 'package:material_ui/material_ui.dart';

export 'package:hugeicons/hugeicons.dart' show HugeIcons;

/// One Hugeicons icon (SVG path data), e.g. `HugeIcons.strokeRoundedHome01`.
typedef AppIconData = List<List<dynamic>>;

/// The app's icon widget (Hugeicons, stroke rounded).
///
/// Unlike `HugeIcon`, it follows the surrounding [IconTheme] for size as
/// well as colour, so it behaves like Flutter's `Icon` inside buttons,
/// list tiles and the navigation bar.
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.strokeWidth,
    this.semanticLabel,
  });

  final AppIconData icon;
  final double? size;
  final Color? color;

  /// Line thickness. Hugeicons default is 1.5; a thicker line marks a
  /// selected item (there are no filled variants).
  final double? strokeWidth;

  final String? semanticLabel;

  /// Stroke used for selected items, e.g. the active navigation tab.
  static const selectedStroke = 2.2;

  @override
  Widget build(BuildContext context) {
    final icon = HugeIcon(
      icon: this.icon,
      size: size ?? IconTheme.of(context).size ?? 24,
      color: color,
      strokeWidth: strokeWidth,
    );
    final label = semanticLabel;
    if (label == null) return ExcludeSemantics(child: icon);
    return Semantics(
      label: label,
      child: ExcludeSemantics(child: icon),
    );
  }
}
