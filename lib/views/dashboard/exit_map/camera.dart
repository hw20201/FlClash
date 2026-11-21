import 'dart:math' as math;

import 'package:fl_clash/common/exit_map_geo.dart';
import 'package:flutter/widgets.dart';

import 'data.dart';
import 'gestures.dart';

const exitMapTransitionDuration = Duration(milliseconds: 560);

class ExitMapCamera {
  ExitMapCamera(TickerProvider vsync)
    : _motion = AnimationController(
        vsync: vsync,
        duration: exitMapTransitionDuration,
      ) {
    _motion.addListener(_tick);
  }

  final view = TransformationController();
  final AnimationController _motion;
  ExitMapCameraBounds? bounds;
  _View? _home;
  _View? _from;
  _View? _to;
  var _manual = false;
  var _animate = false;
  var _zoomReference = 1.0;

  bool get canReset => _manual;

  void layout(
    Size size,
    ExitMapPlace? origin,
    List<ExitMapRoute> routes, {
    required bool animate,
  }) {
    final oldSize = bounds?.size;
    final resized = oldSize != size;
    final fit = exitMapFitBounds(
      size,
      origin,
      routes.map((route) => route.place),
    );
    final home = (center: fit.center, scale: size.width / fit.width);
    if (resized || !_manual) {
      if (!_manual || oldSize == null) _zoomReference = home.scale;
      bounds = ExitMapCameraBounds(
        size: size,
        world: exitMapWorld,
        maxScale: 4 * _zoomReference,
        verticalPadding: 14,
      );
    }
    _animate = animate;
    if (_manual) {
      if (resized) _show(_current(oldSize ?? size));
    } else if (resized || home != _home) {
      _moveTo(home, animate: animate && !resized);
    } else if (!animate && _motion.isAnimating) {
      _moveTo(home, animate: false);
    }
    _home = home;
  }

  bool takeControl() {
    if (_manual || bounds == null) return false;
    _motion.stop();
    _manual = true;
    return true;
  }

  void reset() {
    if (!_manual || _home == null) return;
    _manual = false;
    _zoomReference = _home!.scale;
    final previous = bounds!;
    bounds = ExitMapCameraBounds(
      size: previous.size,
      world: previous.world,
      maxScale: 4 * _zoomReference,
      verticalPadding: previous.verticalPadding,
    );
    _moveTo(_home!, animate: _animate);
  }

  _View _current(Size size) {
    final scale = view.value.getMaxScaleOnAxis();
    final offset = view.value.getTranslation();
    return (
      center: (size.center(Offset.zero) - Offset(offset.x, offset.y)) / scale,
      scale: scale,
    );
  }

  void _moveTo(_View target, {required bool animate}) {
    _motion.stop();
    if (!animate) {
      _show(target);
      return;
    }
    final from = _current(bounds!.size);
    _from = from;
    _to = (
      center: exitMapNearestCopy(target.center, from.center),
      scale: target.scale,
    );
    if (_from != _to) _motion.forward(from: 0);
  }

  void _tick() {
    final from = _from!;
    final to = _to!;
    final t = Curves.easeInOutCubic.transform(_motion.value);
    _show((
      center: Offset.lerp(from.center, to.center, t)!,
      scale: from.scale * math.pow(to.scale / from.scale, t),
    ));
  }

  void _show(_View target) {
    final limits = bounds!;
    // A manual zoom can be deeper than the new fit's limit while resetting.
    final scale = target.scale.clamp(limits.minScale, double.infinity);
    final camera = limits.constrain(
      exitMapCameraMatrix(
        scale,
        limits.size.center(Offset.zero) - target.center * scale,
      ),
      clampZoom: false,
    );
    if (view.value != camera) view.value = camera;
  }

  void dispose() {
    _motion.dispose();
    view.dispose();
  }
}

typedef _View = ({Offset center, double scale});
