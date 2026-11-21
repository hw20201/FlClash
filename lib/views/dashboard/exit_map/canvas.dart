import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fl_clash/common/exit_map_geo.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'camera.dart';
import 'data.dart';
import 'land.dart';

const exitMapFlowPeriod = Duration(milliseconds: 3400);

class ExitMapCanvas extends StatefulWidget {
  const ExitMapCanvas({
    super.key,
    required this.camera,
    required this.origin,
    required this.routes,
    required this.landColor,
    required this.routeColor,
    required this.originColor,
    required this.surfaceColor,
    required this.animate,
  });

  final TransformationController camera;
  final ExitMapPlace? origin;
  final List<ExitMapRoute> routes;
  final Color landColor;
  final Color routeColor;
  final Color originColor;
  final Color surfaceColor;
  final bool animate;

  @override
  State<ExitMapCanvas> createState() => _ExitMapCanvasState();
}

class _ExitMapCanvasState extends State<ExitMapCanvas>
    with TickerProviderStateMixin {
  late final _flow = AnimationController(
    vsync: this,
    duration: exitMapFlowPeriod,
  );
  late final _motion = AnimationController(
    vsync: this,
    duration: exitMapTransitionDuration,
    value: 1,
  )..addStatusListener(_motionChanged);
  late _Scene _scene;
  var _canAnimate = false;

  bool get _hasFlow =>
      widget.origin != null &&
      widget.routes.any(
        (route) =>
            route.share > 0 &&
            exitMapWorldPoint(route.place) != exitMapWorldPoint(widget.origin!),
      );

  @override
  void initState() {
    super.initState();
    _setScene();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant ExitMapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
    if (widget.origin != oldWidget.origin ||
        !listEquals(widget.routes, oldWidget.routes)) {
      _setScene(oldWidget.routes);
    }
  }

  void _setScene([List<ExitMapRoute>? oldRoutes]) {
    final from = oldRoutes != null && _canAnimate
        ? _scene.frame(_motion.value)
        : null;
    final place = widget.origin;
    final point = place == null ? null : exitMapWorldPoint(place);
    final before = from?.origin;
    final origin = point == null
        ? null
        : _Marker(
            before == null ? point : exitMapNearestCopy(point, before.point),
            1,
            place!.approximate ? 1 : 0,
          );
    final targets = <Offset, double>{};
    if (origin != null) {
      for (final route in widget.routes) {
        final end = exitMapWorldPoint(route.place);
        targets.update(
          end,
          (share) => share + route.share,
          ifAbsent: () => route.share,
        );
      }
    }
    final previous = <Offset, _Arc>{...?from?.arcs};
    final moves = from == null
        ? const <Offset, Offset>{}
        : _moves(oldRoutes!, targets.keys);
    final tweens = <Offset, (_Arc, _Arc)>{};
    if (origin != null) {
      for (final MapEntry(key: key, value: share) in targets.entries) {
        final old = previous.remove(key) ?? previous.remove(moves[key]);
        final arc = _Arc(
          origin.point,
          exitMapNearestCopy(key, origin.point),
          share.clamp(0, 1),
          1,
          old?.phase ?? (key.dx * 0.21 + key.dy * 0.13) % 1,
        );
        tweens[key] = (old ?? (from == null ? arc : arc.hidden), arc);
      }
    }
    for (final MapEntry(key: key, value: arc) in previous.entries) {
      tweens[key] = (arc, arc.hidden);
    }
    _scene = _Scene(tweens, before, origin);
    if (from != null &&
        (before != origin ||
            tweens.values.any((pair) => !pair.$1.matches(pair.$2)))) {
      _motion.forward(from: 0);
    } else {
      _motion.value = 1;
    }
    _syncFlow();
  }

  Map<Offset, Offset> _moves(
    List<ExitMapRoute> previous,
    Iterable<Offset> targets,
  ) {
    final oldPlaces = {
      for (final route in previous) route.node: exitMapWorldPoint(route.place),
    };
    final current = targets.toSet();
    final replacements = exitMapReplacements(previous, widget.routes);
    final moves = <Offset, Offset>{};
    final claimed = <Offset>{};
    for (final route in widget.routes) {
      final before = oldPlaces[replacements[route.node]];
      final after = exitMapWorldPoint(route.place);
      if (before != null &&
          !current.contains(before) &&
          !moves.containsKey(after) &&
          claimed.add(before)) {
        moves[after] = before;
      }
    }
    return moves;
  }

  void _syncAnimation() {
    _canAnimate =
        widget.animate &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (!_canAnimate && _motion.isAnimating) _motion.value = 1;
    _syncFlow();
  }

  void _syncFlow() {
    if (_canAnimate && (_hasFlow || (_motion.isAnimating && _scene.hadFlow))) {
      if (!_flow.isAnimating) _flow.repeat();
    } else {
      _flow.stop();
    }
  }

  void _motionChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) _syncFlow();
  }

  @override
  void dispose() {
    _flow.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      RepaintBoundary(
        key: const ValueKey('exit-map-land'),
        child: CustomPaint(
          painter: _LandPainter(widget.camera, widget.landColor),
        ),
      ),
      RepaintBoundary(
        key: const ValueKey('exit-map-routes'),
        child: CustomPaint(
          painter: _RoutePainter(
            widget.camera,
            _scene,
            _motion,
            widget.routeColor,
            widget.originColor,
            widget.surfaceColor,
          ),
        ),
      ),
      if (_canAnimate && (_hasFlow || _scene.hadFlow))
        RepaintBoundary(
          key: const ValueKey('exit-map-flow'),
          child: CustomPaint(
            painter: _ParticlePainter(
              widget.camera,
              _scene,
              _motion,
              _flow,
              widget.routeColor,
            ),
            willChange: true,
          ),
        ),
    ],
  );
}

final _landPath = exitMapLandPath();

@visibleForTesting
Path exitMapLandPath() {
  final bytes = base64Decode(exitMapLandBase64);
  var offset = 0;
  int read() {
    var value = 0;
    var shift = 0;
    while (true) {
      final byte = bytes[offset++];
      value |= (byte & 127) << shift;
      if (byte < 128) return value;
      shift += 7;
    }
  }

  int delta() {
    final value = read();
    return value.isEven ? value >> 1 : -(value >> 1) - 1;
  }

  final path = Path()..fillType = PathFillType.evenOdd;
  while (offset < bytes.length) {
    final count = read();
    var x = delta();
    var y = delta();
    path.moveTo(x / 20, y / 20);
    for (var i = 1; i < count; i++) {
      x += delta();
      y += delta();
      path.lineTo(x / 20, y / 20);
    }
    path.close();
  }
  return path;
}

class _Projection {
  _Projection(Matrix4 matrix, this.size)
    : scale = matrix.getMaxScaleOnAxis(),
      offset = _translation(matrix);

  final Size size;
  final double scale;
  final Offset offset;

  static Offset _translation(Matrix4 matrix) {
    final translation = matrix.getTranslation();
    final period = exitMapWorld.width * matrix.getMaxScaleOnAxis();
    return Offset(translation.x % period, translation.y);
  }

  double get period => exitMapWorld.width * scale;

  (int, int) copies(double left, double right, double padding) => (
    ((-padding - offset.dx - right * scale) / period).ceil(),
    ((size.width + padding - offset.dx - left * scale) / period).floor(),
  );

  Offset point(Offset world, int copy) =>
      world * scale + offset + Offset(copy * period, 0);
}

class _LandPainter extends CustomPainter {
  _LandPainter(this.camera, this.color) : super(repaint: camera);

  final TransformationController camera;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final world = _Projection(camera.value, size);
    final top = math.max(0.0, world.offset.dy);
    final bottom = math.min(
      size.height,
      world.offset.dy + exitMapWorld.height * world.scale,
    );
    if (top >= bottom) return;
    canvas.clipRect(Offset.zero & size);
    final grid = Paint()
      ..color = color.withValues(alpha: color.a * 0.40)
      ..strokeWidth = 0.5;
    final step = 30 * world.scale;
    for (var x = world.offset.dx % step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, top), Offset(x, bottom), grid);
    }
    for (var y = world.offset.dy % step; y < bottom; y += step) {
      if (y >= top) canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final fill = Paint()..color = color;
    final coast = Paint()
      ..color = color.withValues(alpha: color.a * 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.65 / world.scale;
    final (first, last) = world.copies(0, exitMapWorld.width, 1);
    for (var copy = first; copy <= last; copy++) {
      final offset = world.point(Offset.zero, copy);
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      canvas.scale(world.scale, world.scale);
      canvas.drawPath(_landPath, fill);
      canvas.drawPath(_landPath, coast);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _LandPainter oldDelegate) =>
      oldDelegate.camera != camera || oldDelegate.color != color;
}

class _Marker {
  const _Marker(this.point, this.opacity, this.approximate);
  final Offset point;
  final double opacity;
  final double approximate;

  _Marker get hidden => _Marker(point, 0, approximate);

  @override
  bool operator ==(Object other) =>
      other is _Marker &&
      point == other.point &&
      opacity == other.opacity &&
      approximate == other.approximate;

  @override
  int get hashCode => Object.hash(point, opacity, approximate);

  static _Marker? lerp(_Marker? from, _Marker? to, double t) {
    if (from == null && to == null) return null;
    final a = from ?? to!.hidden;
    final b = to ?? a.hidden;
    return _Marker(
      Offset.lerp(a.point, b.point, t)!,
      ui.lerpDouble(a.opacity, b.opacity, t)!,
      ui.lerpDouble(a.approximate, b.approximate, t)!,
    );
  }
}

class _Arc {
  _Arc(this.start, this.end, this.share, this.opacity, this.phase);
  final Offset start;
  final Offset end;
  final double share;
  final double opacity;
  final double phase;
  late final Offset control = exitMapControl(start, end);
  bool get flows => share > 0 && start != end;
  double get width => 0.85 + 0.95 * share;
  double get alpha => (0.52 + 0.44 * share) * opacity;
  _Arc get hidden => _Arc(start, end, share, 0, phase);

  bool matches(_Arc other) =>
      start == other.start &&
      end == other.end &&
      share == other.share &&
      opacity == other.opacity;

  static _Arc lerp(_Arc from, _Arc to, double t) => t == 1
      ? to
      : _Arc(
          Offset.lerp(from.start, to.start, t)!,
          Offset.lerp(from.end, to.end, t)!,
          ui.lerpDouble(from.share, to.share, t)!,
          ui.lerpDouble(from.opacity, to.opacity, t)!,
          to.phase,
        );
}

class _Scene {
  _Scene(this.arcs, this.from, this.to);
  final Map<Offset, (_Arc, _Arc)> arcs;
  final _Marker? from;
  final _Marker? to;
  late final bool hadFlow = arcs.values.any(
    (pair) => pair.$1.opacity > 0 && pair.$1.flows,
  );
  double? _progress;
  late _Frame _frame;

  _Frame frame(double progress) {
    if (_progress != progress) {
      _progress = progress;
      final t = Curves.easeInOutCubic.transform(progress);
      _frame = (
        arcs: {
          for (final MapEntry(key: key, value: (begin, end)) in arcs.entries)
            if (_Arc.lerp(begin, end, t) case final arc when arc.opacity > 0)
              key: arc,
        },
        origin: t == 1 ? to : _Marker.lerp(from, to, t),
      );
    }
    return _frame;
  }
}

typedef _Frame = ({Map<Offset, _Arc> arcs, _Marker? origin});

class _RoutePainter extends CustomPainter {
  _RoutePainter(
    this.camera,
    this.scene,
    this.motion,
    this.color,
    this.origin,
    this.surface,
  ) : super(repaint: Listenable.merge([camera, motion]));

  final TransformationController camera;
  final _Scene scene;
  final Animation<double> motion;
  final Color color;
  final Color origin;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final frame = scene.frame(motion.value);
    final world = _Projection(camera.value, size);
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (final arc in frame.arcs.values) {
      final bend = arc.control;
      final (first, last) = world.copies(
        math.min(bend.dx, math.min(arc.start.dx, arc.end.dx)),
        math.max(bend.dx, math.max(arc.start.dx, arc.end.dx)),
        6,
      );
      for (var copy = first; copy <= last; copy++) {
        final start = world.point(arc.start, copy);
        final end = world.point(arc.end, copy);
        final control = world.point(bend, copy);
        final top = math.min(control.dy, math.min(start.dy, end.dy));
        final bottom = math.max(control.dy, math.max(start.dy, end.dy));
        if (bottom < -6 || top > size.height + 6) continue;
        if ((end - start).distanceSquared >= 1) {
          final path = Path()
            ..moveTo(start.dx, start.dy)
            ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = arc.width
            ..shader = ui.Gradient.linear(start, end, [
              origin.withValues(alpha: arc.alpha * 0.55),
              color.withValues(alpha: arc.alpha),
            ]);
          canvas.drawPath(path, paint);
          paint.shader = null;
        }
        if (arc.start != arc.end) {
          paint
            ..style = PaintingStyle.fill
            ..color = surface.withValues(alpha: arc.opacity);
          canvas.drawCircle(end, 3.6, paint);
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.25
            ..color = color.withValues(alpha: arc.alpha);
          canvas.drawCircle(end, 2.9, paint);
        }
      }
    }
    if (frame.origin case final marker? when marker.opacity > 0) {
      final (first, last) = world.copies(marker.point.dx, marker.point.dx, 14);
      for (var copy = first; copy <= last; copy++) {
        final center = world.point(marker.point, copy);
        paint
          ..style = PaintingStyle.fill
          ..color = origin.withValues(alpha: 0.15 * marker.opacity);
        canvas.drawCircle(center, 11, paint);
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = origin.withValues(
            alpha: 0.66 * marker.opacity * (1 - marker.approximate),
          );
        if (marker.approximate < 1) canvas.drawCircle(center, 10.5, paint);
        if (marker.approximate > 0) {
          paint.color = origin.withValues(
            alpha: 0.66 * marker.opacity * marker.approximate,
          );
          final ring = Rect.fromCircle(center: center, radius: 10.5);
          for (var i = 0; i < 6; i++) {
            canvas.drawArc(ring, i * math.pi / 3, math.pi / 6, false, paint);
          }
        }
        paint
          ..style = PaintingStyle.fill
          ..color = surface.withValues(alpha: marker.opacity);
        canvas.drawCircle(center, 6.1, paint);
        paint.color = origin.withValues(alpha: marker.opacity);
        canvas.drawCircle(center, 4.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) =>
      oldDelegate.camera != camera ||
      oldDelegate.scene != scene ||
      oldDelegate.color != color ||
      oldDelegate.origin != origin ||
      oldDelegate.surface != surface;
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter(this.camera, this.scene, this.motion, this.flow, this.color)
    : super(repaint: Listenable.merge([camera, motion, flow]));

  final TransformationController camera;
  final _Scene scene;
  final Animation<double> motion;
  final Animation<double> flow;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final world = _Projection(camera.value, size);
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.6;
    for (final arc in scene.frame(motion.value).arcs.values) {
      if (!arc.flows ||
          (arc.end - arc.start).distanceSquared * world.scale * world.scale <
              144) {
        continue;
      }
      final t = (flow.value + arc.phase) % 1;
      final point = exitMapAlong(arc.start, arc.control, arc.end, t);
      final tail = exitMapAlong(
        arc.start,
        arc.control,
        arc.end,
        math.max(0, t - 0.025),
      );
      final fade = math.min(1.0, math.min(t, 1 - t) * 10);
      final (first, last) = world.copies(
        math.min(point.dx, tail.dx),
        math.max(point.dx, tail.dx),
        3,
      );
      for (var copy = first; copy <= last; copy++) {
        final head = world.point(point, copy);
        final trail = world.point(tail, copy);
        paint.color = color.withValues(alpha: 0.45 * arc.alpha * fade);
        canvas.drawLine(head, trail, paint);
        paint.color = color.withValues(alpha: arc.alpha * fade);
        canvas.drawCircle(head, 1.35, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) =>
      oldDelegate.camera != camera ||
      oldDelegate.scene != scene ||
      oldDelegate.color != color;
}
