import 'dart:ui' as ui;

import 'package:fl_clash/common/exit_map_geo.dart';
import 'package:fl_clash/views/dashboard/exit_map/camera.dart';
import 'package:fl_clash/views/dashboard/exit_map/canvas.dart';
import 'package:fl_clash/views/dashboard/exit_map/data.dart';
import 'package:fl_clash/views/dashboard/exit_map/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = Size(96, 70);
const _origin = ExitMapPlace(
  country: 'RU',
  city: 'Origin',
  latitude: 45,
  longitude: 176,
);
const _exit = ExitMapPlace(
  country: 'US',
  city: 'Exit',
  latitude: 62,
  longitude: -150,
);
const _next = ExitMapPlace(
  country: 'US',
  city: 'New exit',
  latitude: 32,
  longitude: -150,
);
const _seamExit = ExitMapPlace(
  country: 'FJ',
  city: 'Seam exit',
  latitude: 25,
  longitude: -178,
);
const _route = ExitMapRoute(
  node: 'Exit',
  groups: {'Proxy'},
  place: _exit,
  share: 1,
);
const _replacement = ExitMapRoute(
  node: 'New exit',
  groups: {'Proxy'},
  place: _next,
  share: 1,
);
const _layers = ['exit-map-land', 'exit-map-routes', 'exit-map-flow'];
const _offset = Offset(-337, -18);

TransformationController _camera([Offset offset = _offset]) {
  final camera = TransformationController(exitMapCameraMatrix(1, offset));
  addTearDown(camera.dispose);
  return camera;
}

Widget _canvas(
  TransformationController camera, {
  ExitMapPlace? origin = _origin,
  List<ExitMapRoute> routes = const [_route],
  Size size = _size,
  bool animate = true,
  bool reducedMotion = false,
  bool tickerEnabled = true,
}) => TickerMode(
  enabled: tickerEnabled,
  child: MediaQuery(
    data: MediaQueryData(disableAnimations: reducedMotion),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox.fromSize(
          size: size,
          child: ExitMapCanvas(
            camera: camera,
            origin: origin,
            routes: routes,
            landColor: const Color(0xff808080),
            routeColor: const Color(0xff3366ff),
            originColor: const Color(0xffff6600),
            surfaceColor: const Color(0xff101014),
            animate: animate,
          ),
        ),
      ),
    ),
  ),
);

Finder _layer(String name) => find.byKey(ValueKey(name));

Future<Map<String, Uint8List>> _layerPixels(
  WidgetTester tester,
  Iterable<String> names,
) async => (await tester.runAsync(() async {
  final pixels = <String, Uint8List>{};
  for (final name in names) {
    final layer = tester.renderObject<RenderRepaintBoundary>(_layer(name));
    final image = await layer.toImage(pixelRatio: 1);
    try {
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      pixels[name] = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
    } finally {
      image.dispose();
    }
  }
  return pixels;
}))!;

Future<Uint8List> _routes(WidgetTester tester) async =>
    (await _layerPixels(tester, ['exit-map-routes']))['exit-map-routes']!;

Offset _point(ExitMapPlace place) =>
    exitMapNearestCopy(exitMapWorldPoint(place), exitMapWorldPoint(_origin)) +
    _offset;

int _pixelIndex(Size size, Offset point) =>
    (point.dy.floor() * size.width.toInt() + point.dx.floor()) * 4;

void main() {
  testWidgets('land, arcs and particles wrap on the same world period', (
    tester,
  ) async {
    final camera = _camera();
    await tester.pumpWidget(_canvas(camera));
    await tester.pump(const Duration(milliseconds: 1550));
    final baseline = await _layerPixels(tester, _layers);
    final land = baseline['exit-map-land']!;
    final routes = baseline['exit-map-routes']!;
    final flow = baseline['exit-map-flow']!;
    expect(land[_pixelIndex(_size, const Offset(3, 31)) + 3], 0);
    for (final landPoint in [const Offset(3, 6), const Offset(53, 10)]) {
      expect(land[_pixelIndex(_size, landPoint) + 3], greaterThan(200));
    }
    final origin = _pixelIndex(_size, _point(_origin));
    final exit = _pixelIndex(_size, _point(_exit) + const Offset(2.5, 0));
    expect(routes[origin], 255);
    expect(routes[origin + 2], 0);
    expect(routes[exit + 2], greaterThan(routes[exit]));
    expect([
      for (var i = 3; i < flow.length; i += 4) flow[i],
    ], contains(greaterThan(64)));

    for (final turns in [-3, -1, 1, 4]) {
      camera.value = exitMapCameraMatrix(1, _offset + const Offset(11, 0));
      await tester.pump();
      final shifted = (await _layerPixels(tester, [
        'exit-map-land',
      ]))['exit-map-land'];
      expect(listEquals(shifted, land), isFalse);
      camera.value = exitMapCameraMatrix(
        1,
        _offset + Offset(turns * exitMapWorld.width, 0),
      );
      await tester.pump();
      final actual = await _layerPixels(tester, _layers);
      for (final name in _layers) {
        expect(
          listEquals(actual[name], baseline[name]),
          isTrue,
          reason: '$name at $turns turns',
        );
      }
    }
    camera.value = exitMapCameraMatrix(
      1,
      _offset - Offset(0, exitMapWorld.height),
    );
    await tester.pump();
    final offWorld = await _layerPixels(tester, _layers);
    for (final pixels in offWorld.values) {
      expect(pixels.every((value) => value == 0), isTrue);
    }
  });

  testWidgets('markers and route paint across the seam from outside the clip', (
    tester,
  ) async {
    const size = Size(4, 70);
    final camera = _camera(const Offset(-357, -26));
    await tester.pumpWidget(
      _canvas(
        camera,
        size: size,
        routes: const [
          ExitMapRoute(
            node: 'Seam exit',
            groups: {},
            place: _seamExit,
            share: 1,
          ),
        ],
      ),
    );
    final pixels = await _routes(tester);
    final origin = _pixelIndex(size, const Offset(1, 19));
    final exit = _pixelIndex(size, const Offset(2, 39));
    expect(pixels[origin], greaterThan(pixels[origin + 2]));
    expect(pixels[exit + 2], greaterThan(pixels[exit]));
  });

  testWidgets('flow repaints without rebuilding land or route geometry', (
    tester,
  ) async {
    await tester.pumpWidget(_canvas(_camera()));
    await tester.pump(const Duration(seconds: 1));
    RenderRepaintBoundary layer(String name) =>
        tester.renderObject<RenderRepaintBoundary>(_layer(name));
    final land = layer('exit-map-land')..debugResetMetrics();
    final routes = layer('exit-map-routes')..debugResetMetrics();
    final flow = layer('exit-map-flow')..debugResetMetrics();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    int paints(RenderRepaintBoundary layer) =>
        layer.debugSymmetricPaintCount + layer.debugAsymmetricPaintCount;
    expect(paints(land), 0);
    expect(paints(routes), 0);
    expect(paints(flow), greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
    'origin and route appearance, replacement and loss have intermediate frames',
    (tester) async {
      final camera = _camera();
      await tester.pumpWidget(_canvas(camera, origin: null));
      final empty = await _routes(tester);
      int originAlpha(Uint8List bytes) =>
          bytes[_pixelIndex(_size, _point(_origin)) + 3];

      await tester.pumpWidget(_canvas(camera));
      expect(await _routes(tester), orderedEquals(empty));
      await tester.pump(exitMapTransitionDuration ~/ 2);
      expect(originAlpha(await _routes(tester)), inExclusiveRange(0, 255));
      await tester.pump(exitMapTransitionDuration);
      final original = await _routes(tester);
      expect(originAlpha(original), 255);

      await tester.pumpWidget(_canvas(camera, routes: const [_replacement]));
      expect(await _routes(tester), orderedEquals(original));
      await tester.pump(exitMapTransitionDuration ~/ 2);
      final mid = await _routes(tester);
      final endpoint = Offset.lerp(_point(_exit), _point(_next), 0.5)!;
      final ring = _pixelIndex(_size, endpoint + const Offset(2.5, 0));
      expect(mid[ring + 2], greaterThan(mid[ring]));
      await tester.pump(exitMapTransitionDuration);
      final replaced = await _routes(tester);
      expect(listEquals(mid, replaced), isFalse);

      await tester.pumpWidget(_canvas(camera, origin: null));
      expect(await _routes(tester), orderedEquals(replaced));
      await tester.pump(exitMapTransitionDuration ~/ 2);
      expect(originAlpha(await _routes(tester)), inExclusiveRange(0, 255));
      await tester.pump(exitMapTransitionDuration);
      expect(await _routes(tester), orderedEquals(empty));
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('reduced motion and inactive map stop scheduling frames', (
    tester,
  ) async {
    final camera = _camera();
    await tester.pumpWidget(_canvas(camera));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(_canvas(camera, routes: const [_replacement]));
    await tester.pump(exitMapTransitionDuration ~/ 2);
    await tester.pumpWidget(
      _canvas(camera, routes: const [_replacement], reducedMotion: true),
    );
    expect(_layer('exit-map-flow'), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    final settled = await _routes(tester);
    await tester.pumpWidget(
      _canvas(camera, routes: const [_replacement], tickerEnabled: false),
    );
    expect(_layer('exit-map-flow'), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    expect(await _routes(tester), orderedEquals(settled));
    await tester.pumpWidget(
      _canvas(camera, routes: const [_replacement], animate: false),
    );
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
