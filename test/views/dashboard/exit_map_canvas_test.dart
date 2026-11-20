import 'dart:ui' as ui;

import 'package:fl_clash/common/exit_map_geo.dart';
import 'package:fl_clash/views/dashboard/exit_map/canvas.dart';
import 'package:fl_clash/views/dashboard/exit_map/data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _wrapViewport = ExitMapViewport(
  Rect.fromLTWH(0.125, 0.25, 0.5, 0.5),
  180,
);
const _sceneSize = Size(180, 90);
const _origin = ExitMapPlace(
  country: 'GH',
  city: 'Origin',
  latitude: 0,
  longitude: 1,
);
const _exit = ExitMapPlace(
  country: 'SD',
  city: 'Exit',
  latitude: 15,
  longitude: 39,
);
const _seamExit = ExitMapPlace(
  country: 'GH',
  city: 'Seam exit',
  latitude: -15,
  longitude: 0,
);
const _layers = ['exit-map-land', 'exit-map-routes', 'exit-map-flow'];

Widget _wrappedCanvas(
  Rect visible, {
  List<ExitMapRoute> routes = const [
    ExitMapRoute(node: 'Exit', groups: {}, place: _exit, share: 1),
  ],
}) => MediaQuery(
  data: const MediaQueryData(),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: SizedBox.fromSize(
        size: visible.size,
        child: ExitMapCanvas(
          origin: _origin,
          routes: routes,
          landColor: const Color(0xff808080),
          routeColor: const Color(0xff3366ff),
          originColor: const Color(0xffff6600),
          animate: true,
          sceneSize: _sceneSize,
          visibleRect: visible,
          viewport: _wrapViewport,
        ),
      ),
    ),
  ),
);

Finder _layer(String name) => find.byKey(ValueKey(name));

CustomPainter _landPainter(WidgetTester tester) => tester
    .widget<CustomPaint>(
      find.descendant(
        of: _layer('exit-map-land'),
        matching: find.byType(CustomPaint),
      ),
    )
    .painter!;

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

int _pixelIndex(Rect visible, Offset point) =>
    (point.dy.floor() * visible.width.toInt() + point.dx.floor()) * 4;

Widget _canvas({
  bool animate = true,
  bool reducedMotion = false,
  String exit = 'Tokyo',
}) => MediaQuery(
  data: MediaQueryData(disableAnimations: reducedMotion),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: SizedBox(
        width: 400,
        height: 200,
        child: ExitMapCanvas(
          origin: locateExit('香港'),
          routes: [
            ExitMapRoute(
              node: exit,
              groups: const {'Proxy'},
              place: locateExit(exit)!,
              share: 1,
            ),
          ],
          landColor: const Color(0xff808080),
          routeColor: const Color(0xff3366ff),
          originColor: const Color(0xffff6600),
          animate: animate,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('all layers repeat across positive and negative world turns', (
    tester,
  ) async {
    final world = _wrapViewport.worldRect(_sceneSize);
    final visible = Rect.fromLTWH(world.right - 8, 4, 80, 70);
    await tester.pumpWidget(_wrappedCanvas(visible));
    await tester.pump(const Duration(milliseconds: 700));
    final baseline = await _layerPixels(tester, _layers);
    final landPainter = _landPainter(tester);
    final land = baseline['exit-map-land']!;
    final routes = baseline['exit-map-routes']!;
    final flow = baseline['exit-map-flow']!;
    var landBeforeSeam = false;
    var landAfterSeam = false;
    var particlePixels = 0;
    for (var alpha = 3; alpha < land.length; alpha += 4) {
      if (land[alpha] != 0) {
        if (alpha ~/ 4 % visible.width.toInt() < 8) {
          landBeforeSeam = true;
        } else {
          landAfterSeam = true;
        }
      }
      if (flow[alpha] > 64) {
        particlePixels++;
        expect(routes[alpha], isPositive);
      }
    }
    expect(landBeforeSeam, isTrue);
    expect(landAfterSeam, isTrue);
    expect(particlePixels, isPositive);

    Offset pointInView(ExitMapPlace place) =>
        _wrapViewport.project(place, _sceneSize) +
        Offset(world.width, 0) -
        visible.topLeft;
    final origin = _pixelIndex(visible, pointInView(_origin));
    final exit = _pixelIndex(visible, pointInView(_exit));
    expect(routes[origin], 255);
    expect(routes[origin + 2], 0);
    expect(routes[exit + 2], greaterThan(routes[exit]));

    for (final turns in [-3, -1, 1, 4]) {
      await tester.pumpWidget(_wrappedCanvas(visible.translate(11, 0)));
      expect(_landPainter(tester).shouldRepaint(landPainter), isTrue);
      await tester.pumpWidget(
        _wrappedCanvas(visible.translate(turns * world.width, 0)),
      );
      expect(_landPainter(tester).shouldRepaint(landPainter), isFalse);
      final actual = await _layerPixels(tester, _layers);
      for (final name in _layers) {
        expect(
          listEquals(actual[name], baseline[name]),
          isTrue,
          reason: '$name at $turns turns',
        );
      }
    }

    await tester.pumpWidget(_wrappedCanvas(visible.translate(0, world.height)));
    final offWorld = await _layerPixels(tester, _layers);
    for (final pixels in offWorld.values) {
      expect(pixels.every((value) => value == 0), isTrue);
    }
  });

  testWidgets('offscreen route and origin paint through the world seam', (
    tester,
  ) async {
    final seam = _wrapViewport.worldRect(_sceneSize).right;
    final visible = Rect.fromLTWH(seam - 8, 4, 7, 70);
    await tester.pumpWidget(
      _wrappedCanvas(
        visible,
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
    const layer = 'exit-map-routes';
    final pixels = (await _layerPixels(tester, [layer]))[layer]!;
    final originY = _wrapViewport.project(_origin, _sceneSize).dy - visible.top;
    final exitY = _wrapViewport.project(_seamExit, _sceneSize).dy - visible.top;
    final halo = _pixelIndex(visible, Offset(2, originY));
    final arc = _pixelIndex(visible, Offset(6, exitY));
    expect(pixels[halo], greaterThan(pixels[halo + 2]));
    expect(pixels[arc + 2], greaterThan(pixels[arc]));
  });

  testWidgets('flow repaints without rebuilding land or route geometry', (
    tester,
  ) async {
    await tester.pumpWidget(_canvas());
    await tester.pump(const Duration(seconds: 1));
    RenderRepaintBoundary layer(String name) =>
        tester.renderObject<RenderRepaintBoundary>(find.byKey(ValueKey(name)));
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
    'node changes animate and stop after disposal or reduced motion',
    (tester) async {
      await tester.pumpWidget(_canvas());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(_canvas(exit: 'London'));
      await tester.pump(const Duration(milliseconds: 325));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(_canvas(exit: 'London', reducedMotion: true));
      await tester.pump();
      expect(find.byKey(const ValueKey('exit-map-flow')), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(_canvas(exit: 'London', animate: false));
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
