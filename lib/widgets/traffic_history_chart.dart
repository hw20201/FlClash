import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/common.dart' show TrafficShowExt;
import 'package:fl_clash/models/traffic_history.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

final _growthCurve = SpringCurve(
  const SpringDescription(mass: 1, stiffness: 190, damping: 18),
  seconds: .68,
);

class TrafficHistoryChart extends StatefulWidget {
  const TrafficHistoryChart({
    super.key,
    required this.snapshot,
    required this.period,
  });

  final TrafficHistorySnapshot snapshot;
  final TrafficHistoryPeriod period;

  @override
  State<TrafficHistoryChart> createState() => _TrafficHistoryChartState();
}

class _TrafficHistoryChartState extends State<TrafficHistoryChart>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(vsync: this, value: 1);
  late List<TrafficPoint> _points;
  late List<double> _from;
  late List<double> _to;
  var _maxValue = 0;
  var _selected = 0;
  var _entering = false;
  var _animate = false;

  bool get _hourly => widget.period == TrafficHistoryPeriod.day;

  @override
  void initState() {
    super.initState();
    _readPoints();
    _from = List.of(_to);
    _selectPeak();
  }

  void _readPoints() {
    _points = widget.snapshot.points(hourly: _hourly);
    _maxValue = _points.fold(
      0,
      (value, point) => math.max(value, point.upload + point.download),
    );
    _to = [
      for (final point in _points)
        if (_maxValue == 0 || point.upload + point.download == 0)
          0
        else
          math.max(.022, (point.upload + point.download) / _maxValue),
    ];
  }

  void _selectPeak() {
    _selected = _points.indexWhere(
      (point) => point.upload + point.download == _maxValue,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animate =
        !context.disableAnimations && TickerMode.valuesOf(context).enabled;
    if (!_animate) {
      _motion.stop();
      _motion.value = 1;
    }
  }

  @override
  void didUpdateWidget(TrafficHistoryChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedRange =
        oldWidget.period != widget.period ||
        oldWidget.snapshot.start != widget.snapshot.start ||
        oldWidget.snapshot.end != widget.snapshot.end;
    final current = [for (var i = 0; i < _to.length; i++) _valueAt(i)];
    final previous = _to;
    _readPoints();
    if (oldWidget.period != widget.period) {
      _selectPeak();
      _start(entering: true);
    } else if (changedRange || !listEquals(previous, _to)) {
      if (changedRange) _selectPeak();
      _from = List.generate(
        _to.length,
        (index) => index < current.length ? current[index] : 0,
      );
      _start(entering: false);
    }
  }

  double _valueAt(int index) {
    final time = _motion.value;
    final progress = _entering
        ? _growthCurve.transform(
            ((time - index / math.max(1, _to.length - 1) * .2) / .8).clamp(
              0.0,
              1.0,
            ),
          )
        : Curves.easeOutCubic.transform(time);
    return math.max(0, _from[index] + (_to[index] - _from[index]) * progress);
  }

  void _start({required bool entering}) {
    _entering = entering;
    if (entering) _from = List.filled(_to.length, 0);
    _motion.stop();
    if (!_animate) {
      _motion.value = 1;
    } else {
      _motion.duration = Duration(milliseconds: entering ? 850 : 280);
      _motion.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final point = _points[_selected];
    final label = _hourly
        ? '${point.label.padLeft(2, '0')}:00'
        : trafficDayKey(point.date);
    return Card(
      shape: AppShape.xl,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoHeader(
            info: Info(label: context.appLocalizations.trafficHistoryTrend),
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 12),
          Row(
            spacing: 12,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  (point.upload + point.download).traffic.show,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.title3.of(context, emphasized: true),
                ),
              ),
              Text(
                label,
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${point.download.traffic.show} ↓ · ${point.upload.traffic.show} ↑',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              _maxValue.traffic.show,
              style: AppTextStyle.caption2
                  .of(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 4),
          RepaintBoundary(
            child: SizedBox(
              height: 158,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final height = constraints.maxHeight - 16;
                  final barWidth = math.min(
                    12.0,
                    constraints.maxWidth / _points.length * .56,
                  );
                  return CustomPaint(
                    painter: _TrafficGridPainter(
                      color: scheme.onSurface.withValues(alpha: .08),
                      headroom: 16,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (index, point) in _points.indexed)
                          Expanded(
                            child: _TrafficBar(
                              point: point,
                              height: height,
                              width: barWidth,
                              selected: index == _selected,
                              growing: _entering,
                              motion: _motion,
                              heightFactor: () => _valueAt(index),
                              onSelected: () =>
                                  setState(() => _selected = index),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          SizedBox(
            height: 1,
            width: double.infinity,
            child: ColoredBox(color: scheme.onSurface.withValues(alpha: .18)),
          ),
          const SizedBox(height: 6),
          _buildLabels(context),
        ],
      ),
    );
  }

  Widget _buildLabels(BuildContext context) {
    final indexes = _hourly
        ? const {0, 6, 12, 18}
        : _points.length <= 7
        ? {for (var i = 0; i < _points.length; i++) i}
        : {
            0,
            _points.length ~/ 4,
            _points.length ~/ 2,
            _points.length * 3 ~/ 4,
            _points.length - 1,
          };
    return Row(
      children: [
        for (var index = 0; index < _points.length; index++)
          Expanded(
            child: indexes.contains(index)
                ? Text(
                    _points[index].label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: AppTextStyle.caption2
                        .of(context)
                        .copyWith(color: context.colorScheme.onSurfaceVariant),
                  )
                : const SizedBox.shrink(),
          ),
      ],
    );
  }
}

class _TrafficBar extends StatelessWidget {
  const _TrafficBar({
    required this.point,
    required this.height,
    required this.width,
    required this.selected,
    required this.growing,
    required this.motion,
    required this.heightFactor,
    required this.onSelected,
  });

  final TrafficPoint point;
  final double height;
  final double width;
  final bool selected;
  final bool growing;
  final Animation<double> motion;
  final double Function() heightFactor;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${point.label}, ${context.appLocalizations.download} ${point.download.traffic.show}, ${context.appLocalizations.upload} ${point.upload.traffic.show}',
      onTap: onSelected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onSelected,
        child: Tooltip(
          message:
              '${point.label}: ${point.download.traffic.show} ↓ · ${point.upload.traffic.show} ↑',
          child: CustomPaint(
            painter: _TrafficBarPainter(
              motion: motion,
              heightFactor: heightFactor,
              height: height,
              width: width,
              empty: point.upload + point.download == 0,
              selected: selected,
              growing: growing,
              color: context.colorScheme.primary,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _TrafficBarPainter extends CustomPainter {
  _TrafficBarPainter({
    required Animation<double> motion,
    required this.heightFactor,
    required this.height,
    required this.width,
    required this.empty,
    required this.selected,
    required this.growing,
    required this.color,
  }) : super(repaint: motion);

  final double Function() heightFactor;
  final double height;
  final double width;
  final bool empty;
  final bool selected;
  final bool growing;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final valueHeight = height * heightFactor();
    final dotSize = math.min(3.0, width);
    final fromZero = growing && !empty;
    final morph = fromZero ? 1.0 : (valueHeight / dotSize).clamp(0.0, 1.0);
    final barHeight = fromZero ? valueHeight : math.max(dotSize, valueHeight);
    if (barHeight <= 0) return;
    final barWidth = dotSize + (width - dotSize) * morph;
    final rect = Rect.fromLTWH(
      (size.width - barWidth) / 2,
      size.height - barHeight,
      barWidth,
      barHeight,
    );
    final paint = Paint();
    final dotAlpha = selected ? .85 : .22;
    if (morph == 0) {
      paint.color = color.withValues(alpha: dotAlpha);
    } else {
      paint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(
            alpha: dotAlpha + ((selected ? .78 : .42) - dotAlpha) * morph,
          ),
          color.withValues(
            alpha: dotAlpha + ((selected ? 1 : .65) - dotAlpha) * morph,
          ),
        ],
      ).createShader(rect);
    }
    canvas.drawPath(AppShape.full.getOuterPath(rect), paint);
  }

  @override
  bool shouldRepaint(_TrafficBarPainter oldDelegate) =>
      heightFactor != oldDelegate.heightFactor ||
      height != oldDelegate.height ||
      width != oldDelegate.width ||
      empty != oldDelegate.empty ||
      growing != oldDelegate.growing ||
      selected != oldDelegate.selected ||
      color != oldDelegate.color;
}

class _TrafficGridPainter extends CustomPainter {
  const _TrafficGridPainter({required this.color, required this.headroom});

  final Color color;
  final double headroom;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = .75;
    for (final fraction in [0.0, .5]) {
      final y = headroom + (size.height - headroom) * fraction;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_TrafficGridPainter oldDelegate) =>
      color != oldDelegate.color || headroom != oldDelegate.headroom;
}
