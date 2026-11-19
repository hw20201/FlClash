import 'dart:math' as math;

import 'package:fl_clash/ui/ui.dart';
import 'package:flutter/widgets.dart';

class TrafficShareGauge extends StatelessWidget {
  const TrafficShareGauge({
    super.key,
    required this.share,
    required this.size,
    required this.label,
    this.showLabel = false,
    this.remainderColor,
  });

  final double? share;
  final double size;
  final String label;
  final bool showLabel;
  final Color? remainderColor;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final ratio = share?.clamp(0.0, 1.0);
    final percentage = ratio == null ? '—' : '${(ratio * 100).round()}%';
    final numberStyle = switch (size) {
      <= 44 => AppTextStyle.caption2,
      <= 68 => AppTextStyle.subheadline,
      _ => AppTextStyle.title2,
    };
    return Semantics(
      label: label,
      value: percentage,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _GaugeTicks(
            ratio: ratio ?? 0,
            active: scheme.primary,
            inactive:
                remainderColor ??
                (ratio == null
                    ? scheme.onSurface.withValues(alpha: 0.12)
                    : scheme.primary.withValues(alpha: 0.45)),
          ),
          child: Center(
            child: FractionallySizedBox(
              widthFactor: 0.66,
              heightFactor: 0.63,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      percentage,
                      style: numberStyle
                          .of(context, emphasized: true)
                          .toTabular,
                    ),
                    if (showLabel)
                      Text(
                        label,
                        style: AppTextStyle.caption2
                            .of(context)
                            .copyWith(color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GaugeTicks extends CustomPainter {
  const _GaugeTicks({
    required this.ratio,
    required this.active,
    required this.inactive,
  });

  final double ratio;
  final Color active;
  final Color inactive;

  @override
  void paint(Canvas canvas, Size size) {
    final diameter = size.shortestSide;
    final segments = switch (diameter) {
      <= 44 => 16,
      <= 68 => 24,
      _ => 32,
    };
    final stroke = Paint()
      ..strokeWidth = diameter * 0.038
      ..strokeCap = StrokeCap.round;
    final radius = (diameter - stroke.strokeWidth) / 2 - 1;
    final center = size.center(Offset.zero);
    final filled = (ratio * segments).round();
    for (var index = 0; index < segments; index++) {
      final angle = index * 2 * math.pi / segments - math.pi / 2;
      final direction = Offset(math.cos(angle), math.sin(angle));
      final length = diameter * (index % 4 == 0 ? 0.108 : 0.085);
      canvas.drawLine(
        center + direction * (radius - length),
        center + direction * radius,
        stroke..color = index < filled ? active : inactive,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugeTicks oldDelegate) =>
      ratio != oldDelegate.ratio ||
      active != oldDelegate.active ||
      inactive != oldDelegate.inactive;
}
