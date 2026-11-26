import 'package:fl_clash/models/traffic_history.dart';
import 'package:fl_clash/ui/ui.dart' show Tooltip;
import 'package:fl_clash/widgets/traffic_history_chart.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

TrafficHistorySnapshot _snapshot({int peak = 1000, int small = 10}) {
  final day = TrafficDay('2026-11-19')
    ..addTotals(0, 0, peak)
    ..addTotals(6, 0, small);
  return TrafficHistorySnapshot(
    start: DateTime.utc(2026, 11, 19),
    end: DateTime.utc(2026, 11, 19),
    days: [day],
  );
}

Widget _host({
  required ScrollController controller,
  required TrafficHistorySnapshot snapshot,
  bool reducedMotion = false,
  TrafficHistoryPeriod period = TrafficHistoryPeriod.day,
  ValueNotifier<double>? viewportHeight,
  ValueNotifier<ScrollMetrics?>? viewportMetrics,
  double before = 40,
}) => TestApp(
  locale: const Locale('en'),
  child: Builder(
    builder: (context) {
      final scroll = NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          viewportMetrics?.value = notification.metrics;
          return false;
        },
        child: ListView(
          controller: controller,
          scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
          children: [
            SizedBox(height: before),
            TrafficHistoryChart(
              snapshot: snapshot,
              period: period,
              viewportChanges: viewportMetrics,
            ),
            const SizedBox(height: 1400),
          ],
        ),
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

Finder _bar(int hour) => find.byWidgetPredicate(
  (widget) => widget is Tooltip && widget.message.startsWith('$hour:'),
  skipOffstage: false,
);

double _scale(WidgetTester tester, int hour) => tester
    .widget<Transform>(
      find.descendant(
        of: _bar(hour),
        matching: find.byType(Transform, skipOffstage: false),
        skipOffstage: false,
      ),
    )
    .transform
    .storage[5];

void main() {
  testWidgets('bars grow from zero, overshoot and settle without layout work', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(controller: controller, snapshot: _snapshot()),
    );
    final size = tester.getSize(_bar(0));
    expect(_scale(tester, 0), 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(_scale(tester, 0), greaterThan(1));
    expect(_scale(tester, 0), lessThan(1.12));
    expect(tester.getSize(_bar(0)), size);
    await tester.pump(const Duration(milliseconds: 600));
    expect(_scale(tester, 0), closeTo(1, .0001));
    expect(_scale(tester, 6), closeTo(.022, .0001));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('only a full viewport exit arms another entrance', (
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
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final state = tester.state(
      find.byType(TrafficHistoryChart, skipOffstage: false),
    );
    expect(_scale(tester, 0), closeTo(1, .0001));
    controller.jumpTo(20);
    await tester.pump();
    expect(_scale(tester, 0), closeTo(1, .0001));
    controller.jumpTo(550);
    await tester.pump();
    expect(
      tester.state(find.byType(TrafficHistoryChart, skipOffstage: false)),
      same(state),
    );
    controller.jumpTo(0);
    await tester.pump();
    await tester.pump();
    expect(_scale(tester, 0), 0);
    await tester.pump(const Duration(milliseconds: 140));
    expect(_scale(tester, 0), inExclusiveRange(0, 1));
    await tester.pump(const Duration(seconds: 1));
    expect(_scale(tester, 0), closeTo(1, .0001));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('resizing a retained viewport starts and rearms entrance', (
    tester,
  ) async {
    final controller = ScrollController();
    final height = ValueNotifier<double>(200);
    final metrics = ValueNotifier<ScrollMetrics?>(null);
    addTearDown(controller.dispose);
    addTearDown(height.dispose);
    addTearDown(metrics.dispose);
    await tester.pumpWidget(
      _host(
        controller: controller,
        snapshot: _snapshot(),
        viewportHeight: height,
        viewportMetrics: metrics,
        before: 220,
      ),
    );
    await tester.pump();
    final state = tester.state(
      find.byType(TrafficHistoryChart, skipOffstage: false),
    );
    expect(_scale(tester, 0), 0);
    height.value = 600;
    await tester.pump();
    await tester.pump();
    expect(metrics.value?.viewportDimension, 600);
    // Metrics arrive after layout; visibility starts the ticker next frame.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));
    expect(_scale(tester, 0), inExclusiveRange(0, 1));
    await tester.pump(const Duration(seconds: 1));
    expect(_scale(tester, 0), closeTo(1, .0001));
    height.value = 200;
    await tester.pump();
    await tester.pump();
    height.value = 600;
    await tester.pump();
    await tester.pump();
    expect(metrics.value?.viewportDimension, 600);
    // Metrics arrive after layout; visibility starts the ticker next frame.
    await tester.pump();
    expect(_scale(tester, 0), 0);
    await tester.pump(const Duration(milliseconds: 140));
    expect(_scale(tester, 0), inExclusiveRange(0, 1));
    expect(controller.offset, 0);
    expect(
      tester.state(find.byType(TrafficHistoryChart, skipOffstage: false)),
      same(state),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('live samples continue from the visible height', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(controller: controller, snapshot: _snapshot(small: 200)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(_scale(tester, 6), closeTo(.2, .0001));
    await tester.pumpWidget(
      _host(controller: controller, snapshot: _snapshot(small: 600)),
    );
    expect(_scale(tester, 6), closeTo(.2, .0001));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_scale(tester, 6), inExclusiveRange(.2, .6));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_scale(tester, 6), closeTo(.6, .0001));
    await tester.pumpWidget(
      _host(controller: controller, snapshot: _snapshot(small: 600)),
    );
    expect(_scale(tester, 6), closeTo(.6, .0001));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reduced motion shows final values and bars expose selection', (
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
    await tester.pump();
    expect(_scale(tester, 0), closeTo(1, .0001));
    expect(_scale(tester, 6), closeTo(.2, .0001));
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
    semantics.dispose();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
