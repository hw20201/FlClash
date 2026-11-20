import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fl_clash/common/exit_map_geo.dart';
import 'package:flutter/widgets.dart';

import 'data.dart';
import 'land.dart';

const exitMapFlowPeriod = Duration(milliseconds: 3400);

typedef _Location = (double, double);

class ExitMapCanvas extends StatefulWidget {
  const ExitMapCanvas({
    super.key,
    required this.origin,
    required this.routes,
    required this.landColor,
    required this.routeColor,
    required this.originColor,
    required this.animate,
    this.sceneSize,
    this.visibleRect,
    this.viewport,
  });

  final ExitMapPlace? origin;
  final List<ExitMapRoute> routes;
  final Color landColor;
  final Color routeColor;
  final Color originColor;
  final bool animate;
  final Size? sceneSize;
  final Rect? visibleRect;
  final ExitMapViewport? viewport;

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
    duration: const Duration(milliseconds: 650),
    value: 1,
  );
  late final _particleRepaint = Listenable.merge([_flow, _motion]);
  Size? _size;
  ExitMapViewport? _viewport;
  _Scene? _scene;
  Float32List _land = Float32List(0);
  ui.Picture? _landPicture;
  (Float32List, Color, double)? _landPictureKey;
  List<ExitMapRoute> _previousRoutes = const [];
  var _dirty = true;

  bool get _canAnimate =>
      widget.animate &&
      TickerMode.valuesOf(context).enabled &&
      !MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant ExitMapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.routes != oldWidget.routes ||
        widget.origin != oldWidget.origin ||
        widget.viewport != oldWidget.viewport) {
      _dirty = true;
    }
    _syncAnimation();
  }

  void _syncAnimation() {
    if (_canAnimate &&
        widget.origin != null &&
        widget.routes.any((route) => route.share > 0)) {
      if (!_flow.isAnimating) _flow.repeat();
    } else {
      _flow.stop();
    }
    if (!_canAnimate && _motion.isAnimating) _motion.value = 1;
  }

  void _layout(Size size) {
    if (!_dirty && size == _size) return;
    _dirty = false;
    final origin = widget.origin;
    final corridors = <_Location, _Corridor>{};
    if (origin != null) {
      for (final route in widget.routes) {
        final place = route.place;
        corridors.putIfAbsent(_location(place), () => _Corridor(place)).share +=
            route.share;
      }
    }
    final viewport =
        widget.viewport ??
        ExitMapViewport.fit(
          size,
          origin,
          corridors.values.map((corridor) => corridor.place),
        );
    if (_viewport != viewport || _size != size) {
      _land = exitMapLandPoints(viewport, size);
    }
    final old = _scene?.frame(_motion.value);
    final from = _canAnimate && _size == size && origin != null ? old : null;
    _size = size;
    _viewport = viewport;
    final start = origin == null ? null : viewport.project(origin, size);
    final previous = <_Location, _Arc>{...?from?.arcs};
    final moves = from == null
        ? const <_Location, _Location>{}
        : _moves(corridors.keys);
    final tweens = <_Location, _ArcTween>{};
    if (start != null) {
      for (final MapEntry(key: key, value: corridor) in corridors.entries) {
        final share = corridor.share.clamp(0.0, 1.0);
        final target = _Arc(
          start,
          viewport.project(corridor.place, size),
          1.1 + 5 * share,
          0.32 + 0.54 * share,
          share > 0,
        );
        final before = previous.remove(key) ?? previous.remove(moves[key]);
        tweens[key] = _ArcTween(before ?? target.hidden, target);
      }
      for (final MapEntry(key: key, value: arc) in previous.entries) {
        tweens[key] = _ArcTween(arc, arc.hidden);
      }
    }
    _previousRoutes = widget.routes;
    _scene = _Scene(tweens, from?.origin ?? start, start);
    if (from != null && (tweens.isNotEmpty || start != from.origin)) {
      _motion.forward(from: 0);
    } else {
      _motion.value = 1;
    }
  }

  Map<_Location, _Location> _moves(Iterable<_Location> next) {
    final oldPlaces = {
      for (final route in _previousRoutes) route.node: _location(route.place),
    };
    final current = next.toSet();
    final replacements = exitMapReplacements(_previousRoutes, widget.routes);
    final moves = <_Location, _Location>{};
    final claimed = <_Location>{};
    for (final route in widget.routes) {
      final before = oldPlaces[replacements[route.node]];
      final after = _location(route.place);
      if (before != null &&
          !current.contains(before) &&
          !moves.containsKey(after) &&
          claimed.add(before)) {
        moves[after] = before;
      }
    }
    return moves;
  }

  static _Location _location(ExitMapPlace place) =>
      (place.latitude, place.longitude);

  ui.Picture _landPictureFor(double dotSize) {
    final key = (_land, widget.landColor, dotSize);
    if (_landPictureKey != key) {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRawPoints(
        ui.PointMode.points,
        _land,
        Paint()
          ..color = widget.landColor
          ..strokeWidth = dotSize
          ..strokeCap = StrokeCap.round,
      );
      final previous = _landPicture;
      _landPicture = recorder.endRecording();
      _landPictureKey = key;
      previous?.dispose();
    }
    return _landPicture!;
  }

  @override
  void dispose() {
    _landPicture?.dispose();
    _flow.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showParticles = _canAnimate;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = widget.sceneSize ?? constraints.biggest;
        if (size.isEmpty || !size.isFinite) return const SizedBox.shrink();
        _layout(size);
        final offset = widget.visibleRect?.topLeft ?? Offset.zero;
        final scene = _scene!;
        final dotSize = (size.width / (_viewport!.bounds.width * 360) * 0.8)
            .clamp(0.6, 1.8);
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(
                key: const ValueKey('exit-map-land'),
                child: CustomPaint(
                  painter: _LandPainter(_landPictureFor(dotSize), offset),
                ),
              ),
              RepaintBoundary(
                key: const ValueKey('exit-map-routes'),
                child: CustomPaint(
                  painter: _RoutePainter(
                    scene,
                    _motion,
                    widget.routeColor,
                    widget.originColor,
                    offset,
                  ),
                ),
              ),
              if (showParticles &&
                  widget.origin != null &&
                  widget.routes.isNotEmpty)
                RepaintBoundary(
                  key: const ValueKey('exit-map-flow'),
                  child: CustomPaint(
                    painter: _ParticlePainter(
                      scene,
                      _motion,
                      _flow,
                      widget.routeColor,
                      offset,
                      repaint: _particleRepaint,
                    ),
                    willChange: true,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

final _landBits = base64Decode(exitMapLandBase64);

Float32List exitMapLandPoints(ExitMapViewport viewport, Size size) {
  final firstColumn = (viewport.centerLongitude - 0.5).ceil();
  final points = <double>[];
  for (var row = 0; row < 180; row++) {
    for (var column = firstColumn; column < firstColumn + 360; column++) {
      final cell = row * 360 + column % 360;
      if (_landBits[cell >> 3] & (1 << (cell & 7)) == 0) continue;
      final point = viewport.projectCoordinates(
        89.5 - row,
        column - 179.5,
        size,
      );
      points
        ..add(point.dx)
        ..add(point.dy);
    }
  }
  return Float32List.fromList(points);
}

class _LandPainter extends CustomPainter {
  const _LandPainter(this.picture, this.offset);
  final ui.Picture picture;
  final Offset offset;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    canvas.translate(-offset.dx, -offset.dy);
    canvas.drawPicture(picture);
  }

  @override
  bool shouldRepaint(covariant _LandPainter oldDelegate) =>
      oldDelegate.picture != picture || oldDelegate.offset != offset;
}

class _Corridor {
  _Corridor(this.place);
  final ExitMapPlace place;
  var share = 0.0;
}

class _Arc {
  _Arc(this.start, this.end, this.width, this.opacity, this.hasTraffic);
  final Offset start;
  final Offset end;
  final double width;
  final double opacity;
  final bool hasTraffic;
  late final Offset control = exitMapControl(start, end);
  late final Path path = Path()
    ..moveTo(start.dx, start.dy)
    ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
  _Arc get hidden => _Arc(start, end, width, 0, hasTraffic);
}

class _ArcTween {
  const _ArcTween(this.begin, this.end);
  final _Arc begin;
  final _Arc end;

  _Arc at(double t) => t == 1
      ? end
      : _Arc(
          Offset.lerp(begin.start, end.start, t)!,
          Offset.lerp(begin.end, end.end, t)!,
          ui.lerpDouble(begin.width, end.width, t)!,
          ui.lerpDouble(begin.opacity, end.opacity, t)!,
          begin.hasTraffic || end.hasTraffic,
        );
}

class _Scene {
  _Scene(this.tweens, this.originBefore, this.originAfter);
  final Map<_Location, _ArcTween> tweens;
  final Offset? originBefore;
  final Offset? originAfter;
  double? _progress;
  late ({Map<_Location, _Arc> arcs, Offset? origin}) _frame;

  ({Map<_Location, _Arc> arcs, Offset? origin}) frame(double progress) {
    if (_progress != progress) {
      _progress = progress;
      final t = Curves.easeInOutCubic.transform(progress);
      _frame = (
        arcs: {
          for (final entry in tweens.entries)
            if (entry.value.at(t) case final arc when arc.opacity > 0)
              entry.key: arc,
        },
        origin: Offset.lerp(originBefore, originAfter, t),
      );
    }
    return _frame;
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter(
    this.scene,
    this.motion,
    this.color,
    this.originColor,
    this.offset,
  ) : super(repaint: motion);

  final _Scene scene;
  final Animation<double> motion;
  final Color color;
  final Color originColor;
  final Offset offset;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    canvas.translate(-offset.dx, -offset.dy);
    final frame = scene.frame(motion.value);
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (final arc in frame.arcs.values) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = arc.width
        ..color = color.withValues(alpha: arc.opacity);
      canvas.drawPath(arc.path, paint);
      paint.style = PaintingStyle.fill;
      canvas.drawCircle(arc.end, 3, paint);
    }
    if (frame.origin case final origin?) {
      paint
        ..style = PaintingStyle.fill
        ..color = originColor.withValues(alpha: 0.24);
      canvas.drawCircle(origin, 8, paint);
      paint.color = originColor;
      canvas.drawCircle(origin, 4, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) =>
      oldDelegate.scene != scene ||
      oldDelegate.color != color ||
      oldDelegate.originColor != originColor ||
      oldDelegate.offset != offset;
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter(
    this.scene,
    this.motion,
    this.flow,
    this.color,
    this.offset, {
    required super.repaint,
  });

  final _Scene scene;
  final Animation<double> motion;
  final Animation<double> flow;
  final Color color;
  final Offset offset;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    canvas.translate(-offset.dx, -offset.dy);
    final paint = Paint();
    final frame = scene.frame(motion.value);
    final progress = flow.value;
    for (final MapEntry(key: key, value: arc) in frame.arcs.entries) {
      if (!arc.hasTraffic || arc.start == arc.end) continue;
      final phase = key.hashCode % 101 / 101;
      for (var index = 0; index < 2; index++) {
        final t = (progress + phase + index / 2) % 1;
        final alpha = (t * 12).clamp(0.0, 1.0) * ((1 - t) * 12).clamp(0.0, 1.0);
        paint.color = color.withValues(alpha: arc.opacity * alpha);
        canvas.drawCircle(
          exitMapAlong(arc.start, arc.control, arc.end, t),
          2.4,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) =>
      oldDelegate.scene != scene ||
      oldDelegate.color != color ||
      oldDelegate.offset != offset;
}
