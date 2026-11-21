import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

Matrix4 exitMapCameraMatrix(double scale, Offset offset) => Matrix4.identity()
  ..translateByDouble(offset.dx, offset.dy, 0, 1)
  ..scaleByDouble(scale, scale, scale, 1);

class ExitMapCameraBounds {
  const ExitMapCameraBounds({
    required this.size,
    required this.world,
    required this.maxScale,
    this.verticalPadding = 0,
  });

  final Size size;
  final Rect world;
  final double maxScale;
  final double verticalPadding;

  double get minScale =>
      math.min(size.width / world.width, size.height / world.height) * 0.88;

  double clampScale(double scale) => scale.clamp(minScale, maxScale);

  Matrix4 constrain(Matrix4 camera, {bool clampZoom = true}) {
    final requested = camera.getMaxScaleOnAxis();
    final scale = clampZoom ? clampScale(requested) : requested;
    final translation = camera.getTranslation();
    final period = world.width * scale;
    final x = (translation.x + period / 2) % period - period / 2;
    final top = verticalPadding - world.top * scale;
    final bottom = size.height - verticalPadding - world.bottom * scale;
    final y = bottom > top
        ? (top + bottom) / 2
        : translation.y.clamp(bottom, top);
    return exitMapCameraMatrix(scale, Offset(x, y));
  }
}

class ExitMapGestureRegion extends StatefulWidget {
  const ExitMapGestureRegion({
    super.key,
    required this.controller,
    required this.mapKey,
    required this.bounds,
    required this.enabled,
    this.onInteractionStart,
    required this.child,
  });

  final TransformationController controller;
  final GlobalKey mapKey;
  final ExitMapCameraBounds? Function() bounds;
  final bool enabled;
  final VoidCallback? onInteractionStart;
  final Widget child;

  @override
  State<ExitMapGestureRegion> createState() => _ExitMapGestureRegionState();
}

class _ExitMapGestureRegionState extends State<ExitMapGestureRegion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _inertia;
  late _ExitMapScaleGestureRecognizer _recognizer;
  var _anchor = Offset.zero;
  var _startScale = 1.0;
  var _active = false;
  var _applying = false;
  var _flingStart = Offset.zero;
  var _flingDirection = Offset.zero;

  RenderBox? get _mapBox =>
      widget.mapKey.currentContext?.findRenderObject() as RenderBox?;

  @override
  void initState() {
    super.initState();
    _inertia = AnimationController.unbounded(vsync: this)
      ..addListener(_flingTick);
    widget.controller.addListener(_cameraChanged);
  }

  @override
  void didUpdateWidget(covariant ExitMapGestureRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_cameraChanged);
      widget.controller.addListener(_cameraChanged);
    }
    if (!widget.enabled || oldWidget.controller != widget.controller) {
      _inertia.stop();
      _active = false;
    }
  }

  void _cameraChanged() {
    if (!_applying) _inertia.stop();
  }

  bool _inMap(Offset point) {
    final box = _mapBox;
    return box != null &&
        box.hasSize &&
        (Offset.zero & box.size).contains(box.globalToLocal(point));
  }

  void _setCamera(double scale, Offset translation) {
    final bounds = widget.bounds();
    if (bounds == null) return;
    final camera = bounds.constrain(exitMapCameraMatrix(scale, translation));
    _applying = true;
    try {
      if (camera != widget.controller.value) widget.controller.value = camera;
    } finally {
      _applying = false;
    }
  }

  void _start(ScaleStartDetails details) {
    _inertia.stop();
    _active = widget.enabled && _recognizer.canUpdate;
    final box = _mapBox;
    if (!_active || box == null) return;
    widget.onInteractionStart?.call();
    _startScale = widget.controller.value.getMaxScaleOnAxis();
    _anchor = widget.controller.toScene(box.globalToLocal(details.focalPoint));
  }

  void _update(ScaleUpdateDetails details) {
    final box = _mapBox;
    final bounds = widget.bounds();
    if (!_active ||
        !_recognizer.canUpdate ||
        box == null ||
        bounds == null ||
        !details.scale.isFinite ||
        details.scale <= 0) {
      return;
    }
    final requestedScale = _startScale * details.scale;
    final scale = bounds.clampScale(requestedScale);
    final point = box.globalToLocal(details.focalPoint);
    _setCamera(scale, point - _anchor * scale);
    _anchor = widget.controller.toScene(point);
    if (scale != requestedScale) _startScale = scale / details.scale;
  }

  void _end(ScaleEndDetails details) {
    final active = _active;
    _active = false;
    if (!active ||
        details.pointerCount != 0 ||
        _recognizer.wasCanceled ||
        !widget.enabled ||
        MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    final velocity = details.velocity.pixelsPerSecond;
    final speed = velocity.distance;
    if (speed < kMinFlingVelocity) return;
    final translation = widget.controller.value.getTranslation();
    _flingStart = Offset(translation.x, translation.y);
    _flingDirection = velocity / speed;
    _inertia.animateWith(
      FrictionSimulation(
        0.0000135,
        0,
        speed,
        tolerance: const Tolerance(distance: 1, velocity: 10),
      ),
    );
  }

  void _flingTick() {
    if (_inertia.value == 0) return;
    final before = widget.controller.value;
    _setCamera(
      before.getMaxScaleOnAxis(),
      _flingStart + _flingDirection * _inertia.value,
    );
    if (before == widget.controller.value) _inertia.stop();
  }

  void _pointerSignal(PointerSignalEvent event) {
    if (!widget.enabled ||
        event is! PointerScrollEvent ||
        !_inMap(event.position)) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _inertia.stop();
      final box = _mapBox;
      final bounds = widget.bounds();
      if (box == null || bounds == null) return;
      widget.onInteractionStart?.call();
      final point = box.globalToLocal(event.position);
      final anchor = widget.controller.toScene(point);
      final scale = bounds.clampScale(
        widget.controller.value.getMaxScaleOnAxis() *
            math.exp(-event.scrollDelta.dy / kDefaultMouseScrollToScaleFactor),
      );
      _setCamera(scale, point - anchor * scale);
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_cameraChanged);
    _inertia.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      _inertia.stop();
      _recognizer.physicalDown(event);
    },
    onPointerUp: (event) => _recognizer.physicalUp(event),
    onPointerCancel: (event) => _recognizer.physicalUp(event),
    onPointerSignal: _pointerSignal,
    child: RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        _ExitMapScaleGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              _ExitMapScaleGestureRecognizer
            >(
              () => _recognizer = _ExitMapScaleGestureRecognizer(_inMap),
              (instance) => instance
                ..enabled = widget.enabled
                ..gestureSettings = DeviceGestureSettings(
                  touchSlop:
                      (MediaQuery.gestureSettingsOf(context).touchSlop ??
                          kTouchSlop) /
                      4,
                )
                ..trackpadScrollCausesScale = true
                ..onStart = _start
                ..onUpdate = _update
                ..onEnd = _end,
            ),
      },
      child: widget.child,
    ),
  );
}

class _ExitMapScaleGestureRecognizer extends ScaleGestureRecognizer {
  _ExitMapScaleGestureRecognizer(this.inMap);

  final bool Function(Offset) inMap;
  final _contacts = <int>{};
  final _mapContacts = <int>{};
  final _panZoomContacts = <int>{};
  var _blocked = false;
  var _accepted = false;
  var wasCanceled = false;
  var enabled = true;

  bool get canUpdate =>
      enabled &&
      !_blocked &&
      (_contacts.length >= 2 ||
          _mapContacts.isNotEmpty ||
          _panZoomContacts.isNotEmpty);

  void physicalDown(PointerDownEvent event) {
    if (_contacts.isEmpty) {
      _blocked = false;
      _accepted = false;
      wasCanceled = false;
    }
    _contacts.add(event.pointer);
    if (inMap(event.position)) _mapContacts.add(event.pointer);
  }

  void physicalUp(PointerEvent event) {
    _contacts.remove(event.pointer);
    _mapContacts.remove(event.pointer);
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    physicalDown(event);
    super.addAllowedPointer(event);
    if (_blocked) super.resolve(GestureDisposition.rejected);
  }

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    _panZoomContacts.add(event.pointer);
    _blocked = false;
    wasCanceled = false;
    super.addAllowedPointerPanZoom(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (event is PointerCancelEvent) wasCanceled = true;
      physicalUp(event);
    }
    super.handleEvent(event);
    if (event is PointerPanZoomEndEvent) _panZoomContacts.remove(event.pointer);
  }

  @override
  void resolve(GestureDisposition disposition) {
    if (disposition == GestureDisposition.accepted && !canUpdate) return;
    super.resolve(disposition);
  }

  @override
  void acceptGesture(int pointer) {
    if (!canUpdate) return;
    _accepted = true;
    super.acceptGesture(pointer);
  }

  @override
  void rejectGesture(int pointer) {
    _panZoomContacts.remove(pointer);
    if (!_accepted && _contacts.isNotEmpty) _blocked = true;
    super.rejectGesture(pointer);
  }
}
