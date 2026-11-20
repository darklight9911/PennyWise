import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/responsive_layout.dart';

/// Dots showing how many digits are typed.
class PinDots extends StatelessWidget {
  const PinDots({super.key, required this.filled, required this.length});

  final int filled;
  final int length;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Semantics(
      label: '$filled of $length digits entered',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < length; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < filled ? c.primary : Colors.transparent,
                border: Border.all(
                  color: i < filled ? c.primary : c.onSurfaceVariant,
                  width: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A big number pad (72 dp keys). [extra] goes left of 0 (e.g. fingerprint).
/// Works without a Navigator or Overlay, so it can sit above the app.
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.extra,
    this.enabled = true,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final Widget? extra;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < Breakpoints.narrow || size.height < 680;
    final keySize = compact ? 60.0 : 68.0;
    final keyPadding = compact ? 4.0 : 6.0;
    Widget key(String d) => _Key(
      label: d,
      size: keySize,
      padding: keyPadding,
      onTap: enabled ? () => onDigit(d) : null,
      child: Text(d, style: Theme.of(context).textTheme.headlineSmall),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (final d in row) key(d)],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox.square(
              dimension: keySize + keyPadding * 2,
              child: Center(child: extra),
            ),
            key('0'),
            _Key(
              label: 'Delete last digit',
              size: keySize,
              padding: keyPadding,
              onTap: enabled ? onBackspace : null,
              child: const AppIcon(HugeIcons.strokeRoundedArrowLeft01),
            ),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.label,
    required this.size,
    required this.padding,
    required this.child,
    this.onTap,
  });

  final String label;
  final double size;
  final double padding;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(padding),
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: size,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}
