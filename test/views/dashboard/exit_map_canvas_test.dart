import 'package:fl_clash/common/exit_map_geo.dart';
import 'package:fl_clash/views/dashboard/exit_map/canvas.dart';
import 'package:fl_clash/views/dashboard/exit_map/data.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

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
