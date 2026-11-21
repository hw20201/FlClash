import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fl_clash/common/exit_map_geo.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/exit_map.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/exit_map/camera.dart';
import 'package:fl_clash/views/dashboard/exit_map/canvas.dart';
import 'package:fl_clash/views/dashboard/exit_map/data.dart';
import 'package:fl_clash/views/dashboard/exit_map/gestures.dart';
import 'package:fl_clash/views/dashboard/widgets/card.dart';
import 'package:fl_clash/views/dashboard/widgets/exit_map.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/host_scaffold.dart';
import '../../helpers/test_app.dart';

class _Origin extends ExitMapOrigin {
  var watchers = 0;

  @override
  RoutedProbeState<String, ExitMapPlace> build() => const RoutedProbeState();

  void show(ProbeEntry<ExitMapPlace> entry) {
    state = RoutedProbeState({directOutbound: entry});
  }

  @override
  void watch(String target) {
    expect(target, directOutbound);
    watchers++;
  }

  @override
  void unwatch(String target) {
    expect(target, directOutbound);
    watchers--;
  }
}

void main() {
  late ProviderContainer container;
  late _Origin origin;

  setUp(() {
    origin = _Origin();
    container = ProviderContainer(
      overrides: [
        coreStatusProvider.overrideWithBuild((_, _) => CoreStatus.connected),
        exitMapOriginProvider.overrideWith(() => origin),
      ],
    );
    globalState.container = container;
  });

  tearDown(() => container.dispose());

  var connectionId = 0;

  void connect(String node) {
    container
        .read(connectionBookProvider)
        .apply(
          ConnectionsReset(
            ConnectionSnapshot([
              ConnectionInfo(
                id: ++connectionId,
                start: 1,
                network: 'tcp',
                sourceIp: '127.0.0.1',
                sourcePort: 50000,
                destinationPort: 443,
                inboundType: 'mixed',
                chains: [node, 'Proxy'],
                rule: 'MATCH',
                upload: 0,
                download: 100,
              ),
            ]),
          ),
        );
  }

  Future<Uint8List> landPixels(WidgetTester tester) async =>
      (await tester.runAsync(() async {
        final layer = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('exit-map-land')),
        );
        final image = await layer.toImage(pixelRatio: 1);
        try {
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          return Uint8List.fromList(data!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      }))!;

  Future<void> pumpCard(
    WidgetTester tester, {
    bool active = true,
    ScrollController? scroll,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          child: HostScaffold(
            body: PageActivityScope(
              isActive: active,
              child: SingleChildScrollView(
                controller: scroll,
                child: const Column(
                  children: [ExitMapCard(), SizedBox(height: 1500)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  TransformationController camera(WidgetTester tester) => tester
      .widget<ExitMapGestureRegion>(find.byType(ExitMapGestureRegion))
      .controller;

  ExitMapCameraBounds limits(WidgetTester tester) => tester
      .widget<ExitMapGestureRegion>(find.byType(ExitMapGestureRegion))
      .bounds()!;

  double panX(Matrix4 before, Matrix4 after) {
    final period = after.getMaxScaleOnAxis() * exitMapWorld.width;
    return (after.getTranslation().x - before.getTranslation().x + period / 2) %
            period -
        period / 2;
  }

  void expectCamera(Matrix4 actual, Matrix4 target) {
    expect(
      actual.getMaxScaleOnAxis(),
      closeTo(target.getMaxScaleOnAxis(), 1e-9),
    );
    expect(panX(target, actual), closeTo(0, 1e-8));
    expect(actual.getTranslation().y, closeTo(target.getTranslation().y, 1e-8));
  }

  Finder mapViewport() => find.byKey(const ValueKey('exit-map-viewport'));

  Finder resetButton() => find.byWidgetPredicate(
    (widget) => widget is IconButton && widget.tooltip == 'Reset',
  );

  Future<void> closeCard(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  }

  Future<void> spreadPointers(
    WidgetTester tester,
    TestGesture first,
    TestGesture second,
    Offset firstPosition,
    Offset secondPosition, {
    double factor = 2.5,
  }) async {
    final center = (firstPosition + secondPosition) / 2;
    final halfSpan = (secondPosition - firstPosition) / 2;
    for (var step = 1; step <= 8; step++) {
      final span = halfSpan * (1 + (factor - 1) * step / 8);
      await first.moveTo(center - span);
      await second.moveTo(center + span);
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<TestGesture> fastMapPan(WidgetTester tester) async {
    final gesture = await tester.startGesture(tester.getCenter(mapViewport()));
    for (var step = 1; step <= 8; step++) {
      await gesture.moveBy(
        const Offset(12, 0),
        timeStamp: Duration(milliseconds: step * 16),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    return gesture;
  }

  testWidgets('empty, locating and failed origins stay usable', (tester) async {
    await pumpCard(tester);
    expect(origin.watchers, 1);
    expect(find.text('Location unavailable · East Asia view'), findsOneWidget);
    origin.show(const ProbeEntry(phase: ProbePhase.probing));
    await tester.pump();
    expect(find.text('Locating your direct connection…'), findsOneWidget);
    origin.show(const ProbeEntry(phase: ProbePhase.failed));
    await tester.pump();
    await tester.pump(exitMapTransitionDuration);
    expect(find.text('Location unavailable · East Asia view'), findsOneWidget);
    origin.show(
      ProbeEntry(phase: ProbePhase.fresh, value: locateExit('Tokyo')),
    );
    await tester.pump();
    expect(find.text('No active proxy exits to show'), findsNothing);
    expect(tester.getSize(mapViewport()).height, greaterThan(165));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(origin.watchers, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Chinese origins show only the country on the card and map', (
    tester,
  ) async {
    await pumpCard(tester);
    origin.show(
      ProbeEntry(
        phase: ProbePhase.fresh,
        value: parseExitMapOrigin(
          '{"country_code":"CN","city":"Shanghai","latitude":31.23,"longitude":121.47}',
        ),
      ),
    );
    await tester.pump();
    final label = tester.widget<Text>(find.text('You · ≈ 🇨🇳 China'));
    final spans = (label.textSpan! as TextSpan).children!.whereType<TextSpan>();
    final flag = spans.singleWhere((span) => span.text == '🇨🇳');
    expect(flag.style?.fontFamily, 'Twemoji');
    expect(find.textContaining('Shanghai'), findsNothing);
    final place = tester
        .widget<ExitMapCanvas>(find.byType(ExitMapCanvas))
        .origin!;
    expect(place.city, isEmpty);
    expect(place.latitude, 35);
    expect(place.longitude, 105);
    origin.show(
      ProbeEntry(
        phase: ProbePhase.fresh,
        value: parseExitMapOrigin(
          '{"country":"JP","city":"Tokyo","loc":"35.7,139.7"}',
        ),
      ),
    );
    await tester.pump();
    expect(find.text('You · 🇯🇵 Tokyo'), findsOneWidget);
    expect(
      tester
          .widget<ExitMapCanvas>(find.byType(ExitMapCanvas))
          .origin
          ?.longitude,
      139.7,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('one finger pans at normal scale and reset restores the map', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await pumpCard(tester, scroll: scroll);
    final viewer = find.byKey(const ValueKey('exit-map-viewport'));
    final transform = tester
        .widget<ExitMapGestureRegion>(find.byType(ExitMapGestureRegion))
        .controller;
    final size = tester.getSize(find.byType(ExitMapCard));
    final home = Matrix4.copy(transform.value);
    final reset = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Reset',
    );
    expect(find.byType(IconButton), findsOneWidget);
    expect(tester.widget<IconButton>(reset).onPressed, isNull);
    final pan = await tester.startGesture(tester.getCenter(viewer));
    for (var i = 0; i < 3; i++) {
      await pan.moveBy(const Offset(25, -10));
      await tester.pump();
    }
    await pan.up();
    await tester.pump();
    expect(transform.value.getMaxScaleOnAxis(), home.getMaxScaleOnAxis());
    expect(panX(home, transform.value), greaterThan(0));
    expect(
      transform.value.getTranslation().y,
      lessThan(home.getTranslation().y),
    );
    expect(scroll.position.pixels, 0);
    expect(tester.widget<IconButton>(reset).onPressed, isNotNull);
    await tester.tap(reset);
    await tester.pump();
    await tester.pump(exitMapTransitionDuration);
    expectCamera(transform.value, home);
    expect(tester.getSize(find.byType(ExitMapCard)), size);
    expect(tester.widget<IconButton>(reset).onPressed, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  for (final delta in [const Offset(0, -3), const Offset(1.5, -1)]) {
    testWidgets('small-step map pan $delta keeps the dashboard still', (
      tester,
    ) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await pumpCard(tester, scroll: scroll);
      final viewer = find.byKey(const ValueKey('exit-map-viewport'));
      final transform = tester
          .widget<ExitMapGestureRegion>(find.byType(ExitMapGestureRegion))
          .controller;
      final cardBounds = tester.getRect(find.byType(ExitMapCard));
      final home = Matrix4.copy(transform.value);
      final pan = await tester.startGesture(tester.getCenter(viewer));
      for (var i = 0; i < 24; i++) {
        await pan.moveBy(delta);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await pan.up();
      await tester.pump();
      expect(transform.value.getMaxScaleOnAxis(), home.getMaxScaleOnAxis());
      expect(
        transform.value.getTranslation().y,
        lessThan(home.getTranslation().y),
      );
      if (delta.dx != 0) {
        expect(panX(home, transform.value), greaterThan(0));
      }
      expect(scroll.position.pixels, 0);
      expect(tester.getRect(find.byType(ExitMapCard)), cardBounds);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('panning an idle map paints the newly visible land', (
    tester,
  ) async {
    await pumpCard(tester);
    origin.show(
      ProbeEntry(phase: ProbePhase.fresh, value: locateExit('Tokyo')),
    );
    await tester.pump();
    await tester.pump(exitMapTransitionDuration);
    final transform = camera(tester);
    final home = Matrix4.copy(transform.value);
    final before = await landPixels(tester);
    final land = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('exit-map-land')),
    )..debugResetMetrics();
    final pan = await tester.startGesture(tester.getCenter(mapViewport()));
    for (var step = 0; step < 4; step++) {
      await pan.moveBy(const Offset(-28, -14));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await pan.cancel();
    await tester.pump();
    expect(panX(home, transform.value), lessThan(-20));
    expect(
      land.debugAsymmetricPaintCount + land.debugSymmetricPaintCount,
      greaterThan(0),
    );
    expect(await landPixels(tester), isNot(orderedEquals(before)));

    await tester.tap(resetButton());
    await tester.pump();
    await tester.pump(exitMapTransitionDuration);
    expectCamera(transform.value, home);
    expect(await landPixels(tester), orderedEquals(before));
    expect(find.byKey(const ValueKey('exit-map-flow')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('an automatic fit animates and settles around the new route', (
    tester,
  ) async {
    await pumpCard(tester);
    final transform = camera(tester);
    final initial = Matrix4.copy(transform.value);
    origin.show(
      ProbeEntry(phase: ProbePhase.fresh, value: locateExit('Tokyo')),
    );
    await tester.pump();
    expectCamera(transform.value, initial);
    await tester.pump(exitMapTransitionDuration);
    final regional = Matrix4.copy(transform.value);
    expect(regional, isNot(initial));

    connect('London');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expectCamera(transform.value, regional);
    await tester.pump(exitMapTransitionDuration ~/ 2);
    final mid = transform.value.getMaxScaleOnAxis();
    await tester.pump(exitMapTransitionDuration);
    final end = transform.value.getMaxScaleOnAxis();
    expect(end, lessThan(mid));
    expect(mid, lessThan(regional.getMaxScaleOnAxis()));
    final region = limits(tester);
    expect(region.world, exitMapWorld);
    expect(region.maxScale, closeTo(4 * end, 1e-9));
    expect(
      tester
          .widget<ExitMapCanvas>(find.byType(ExitMapCanvas))
          .routes
          .single
          .node,
      'London',
    );
    await closeCard(tester);
  });

  testWidgets(
    'a manually panned map stays in place when location and route refresh',
    (tester) async {
      await pumpCard(tester);
      final transform = camera(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(mapViewport()),
      );
      await gesture.moveBy(const Offset(80, 48));
      await tester.pump();
      await gesture.cancel();
      final manual = Matrix4.copy(transform.value);
      final maximum = limits(tester).maxScale;
      expect(tester.widget<IconButton>(resetButton()).onPressed, isNotNull);

      connect('London');
      origin.show(
        ProbeEntry(phase: ProbePhase.fresh, value: locateExit('Tokyo')),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await tester.pump(exitMapTransitionDuration);
      expectCamera(transform.value, manual);
      expect(limits(tester).maxScale, maximum);
      await tester.tap(resetButton());
      await tester.pump();
      await tester.pump(exitMapTransitionDuration);
      expect(
        transform.value.getMaxScaleOnAxis(),
        lessThan(manual.getMaxScaleOnAxis()),
      );
      expect(tester.widget<IconButton>(resetButton()).onPressed, isNull);
      await closeCard(tester);
    },
  );

  for (final region in ['header', 'location', 'padding']) {
    testWidgets('a $region pinch zooms only the map', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await pumpCard(tester, scroll: scroll);
      origin.show(
        ProbeEntry(phase: ProbePhase.fresh, value: locateExit('Tokyo')),
      );
      await tester.pump();
      await tester.pump(exitMapTransitionDuration);
      final transform = camera(tester);
      final home = Matrix4.copy(transform.value);
      final header = find.byType(DashboardCardHeader);
      final location = find.text('You · 🇯🇵 ${locateExit('Tokyo')!.city}');
      final reset = resetButton();
      final fixed = [find.byType(ExitMapCard), header, location, reset];
      final before = fixed.map(tester.getRect).toList();
      final card = before.first;
      final center = switch (region) {
        'header' => tester.getRect(header).centerLeft + const Offset(90, 0),
        'location' => tester.getCenter(location),
        _ => Offset(card.left + 6, card.center.dy),
      };
      final span = region == 'padding'
          ? const Offset(0, 20)
          : const Offset(20, 0);
      final first = await tester.startGesture(center - span, pointer: 1);
      final second = await tester.startGesture(center + span, pointer: 2);
      await tester.pump();
      await spreadPointers(tester, first, second, center - span, center + span);
      expect(
        transform.value.getMaxScaleOnAxis(),
        greaterThan(home.getMaxScaleOnAxis()),
      );
      expect(fixed.map(tester.getRect).toList(), before);
      expect(scroll.position.pixels, 0);
      expect(tester.widget<IconButton>(reset).onPressed, isNotNull);
      await first.up();
      await second.up();
      await tester.tap(reset);
      await tester.pump();
      await tester.pump(exitMapTransitionDuration);
      expectCamera(transform.value, home);
      await closeCard(tester);
    });
  }

  for (final mapFirst in [false, true]) {
    testWidgets(
      'a mixed pinch joins ${mapFirst ? 'an already panning map finger' : 'a waiting header finger'}',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        await pumpCard(tester, scroll: scroll);
        final transform = camera(tester);
        final home = Matrix4.copy(transform.value);
        final cardBounds = tester.getRect(find.byType(ExitMapCard));
        final header = tester.getRect(find.byType(DashboardCardHeader));
        var mapPosition = tester.getCenter(mapViewport());
        var headerPosition = header.centerLeft + const Offset(90, 0);
        final first = await tester.startGesture(
          mapFirst ? mapPosition : headerPosition,
          pointer: 1,
        );
        if (mapFirst) {
          for (var step = 0; step < 3; step++) {
            mapPosition += const Offset(12, 0);
            await first.moveTo(mapPosition);
            await tester.pump(const Duration(milliseconds: 16));
          }
          expect(panX(home, transform.value), greaterThan(0));
        } else {
          headerPosition += const Offset(6, 0);
          await first.moveTo(headerPosition);
          await tester.pump();
          expectCamera(transform.value, home);
        }
        final second = await tester.startGesture(
          mapFirst ? headerPosition : mapPosition,
          pointer: 2,
        );
        await tester.pump();
        await spreadPointers(
          tester,
          first,
          second,
          mapFirst ? mapPosition : headerPosition,
          mapFirst ? headerPosition : mapPosition,
          factor: 1.8,
        );
        expect(
          transform.value.getMaxScaleOnAxis(),
          greaterThan(home.getMaxScaleOnAxis()),
        );
        expect(
          transform.value.getMaxScaleOnAxis(),
          lessThanOrEqualTo(limits(tester).maxScale),
        );
        expect(scroll.position.pixels, 0);
        expect(tester.getRect(find.byType(ExitMapCard)), cardBounds);
        await first.up();
        await second.up();
        await closeCard(tester);
      },
    );
  }

  for (final region in ['header', 'location', 'padding']) {
    testWidgets('one $region finger scrolls the dashboard', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await pumpCard(tester, scroll: scroll);
      final card = tester.getRect(find.byType(ExitMapCard));
      final home = Matrix4.copy(camera(tester).value);
      final position = switch (region) {
        'header' =>
          tester.getRect(find.byType(DashboardCardHeader)).centerLeft +
              const Offset(90, 0),
        'location' => tester.getCenter(
          find.text('Location unavailable · East Asia view'),
        ),
        _ => Offset(card.left + 6, card.center.dy),
      };
      final finger = await tester.startGesture(position);
      for (var step = 0; step < 8; step++) {
        await finger.moveBy(const Offset(0, -8));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(scroll.position.pixels, greaterThan(0));
      expectCamera(camera(tester).value, home);
      await finger.up();
      await closeCard(tester);
    });
  }

  testWidgets('a second map finger does not steal a won header scroll', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await pumpCard(tester, scroll: scroll);
    final transform = camera(tester);
    final home = Matrix4.copy(transform.value);
    final header = tester.getRect(find.byType(DashboardCardHeader));
    final first = await tester.startGesture(
      header.centerLeft + const Offset(90, 0),
      pointer: 1,
    );
    for (var step = 0; step < 4; step++) {
      await first.moveBy(const Offset(0, -10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(scroll.position.pixels, greaterThan(0));
    final scrolling = scroll.position.pixels;
    final second = await tester.startGesture(
      tester.getCenter(mapViewport()),
      pointer: 2,
    );
    for (var step = 0; step < 4; step++) {
      await first.moveBy(const Offset(-10, -3));
      await second.moveBy(const Offset(10, -3));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expectCamera(transform.value, home);
    expect(scroll.position.pixels, greaterThanOrEqualTo(scrolling));
    await first.up();
    await second.moveBy(const Offset(40, 0));
    await tester.pump();
    expectCamera(transform.value, home);
    await second.up();
    scroll.jumpTo(0);
    await tester.pump();
    final fresh = await tester.startGesture(tester.getCenter(mapViewport()));
    await fresh.moveBy(const Offset(30, 0));
    await tester.pump();
    await fresh.moveBy(const Offset(20, 0));
    await tester.pump();
    expect(panX(home, transform.value), greaterThan(0));
    await fresh.up();
    await closeCard(tester);
  });

  testWidgets('a header finger left after a pinch cannot pan the map', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await pumpCard(tester, scroll: scroll);
    final transform = camera(tester);
    final home = Matrix4.copy(transform.value);
    final mapPosition = tester.getCenter(mapViewport());
    final headerPosition =
        tester.getRect(find.byType(DashboardCardHeader)).centerLeft +
        const Offset(90, 0);
    final first = await tester.startGesture(mapPosition, pointer: 1);
    final second = await tester.startGesture(headerPosition, pointer: 2);
    await spreadPointers(
      tester,
      first,
      second,
      mapPosition,
      headerPosition,
      factor: 1.6,
    );
    expect(
      transform.value.getMaxScaleOnAxis(),
      greaterThan(home.getMaxScaleOnAxis()),
    );
    await first.up();
    final before = Matrix4.copy(transform.value);
    for (var step = 0; step < 5; step++) {
      await second.moveBy(const Offset(12, -8));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(transform.value, before);
    expect(scroll.position.pixels, 0);
    await second.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(transform.value, before);
    await closeCard(tester);
  });

  testWidgets('a continuous pinch clamps to both scale limits', (tester) async {
    await pumpCard(tester);
    final transform = camera(tester);
    final bounds = limits(tester);
    final center = tester.getCenter(mapViewport());
    const span = Offset(20, 0);
    final first = await tester.startGesture(center - span, pointer: 1);
    final second = await tester.startGesture(center + span, pointer: 2);
    await spreadPointers(
      tester,
      first,
      second,
      center - span,
      center + span,
      factor: 12,
    );
    expect(transform.value.getMaxScaleOnAxis(), bounds.maxScale);
    for (var step = 1; step <= 8; step++) {
      final halfSpan = 240 - 238 * step / 8;
      await first.moveTo(center - Offset(halfSpan, 0));
      await second.moveTo(center + Offset(halfSpan, 0));
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        transform.value.getMaxScaleOnAxis(),
        inInclusiveRange(bounds.minScale, bounds.maxScale),
      );
    }
    expect(transform.value.getMaxScaleOnAxis(), bounds.minScale);
    expect(bounds.world.width * bounds.minScale, lessThan(bounds.size.width));
    expect(bounds.world.height * bounds.minScale, lessThan(bounds.size.height));
    await first.up();
    await second.up();
    await closeCard(tester);
  });

  testWidgets('canceling a fast pan leaves no inertia or ticker', (
    tester,
  ) async {
    await pumpCard(tester);
    final transform = camera(tester);
    final gesture = await fastMapPan(tester);
    await gesture.cancel(timeStamp: const Duration(milliseconds: 144));
    await tester.pump();
    final canceled = Matrix4.copy(transform.value);
    await tester.pump(const Duration(milliseconds: 300));
    expect(transform.value, canceled);
    expect(tester.binding.transientCallbackCount, 0);
    await closeCard(tester);
  });

  testWidgets('reset stops a released pan without a later camera write', (
    tester,
  ) async {
    await pumpCard(tester);
    final transform = camera(tester);
    final home = Matrix4.copy(transform.value);
    final gesture = await fastMapPan(tester);
    await gesture.up(timeStamp: const Duration(milliseconds: 144));
    final released = Matrix4.copy(transform.value);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 32));
    expect(transform.value, isNot(released));
    await tester.tap(resetButton());
    await tester.pump();
    await tester.pump(exitMapTransitionDuration);
    expectCamera(transform.value, home);
    await tester.pump(const Duration(milliseconds: 600));
    expectCamera(transform.value, home);
    expect(tester.binding.transientCallbackCount, 0);
    await closeCard(tester);
  });

  testWidgets('a new contact stops inertia and disposal releases its ticker', (
    tester,
  ) async {
    await pumpCard(tester);
    final transform = camera(tester);
    final gesture = await fastMapPan(tester);
    await gesture.up(timeStamp: const Duration(milliseconds: 144));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 32));
    final next = await tester.startGesture(tester.getCenter(mapViewport()));
    final stopped = Matrix4.copy(transform.value);
    await tester.pump(const Duration(milliseconds: 200));
    expect(transform.value, stopped);
    await next.cancel();
    await closeCard(tester);
  });

  testWidgets('trackpad scale and map wheel zoom leave the card fixed', (
    tester,
  ) async {
    await pumpCard(tester);
    final transform = camera(tester);
    final home = Matrix4.copy(transform.value);
    final bounds = limits(tester);
    final card = tester.getRect(find.byType(ExitMapCard));
    final point = tester.getCenter(mapViewport());
    final trackpad = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    await trackpad.panZoomStart(point);
    for (var step = 1; step <= 4; step++) {
      await trackpad.panZoomUpdate(point, scale: 1 + step * 0.25);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      transform.value.getMaxScaleOnAxis(),
      greaterThan(home.getMaxScaleOnAxis()),
    );
    expect(tester.getRect(find.byType(ExitMapCard)), card);
    await trackpad.panZoomEnd();
    await tester.sendEventToBinding(
      PointerScrollEvent(position: point, scrollDelta: const Offset(0, -2000)),
    );
    await tester.pump();
    expect(transform.value.getMaxScaleOnAxis(), bounds.maxScale);
    await tester.sendEventToBinding(
      PointerScrollEvent(position: point, scrollDelta: const Offset(0, 2000)),
    );
    await tester.pump();
    expect(transform.value.getMaxScaleOnAxis(), bounds.minScale);
    expect(tester.getRect(find.byType(ExitMapCard)), card);
    await closeCard(tester);
  });

  testWidgets('the dashboard scrolls from outside the map', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await pumpCard(tester, scroll: scroll);
    await tester.dragFrom(
      tester.getBottomLeft(find.byType(ExitMapCard)) + const Offset(50, 80),
      const Offset(0, -100),
    );
    await tester.pump();
    expect(scroll.position.pixels, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('two fingers zoom, one finger pans, and reset restores both', (
    tester,
  ) async {
    await pumpCard(tester);
    final viewer = find.byKey(const ValueKey('exit-map-viewport'));
    final transform = tester
        .widget<ExitMapGestureRegion>(find.byType(ExitMapGestureRegion))
        .controller;
    final home = Matrix4.copy(transform.value);
    final center = tester.getCenter(viewer);
    final first = await tester.startGesture(
      center - const Offset(20, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      center + const Offset(20, 0),
      pointer: 2,
    );
    await tester.pump();
    await first.moveTo(center - const Offset(60, 0));
    await second.moveTo(center + const Offset(60, 0));
    await tester.pump();
    await first.moveTo(center - const Offset(200, 0));
    await second.moveTo(center + const Offset(200, 0));
    await tester.pump();
    expect(
      transform.value.getMaxScaleOnAxis(),
      greaterThan(home.getMaxScaleOnAxis()),
    );
    expect(
      transform.value.getMaxScaleOnAxis(),
      lessThanOrEqualTo(limits(tester).maxScale),
    );
    await first.up();
    await second.up();
    await tester.pump();
    final zoom = transform.value.getMaxScaleOnAxis();
    final before = Matrix4.copy(transform.value);
    final pan = await tester.startGesture(center);
    for (var i = 0; i < 3; i++) {
      await pan.moveBy(const Offset(25, 0));
      await tester.pump();
    }
    await pan.up();
    expect(panX(before, transform.value), greaterThan(0));
    expect(transform.value.getMaxScaleOnAxis(), zoom);
    final reset = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Reset',
    );
    await tester.tap(reset);
    await tester.pump();
    await tester.pump(exitMapTransitionDuration);
    expectCamera(transform.value, home);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('returning onscreen refreshes connections and the origin', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    connect('Tokyo');
    await pumpCard(tester, scroll: scroll);
    origin.show(ProbeEntry(phase: ProbePhase.fresh, value: locateExit('香港')));
    await tester.pump();
    expect(
      tester
          .widget<ExitMapCanvas>(find.byType(ExitMapCanvas))
          .routes
          .single
          .node,
      'Tokyo',
    );
    scroll.jumpTo(1000);
    await tester.pump();
    await tester.pump();
    expect(origin.watchers, 0);
    connect('London');
    origin.show(
      ProbeEntry(phase: ProbePhase.fresh, value: locateExit('Tokyo')),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(
      tester
          .widget<ExitMapCanvas>(find.byType(ExitMapCanvas))
          .routes
          .single
          .node,
      'Tokyo',
    );
    scroll.jumpTo(0);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    final canvas = tester.widget<ExitMapCanvas>(find.byType(ExitMapCanvas));
    expect(canvas.routes.single.node, 'London');
    expect(canvas.origin?.country, 'JP');
    expect(origin.watchers, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(origin.watchers, 0);
  });

  testWidgets(
    'scrolling offscreen or leaving a page releases the origin probe',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await pumpCard(tester, scroll: scroll);
      expect(origin.watchers, 1);
      scroll.jumpTo(1000);
      await tester.pump();
      await tester.pump();
      expect(origin.watchers, 0);
      scroll.jumpTo(0);
      await tester.pump();
      await tester.pump();
      expect(origin.watchers, 1);
      await pumpCard(tester, active: false, scroll: scroll);
      expect(origin.watchers, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      expect(origin.watchers, 0);
    },
  );
}
