import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/common.dart' show TrafficShowExt;
import 'package:fl_clash/models/traffic_history.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
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
    this.topClearance = 0,
    this.viewportChanges,
  });

  final TrafficHistorySnapshot snapshot;
  final TrafficHistoryPeriod period;
  final double topClearance;
  final Listenable? viewportChanges;

  @override
  State<TrafficHistoryChart> createState() => _TrafficHistoryChartState();
}

class _TrafficHistoryChartState extends State<TrafficHistoryChart>
    with SingleTickerProviderStateMixin {
  final _plotKey = GlobalKey();
  late final _motion = AnimationController(vsync: this);
  late List<TrafficPoint> _points;
  late List<double> _from;
  late List<double> _to;
  ScrollPosition? _position;
  ValueListenable<double>? _overhang;
  var _maxValue = 0;
  var _selected = 0;
  var _visible = false;
  var _checkScheduled = false;
  var _entering = true;
  var _animate = false;

  bool get _hourly => widget.period == TrafficHistoryPeriod.day;

  @override
  void initState() {
    super.initState();
    _readPoints();
    _from = List.filled(_to.length, 0);
    _selectPeak();
    widget.viewportChanges?.addListener(_scheduleVisibilityCheck);
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
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _position) {
      _position?.removeListener(_scheduleVisibilityCheck);
      _position = position;
      _position?.addListener(_scheduleVisibilityCheck);
    }
    final overhang = SheetOverhangScope.of(context);
    if (overhang != _overhang) {
      _overhang?.removeListener(_scheduleVisibilityCheck);
      _overhang = overhang;
      _overhang?.addListener(_scheduleVisibilityCheck);
    }
    final animate =
        !context.disableAnimations && TickerMode.valuesOf(context).enabled;
    if (_animate != animate) {
      _animate = animate;
      _visible = false;
    }
    if (!_animate) {
      _motion.stop();
      _motion.value = 1;
    }
    _scheduleVisibilityCheck();
  }

  @override
  void didUpdateWidget(TrafficHistoryChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewportChanges != widget.viewportChanges) {
      oldWidget.viewportChanges?.removeListener(_scheduleVisibilityCheck);
      widget.viewportChanges?.addListener(_scheduleVisibilityCheck);
    }
    final changedRange =
        oldWidget.period != widget.period ||
        oldWidget.snapshot.start != widget.snapshot.start ||
        oldWidget.snapshot.end != widget.snapshot.end;
    final current = [for (var i = 0; i < _to.length; i++) _valueAt(i)];
    final previous = _to;
    _readPoints();
    if (changedRange) {
      _selectPeak();
      _start(entering: true);
    } else if (!listEquals(previous, _to)) {
      _from = current;
      _start(entering: false);
    }
    _scheduleVisibilityCheck();
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
    } else if (_visible) {
      _motion.duration = Duration(milliseconds: entering ? 850 : 280);
      _motion.forward(from: 0);
    } else {
      _motion.value = 0;
    }
  }

  void _scheduleVisibilityCheck() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.ensureVisualUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (!mounted) return;
      final plot = _plotKey.currentContext?.findRenderObject();
      if (plot is! RenderBox || !plot.attached || !plot.hasSize) return;
      final viewport = RenderAbstractViewport.maybeOf(plot);
      final (bounds, viewportBounds) = switch (viewport) {
        final RenderBox box => (
          MatrixUtils.transformRect(
            plot.getTransformTo(box),
            Offset.zero & plot.size,
          ),
          (Offset.zero & box.size).intersect(
            MatrixUtils.transformRect(
              Matrix4.inverted(box.getTransformTo(null)),
              Offset.zero & MediaQuery.sizeOf(context),
            ),
          ),
        ),
        _ => (
          plot.localToGlobal(Offset.zero) & plot.size,
          Offset.zero & MediaQuery.sizeOf(context),
        ),
      };
      final visibleTop = math.max(viewportBounds.top, widget.topClearance);
      final visible =
          TickerMode.valuesOf(context).enabled &&
          viewportBounds.bottom > visibleTop &&
          bounds.bottom > visibleTop &&
          bounds.top < viewportBounds.bottom;
      if (visible == _visible) return;
      _visible = visible;
      if (visible) {
        _start(entering: true);
      } else {
        _motion.stop();
      }
    });
  }

  @override
  void dispose() {
    _position?.removeListener(_scheduleVisibilityCheck);
    _overhang?.removeListener(_scheduleVisibilityCheck);
    widget.viewportChanges?.removeListener(_scheduleVisibilityCheck);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleVisibilityCheck();
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
              key: _plotKey,
              height: 158,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final height = constraints.maxHeight - 16;
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
                              selected: index == _selected,
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
    required this.selected,
    required this.motion,
    required this.heightFactor,
    required this.onSelected,
  });

  final TrafficPoint point;
  final double height;
  final bool selected;
  final Animation<double> motion;
  final double Function() heightFactor;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final empty = point.upload + point.download == 0;
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
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: selected ? scheme.primary.withValues(alpha: .07) : null,
            shape: AppShape.md,
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 12,
              height: height,
              child: Tooltip(
                message:
                    '${point.label}: ${point.download.traffic.show} ↓ · ${point.upload.traffic.show} ↑',
                child: AnimatedBuilder(
                  animation: motion,
                  builder: (_, child) => Transform.scale(
                    alignment: Alignment.bottomCenter,
                    scaleY: empty ? 2 / height : heightFactor(),
                    child: child,
                  ),
                  child: Container(
                    decoration: ShapeDecoration(
                      color: empty
                          ? scheme.primary.withValues(alpha: .3)
                          : scheme.primary.withValues(
                              alpha: selected ? 1 : .65,
                            ),
                      shape: AppShape.full,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
