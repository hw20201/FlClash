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
import 'package:fl_clash/views/dashboard/exit_map/canvas.dart';
import 'package:fl_clash/views/dashboard/widgets/exit_map.dart';
import 'package:fl_clash/widgets/widgets.dart';
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

  testWidgets('empty, locating and failed origins stay usable', (tester) async {
    await pumpCard(tester);
    expect(origin.watchers, 1);
    expect(find.text('Location unavailable · East Asia view'), findsOneWidget);
    origin.show(const ProbeEntry(phase: ProbePhase.probing));
    await tester.pump();
    expect(find.text('Locating your direct connection…'), findsOneWidget);
    origin.show(const ProbeEntry(phase: ProbePhase.failed));
    await tester.pump();
    expect(find.text('Location unavailable · East Asia view'), findsOneWidget);
    origin.show(
      ProbeEntry(phase: ProbePhase.fresh, value: locateExit('Tokyo')),
    );
    await tester.pump();
    expect(find.text('No active proxy exits to show'), findsOneWidget);
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
    expect(find.text('You · ≈ 🇨🇳 China'), findsOneWidget);
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
    final viewer = find.byType(InteractiveViewer);
    final transform = tester
        .widget<InteractiveViewer>(viewer)
        .transformationController!;
    final size = tester.getSize(find.byType(ExitMapCard));
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
    expect(transform.value.getMaxScaleOnAxis(), 1);
    expect(transform.value.getTranslation().x, greaterThan(0));
    expect(transform.value.getTranslation().y, lessThan(0));
    expect(scroll.position.pixels, 0);
    expect(tester.widget<IconButton>(reset).onPressed, isNotNull);
    await tester.tap(reset);
    await tester.pump();
    expect(transform.value, Matrix4.identity());
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
      final viewer = find.byType(InteractiveViewer);
      final transform = tester
          .widget<InteractiveViewer>(viewer)
          .transformationController!;
      final cardBounds = tester.getRect(find.byType(ExitMapCard));
      final pan = await tester.startGesture(tester.getCenter(viewer));
      for (var i = 0; i < 24; i++) {
        await pan.moveBy(delta);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await pan.up();
      await tester.pump();
      expect(transform.value.getMaxScaleOnAxis(), 1);
      expect(transform.value.getTranslation().y, lessThan(0));
      if (delta.dx != 0) {
        expect(transform.value.getTranslation().x, greaterThan(0));
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
    final viewer = find.byType(InteractiveViewer);
    final transform = tester
        .widget<InteractiveViewer>(viewer)
        .transformationController!;
    final size = tester.getSize(viewer);
    final before = await landPixels(tester);
    transform.value = Matrix4.identity()
      ..translateByDouble(0, -size.height * 0.4, 0, 1);
    await tester.pump();
    final after = await landPixels(tester);
    expect(after, isNot(orderedEquals(before)));
    final width = size.width.ceil();
    final firstPixel = width * (size.height * 0.7).ceil();
    expect([
      for (var i = firstPixel * 4 + 3; i < after.length; i += 4)
        if (after[i] > 0) after[i],
    ], isNotEmpty);
    transform.value = Matrix4.identity();
    await tester.pump();
    expect(await landPixels(tester), orderedEquals(before));
    expect(find.byKey(const ValueKey('exit-map-flow')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final atEdge in [false, true]) {
    testWidgets(
      'a live refit ${atEdge ? 'recovers an out-of-bounds camera' : 'preserves a valid pan'}',
      (tester) async {
        await pumpCard(tester);
        origin.show(
          ProbeEntry(phase: ProbePhase.fresh, value: locateExit('Tokyo')),
        );
        await tester.pump();
        final viewer = find.byType(InteractiveViewer);
        final transform = tester
            .widget<InteractiveViewer>(viewer)
            .transformationController!;
        final size = tester.getSize(viewer);
        final before = tester.widget<ExitMapCanvas>(find.byType(ExitMapCanvas));
        final world = before.viewport!
            .worldRect(size)
            .expandToInclude(Offset.zero & size);
        transform.value = atEdge
            ? (Matrix4.identity()..translateByDouble(-world.left - 1, 0, 0, 1))
            : (Matrix4.identity()
                ..translateByDouble(-20, -10, 0, 1)
                ..scaleByDouble(2, 2, 2, 1));
        await tester.pump();
        final panned = Matrix4.copy(transform.value);
        final oldView = MatrixUtils.transformRect(
          Matrix4.inverted(panned),
          Offset.zero & size,
        );
        expect(world.inflate(1e-6).contains(oldView.topLeft), isTrue);
        expect(world.inflate(1e-6).contains(oldView.bottomRight), isTrue);
        connect('London');
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        await tester.pump();
        final canvas = tester.widget<ExitMapCanvas>(find.byType(ExitMapCanvas));
        expect(canvas.routes.single.node, 'London');
        expect(canvas.viewport, isNot(before.viewport));
        final bounds = canvas.viewport!
            .worldRect(size)
            .expandToInclude(Offset.zero & size)
            .inflate(1e-6);
        expect(bounds.contains(oldView.topLeft), !atEdge);
        final visible = MatrixUtils.transformRect(
          Matrix4.inverted(transform.value),
          Offset.zero & size,
        );
        expect(bounds.contains(visible.topLeft), isTrue);
        expect(bounds.contains(visible.bottomRight), isTrue);
        expect(transform.value, atEdge ? Matrix4.identity() : panned);
        final pixels = await landPixels(tester);
        expect([
          for (var i = 3; i < pixels.length; i += 4)
            if (pixels[i] > 0) pixels[i],
        ], isNotEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull);
      },
    );
  }

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
    final viewer = find.byType(InteractiveViewer);
    final transform = tester
        .widget<InteractiveViewer>(viewer)
        .transformationController!;
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
    expect(transform.value.getMaxScaleOnAxis(), greaterThan(1));
    expect(transform.value.getMaxScaleOnAxis(), lessThanOrEqualTo(4));
    await first.up();
    await second.up();
    await tester.pump();
    final zoom = transform.value.getMaxScaleOnAxis();
    final before = transform.value.getTranslation();
    final pan = await tester.startGesture(center);
    for (var i = 0; i < 3; i++) {
      await pan.moveBy(const Offset(25, 0));
      await tester.pump();
    }
    await pan.up();
    expect(transform.value.getTranslation().x, greaterThan(before.x));
    expect(transform.value.getMaxScaleOnAxis(), zoom);
    final reset = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Reset',
    );
    await tester.tap(reset);
    await tester.pump();
    expect(transform.value, Matrix4.identity());
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
