import 'package:fl_clash/models/traffic_history.dart';
import 'package:fl_clash/ui/ui.dart' show Tooltip;
import 'package:fl_clash/widgets/traffic_history_chart.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

TrafficHistorySnapshot _snapshot({
  int peak = 1000,
  int small = 10,
  int date = 19,
}) {
  final day = TrafficDay('2026-11-$date')
    ..addTotals(0, 0, peak)
    ..addTotals(6, 0, small);
  return TrafficHistorySnapshot(
    start: DateTime.utc(2026, 11, date),
    end: DateTime.utc(2026, 11, date),
    days: [day],
  );
}

Widget _host({
  required ScrollController controller,
  required TrafficHistorySnapshot snapshot,
  bool reducedMotion = false,
  TrafficHistoryPeriod period = TrafficHistoryPeriod.day,
  ValueNotifier<double>? viewportHeight,
  double before = 40,
}) => TestApp(
  locale: const Locale('en'),
  child: Builder(
    builder: (context) {
      final scroll = ListView(
        controller: controller,
        scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
        children: [
          SizedBox(height: before),
          TrafficHistoryChart(snapshot: snapshot, period: period),
          const SizedBox(height: 1400),
        ],
      );
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child: viewportHeight == null
            ? scroll
            : ValueListenableBuilder<double>(
                valueListenable: viewportHeight,
                child: scroll,
                builder: (context, height, child) => Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(height: height, child: child),
                ),
              ),
      );
    },
  ),
);

Finder _bar(int index) => find
    .descendant(
      of: find.byType(TrafficHistoryChart, skipOffstage: false),
      matching: find.byType(Tooltip, skipOffstage: false),
      skipOffstage: false,
    )
    .at(index);

List<(Path, Paint)> _paints(WidgetTester tester, int index) {
  final paths = <(Path, Paint)>[];
  final canvas = find.descendant(
    of: _bar(index),
    matching: find.byType(CustomPaint, skipOffstage: false),
    skipOffstage: false,
  );
  expect(
    tester.renderObject(canvas),
    paints..everything((method, arguments) {
      if (method == #drawPath) {
        paths.add((arguments[0] as Path, arguments[1] as Paint));
      }
      return true;
    }),
  );
  return paths;
}

double _height(WidgetTester tester, int index) {
  final paths = _paints(tester, index);
  return paths.isEmpty ? 0 : paths.single.$1.getBounds().height;
}

void main() {
  testWidgets('initial and remounted charts show final heights immediately', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    for (var mount = 0; mount < 2; mount++) {
      await tester.pumpWidget(
        _host(controller: controller, snapshot: _snapshot()),
      );
      final height = _height(tester, 0);
      expect(height, greaterThan(100));
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pump(const Duration(milliseconds: 350));
      expect(_height(tester, 0), height);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('genuine period switches grow, overshoot and settle in place', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(controller: controller, snapshot: _snapshot()),
    );
    final target = _height(tester, 0);
    for (final period in [
      TrafficHistoryPeriod.week,
      TrafficHistoryPeriod.month,
    ]) {
      await tester.pumpWidget(
        _host(controller: controller, snapshot: _snapshot(), period: period),
      );
      final size = tester.getSize(_bar(0));
      expect(_height(tester, 0), 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(_height(tester, 0), inExclusiveRange(target, target * 1.12));
      expect(tester.getSize(_bar(0)), size);
      await tester.pump(const Duration(milliseconds: 600));
      expect(_height(tester, 0), closeTo(target, .001));
      await tester.pumpWidget(
        _host(controller: controller, snapshot: _snapshot(), period: period),
      );
      expect(_height(tester, 0), closeTo(target, .001));
      expect(tester.hasRunningAnimations, isFalse);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('partial and full scroll exits never replay growth', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(controller: controller, snapshot: _snapshot()),
    );
    final target = _height(tester, 0);
    final state = tester.state(
      find.byType(TrafficHistoryChart, skipOffstage: false),
    );
    for (final offset in [20.0, 550.0, 0.0]) {
      controller.jumpTo(offset);
      await tester.pump();
      expect(_height(tester, 0), target);
      expect(
        tester.state(find.byType(TrafficHistoryChart, skipOffstage: false)),
        same(state),
      );
      expect(tester.hasRunningAnimations, isFalse);
    }
    await tester.pump(const Duration(milliseconds: 350));
    expect(_height(tester, 0), target);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('resizing a retained sheet never restarts growth', (
    tester,
  ) async {
    final controller = ScrollController();
    final height = ValueNotifier<double>(200);
    addTearDown(controller.dispose);
    addTearDown(height.dispose);
    await tester.pumpWidget(
      _host(
        controller: controller,
        snapshot: _snapshot(),
        viewportHeight: height,
        before: 220,
      ),
    );
    final target = _height(tester, 0);
    final state = tester.state(
      find.byType(TrafficHistoryChart, skipOffstage: false),
    );
    for (final extent in [600.0, 200.0, 600.0]) {
      height.value = extent;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      expect(_height(tester, 0), target);
      expect(controller.offset, 0);
      expect(
        tester.state(find.byType(TrafficHistoryChart, skipOffstage: false)),
        same(state),
      );
      expect(tester.hasRunningAnimations, isFalse);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('date navigation and live values ease from current height', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(controller: controller, snapshot: _snapshot(small: 200)),
    );
    final peak = _height(tester, 0);
    for (final date in [19, 20]) {
      await tester.pumpWidget(
        _host(
          controller: controller,
          snapshot: _snapshot(small: 600, date: date),
        ),
      );
      expect(_height(tester, 0), peak);
      if (date == 19) expect(_height(tester, 6), closeTo(peak * .2, .001));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_height(tester, 0), peak);
      expect(_height(tester, 6), inInclusiveRange(peak * .2, peak * .6));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_height(tester, 6), closeTo(peak * .6, .001));
    }
    await tester.pumpWidget(
      _host(controller: controller, snapshot: _snapshot(small: 0, date: 20)),
    );
    expect(_height(tester, 6), closeTo(peak * .6, .001));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_height(tester, 6), inExclusiveRange(3, peak * .6));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_height(tester, 6), closeTo(3, .001));
    final (dot, dotPaint) = _paints(tester, 6).single;
    await tester.pumpWidget(
      _host(controller: controller, snapshot: _snapshot(small: 200, date: 20)),
    );
    final (first, firstPaint) = _paints(tester, 6).single;
    expect(first.getBounds(), dot.getBounds());
    expect(firstPaint.color, dotPaint.color);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    final (morph, morphPaint) = _paints(tester, 6).single;
    expect(morph.getBounds().height, closeTo(3, .001));
    expect(morph.getBounds().width, inExclusiveRange(3, 12));
    expect(morphPaint.shader, isNotNull);
    await tester.pump(const Duration(milliseconds: 279));
    expect(_height(tester, 6), closeTo(peak * .2, .001));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('short capsules and zero dots retain rounded corners and gaps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(controller: controller, snapshot: _snapshot()),
    );
    for (final index in [0, 6, 1]) {
      final (path, paint) = _paints(tester, index).single;
      final rect = path.getBounds();
      final inset = rect.shortestSide * .05;
      expect(path.contains(rect.center), isTrue);
      expect(path.contains(rect.topLeft + Offset(inset, inset)), isFalse);
      expect(path.contains(rect.bottomRight - Offset(inset, inset)), isFalse);
      expect(
        rect.width,
        lessThanOrEqualTo(tester.getSize(_bar(index)).width * .57),
      );
      if (index == 1) {
        expect(rect.width, closeTo(rect.height, .001));
        expect(paint.shader, isNull);
      } else {
        expect(paint.shader, isNotNull);
      }
    }
    expect(_height(tester, 6), lessThan(5));
    final first = _paints(tester, 0).single.$1.getBounds();
    final next = _paints(tester, 1).single.$1.getBounds();
    final firstRight = tester.getTopLeft(_bar(0)).dx + first.right;
    final nextLeft = tester.getTopLeft(_bar(1)).dx + next.left;
    expect(nextLeft - firstRight, greaterThan(5));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reduced motion skips period growth and preserves selection', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        controller: controller,
        snapshot: _snapshot(small: 200),
        reducedMotion: true,
      ),
    );
    final target = _height(tester, 0);
    await tester.tap(_bar(6));
    await tester.pump();
    expect(find.text('06:00'), findsOneWidget);
    final selected = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.selected == true,
    );
    expect(
      tester.widget<Semantics>(selected).properties.label,
      startsWith('6, Download'),
    );
    final idleDot = _paints(tester, 1).single.$2.color;
    await tester.tap(_bar(1));
    await tester.pump();
    expect(find.text('01:00'), findsOneWidget);
    expect(_paints(tester, 1).single.$2.color.a, greaterThan(idleDot.a));
    expect(
      tester.widget<Semantics>(selected).properties.label,
      startsWith('1, Download'),
    );
    await tester.pumpWidget(
      _host(
        controller: controller,
        snapshot: _snapshot(small: 200),
        period: TrafficHistoryPeriod.week,
        reducedMotion: true,
      ),
    );
    expect(_height(tester, 0), target);
    expect(tester.hasRunningAnimations, isFalse);
    semantics.dispose();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
