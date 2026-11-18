import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// A ring split into slices (spending by category).
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.values,
    required this.colors,
    required this.semanticsLabel,
    this.center,
  });

  final List<int> values;
  final List<Color> colors;
  final String semanticsLabel;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      image: true,
      child: AspectRatio(
        aspectRatio: 1,
        child: CustomPaint(
          painter: _DonutPainter(
            values,
            colors,
            Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: Center(child: center),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.values, this.colors, this.track);

  final List<int> values;
  final List<Color> colors;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.16;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = track);
    final total = values.fold<int>(0, (a, b) => a + b);
    if (total <= 0) return;
    // A small gap between slices keeps neighbours apart.
    const gap = 0.012;
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = 2 * math.pi * values[i] / total;
      final g = values.length > 1 && sweep > 2 * gap ? gap : 0.0;
      canvas.drawArc(
        rect,
        start + g,
        sweep - 2 * g,
        false,
        paint..color = colors[i],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.values != values || old.colors != colors || old.track != track;
}

/// Pairs of bars (money in, money out) per period.
class PairedBarChart extends StatelessWidget {
  const PairedBarChart({
    super.key,
    required this.labels,
    required this.first,
    required this.second,
    required this.firstColor,
    required this.secondColor,
    required this.semanticsLabel,
  });

  final List<String> labels;
  final List<int> first;
  final List<int> second;
  final Color firstColor;
  final Color secondColor;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelSmall!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Semantics(
      label: semanticsLabel,
      image: true,
      child: Column(
        children: [
          SizedBox(
            height: 140,
            child: CustomPaint(
              size: Size.infinite,
              painter: _BarsPainter(
                first,
                second,
                firstColor,
                secondColor,
                theme.colorScheme.outlineVariant,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final l in labels)
                Expanded(
                  child: Text(
                    l,
                    textAlign: TextAlign.center,
                    style: labelStyle,
                    maxLines: 1,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.a, this.b, this.ca, this.cb, this.axis);

  final List<int> a, b;
  final Color ca, cb, axis;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()
        ..color = axis
        ..strokeWidth = 1,
    );
    final maxV = [...a, ...b].fold<int>(0, math.max);
    if (maxV <= 0 || a.isEmpty) return;
    final slot = size.width / a.length;
    final barW = math.min(14.0, slot * 0.3);
    void bar(double x, int v, Color c) {
      final h = (size.height - 1) * v / maxV;
      if (h <= 0) return;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x, size.height - 1 - h, barW, h),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        ),
        Paint()..color = c,
      );
    }

    for (var i = 0; i < a.length; i++) {
      final mid = slot * i + slot / 2;
      bar(mid - barW - 1.5, a[i], ca);
      bar(mid + 1.5, b[i], cb);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.a != a || old.b != b || old.ca != ca || old.cb != cb;
}
