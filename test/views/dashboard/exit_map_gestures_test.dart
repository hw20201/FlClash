import 'package:fl_clash/views/dashboard/exit_map/gestures.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _width = 300.0;
const _size = Size(_width, 160);
const _world = Rect.fromLTRB(30, -50, 270, 210);
const _limits = ExitMapCameraBounds(size: _size, world: _world, maxScale: 4);
const _header = ValueKey('test-header');

Future<GlobalKey> _pumpRegion(
  WidgetTester tester,
  TransformationController camera, {
  bool enabled = true,
  VoidCallback? onDashboardDrag,
}) async {
  final mapKey = GlobalKey();
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(
        disableAnimations: true,
        gestureSettings: DeviceGestureSettings(touchSlop: 6),
      ),
      child: Center(
        child: GestureDetector(
          onVerticalDragStart: onDashboardDrag == null
              ? null
              : (_) => onDashboardDrag(),
          child: ExitMapGestureRegion(
            controller: camera,
            mapKey: mapKey,
            bounds: () => _limits,
            enabled: enabled,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(key: _header, width: _width, height: 48),
                SizedBox.fromSize(key: mapKey, size: _size),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  return mapKey;
}

TransformationController _camera() {
  final camera = TransformationController();
  addTearDown(camera.dispose);
  return camera;
}

void main() {
  test('camera wraps by the clamped scale times the projected world width', () {
    for (final direction in [-1, 1]) {
      final camera = _limits.constrain(
        exitMapCameraMatrix(8, Offset(direction * 1033.0, direction * 1000.0)),
      );
      final translation = camera.getTranslation();
      expect(camera.getMaxScaleOnAxis(), 4);
      expect(translation.x, direction * 73);
      expect(translation.y, direction > 0 ? 200 : -680);
    }
  });

  test('world zoom fits both axes with room for the coastline', () {
    final camera = _limits.constrain(
      exitMapCameraMatrix(0.001, const Offset(0, 992)),
    );
    final scale = camera.getMaxScaleOnAxis();
    expect(scale * _world.height, closeTo(_size.height * 0.88, 1e-9));
    expect(scale * _world.width, lessThan(_size.width));
    expect(
      camera.getTranslation().y + _world.center.dy * scale,
      _size.height / 2,
    );
  });

  testWidgets('pan wraps at world width even in a wider map box', (
    tester,
  ) async {
    final camera = _camera();
    final map = find.byKey(await _pumpRegion(tester, camera));
    final pan = await tester.startGesture(tester.getCenter(map));
    await tester.pump();

    await pan.moveBy(Offset(_world.width + 12, 0));
    expect(camera.value.getTranslation().x, closeTo(12, 1e-9));
    await pan.moveBy(Offset(-2 * (_world.width + 12), 0));
    expect(camera.value.getTranslation().x, closeTo(-12, 1e-9));
    await pan.up();
  });

  testWidgets('pan reverses immediately at either vertical limit', (
    tester,
  ) async {
    final camera = _camera();
    final map = find.byKey(await _pumpRegion(tester, camera));
    final pan = await tester.startGesture(tester.getCenter(map));
    await tester.pump();

    await pan.moveBy(const Offset(0, 145));
    expect(camera.value.getTranslation().y, 50);
    await pan.moveBy(const Offset(0, -6));
    expect(camera.value.getTranslation().y, closeTo(44, 1e-9));
    await pan.moveBy(const Offset(0, -200));
    expect(camera.value.getTranslation().y, -50);
    await pan.moveBy(const Offset(0, 5));
    expect(camera.value.getTranslation().y, closeTo(-45, 1e-9));
    await pan.up();
  });

  testWidgets('trackpad pinch reverses immediately at both scale limits', (
    tester,
  ) async {
    final camera = _camera();
    await _pumpRegion(tester, camera);
    final point = tester.getCenter(find.byKey(_header));
    final pinch = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await pinch.panZoomStart(point);
    await tester.pump();

    await pinch.panZoomUpdate(point, scale: 6);
    expect(camera.value.getMaxScaleOnAxis(), 4);
    await pinch.panZoomUpdate(point, scale: 5.5);
    expect(camera.value.getMaxScaleOnAxis(), closeTo(11 / 3, 1e-9));
    await pinch.panZoomUpdate(point, scale: 0.25);
    expect(camera.value.getMaxScaleOnAxis(), _limits.minScale);
    await pinch.panZoomUpdate(point, scale: 0.30);
    expect(
      camera.value.getMaxScaleOnAxis(),
      closeTo(1.2 * _limits.minScale, 1e-9),
    );
    await pinch.panZoomEnd();
  });

  testWidgets('coincident touch points do not disrupt the pinch scale', (
    tester,
  ) async {
    final camera = _camera();
    final map = find.byKey(await _pumpRegion(tester, camera));
    final center = tester.getCenter(map);
    final leftPoint = center - const Offset(20, 0);
    final rightPoint = center + const Offset(20, 0);
    final left = await tester.startGesture(leftPoint);
    final right = await tester.startGesture(rightPoint);

    await right.moveTo(rightPoint + const Offset(40, 0));
    expect(camera.value.getMaxScaleOnAxis(), closeTo(2, 1e-9));
    await right.moveTo(leftPoint);
    expect(camera.value.getMaxScaleOnAxis(), closeTo(2, 1e-9));
    await right.moveTo(rightPoint + const Offset(36, 0));
    expect(camera.value.getMaxScaleOnAxis(), closeTo(1.9, 1e-9));
    await right.up();
    await left.up();
  });

  testWidgets('disabled map leaves a map-origin drag with the dashboard', (
    tester,
  ) async {
    final camera = _camera();
    var dashboardDrags = 0;
    final mapKey = await _pumpRegion(
      tester,
      camera,
      enabled: false,
      onDashboardDrag: () => dashboardDrags++,
    );
    final touch = await tester.startGesture(
      tester.getCenter(find.byKey(mapKey)),
    );
    await touch.moveBy(const Offset(0, -5));
    await touch.moveBy(const Offset(0, -35));
    expect(dashboardDrags, 1);
    expect(camera.value, Matrix4.identity());
    await touch.up();
  });

  testWidgets('rejected trackpad leaves a later single header drag alone', (
    tester,
  ) async {
    final camera = _camera();
    var dashboardDrags = 0;
    await _pumpRegion(tester, camera, onDashboardDrag: () => dashboardDrags++);
    final header = tester.getCenter(find.byKey(_header));
    final trackpad = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    await trackpad.panZoomStart(header);
    // Pass the dashboard's 6 dp slop without requesting a 5% map zoom.
    await trackpad.panZoomUpdate(header, pan: const Offset(0, -8));
    expect(dashboardDrags, 1);
    expect(camera.value, Matrix4.identity());
    await trackpad.panZoomEnd();

    final touch = await tester.startGesture(header);
    await touch.moveBy(const Offset(0, -5));
    await touch.moveBy(const Offset(0, -35));
    expect(dashboardDrags, 2);
    expect(camera.value, Matrix4.identity());
    await touch.up();
  });
}
