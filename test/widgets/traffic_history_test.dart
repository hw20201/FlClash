import 'dart:io';

import 'package:fl_clash/core/api/core_api.dart';
import 'package:fl_clash/core/api/dto.dart';
import 'package:fl_clash/providers/traffic_history.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/ui.dart' show Card;
import 'package:fl_clash/views/traffic_history.dart';
import 'package:fl_clash/widgets/traffic_share_gauge.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('segmented share gauge scales and exposes an empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      const TestApp(
        locale: Locale('en'),
        child: Column(
          children: [
            TrafficShareGauge(
              share: .6,
              size: 92,
              label: 'Proxy',
              showLabel: true,
            ),
            TrafficShareGauge(share: .6, size: 62, label: 'Proxy'),
            TrafficShareGauge(share: .6, size: 40, label: 'Rule'),
            TrafficShareGauge(share: null, size: 62, label: 'Proxy'),
          ],
        ),
      ),
    );
    expect(find.text('60%'), findsNWidgets(3));
    expect(find.text('—'), findsOneWidget);
    expect(find.text('Proxy'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('empty history can opt in without recording old traffic', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('traffic-history-widget-');
    final store = (await tester.runAsync(() async {
      final store = TrafficHistoryStore(directory: () async => dir);
      await store.refresh();
      return store;
    }))!;
    final container = ProviderContainer(
      overrides: [trafficHistoryProvider.overrideWithValue(store)],
    );
    globalState.container = container;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: TrafficHistorySheet()),
      ),
    );
    await tester.pump();
    expect(find.text('No recorded traffic for this period'), findsOneWidget);
    expect(find.text('Record traffic history'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    store.dispose();
    await tester.runAsync(() => dir.delete(recursive: true));
  });

  testWidgets('mobile history switches periods, scrolls and ranks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = Directory.systemTemp.createTempSync('traffic-history-widget-');
    var now = DateTime.now();
    final store = (await tester.runAsync(() async {
      final store = TrafficHistoryStore(
        directory: () async => dir,
        now: () => now,
      );
      await store.setRecording(true);
      return store;
    }))!;
    store.recordSample(
      const TrafficSample(up: 0, down: 0, totalUp: 100, totalDown: 100),
      onlyProxy: false,
    );
    now = now.add(const Duration(seconds: 5));
    store.recordSample(
      const TrafficSample(up: 0, down: 0, totalUp: 500, totalDown: 2000),
      onlyProxy: false,
    );
    store.recordConnections(
      ConnectionsChanged(
        ConnectionDelta(
          opened: [
            for (var id = 1; id <= 3; id++)
              ConnectionInfo(
                id: id,
                start: 1,
                network: 'tcp',
                sourceIp: '127.0.0.1',
                sourcePort: 1000 + id,
                destinationPort: 443,
                host: 'example.test',
                inboundType: 'mixed',
                chains: const [],
                rule: id <= 2 ? 'RuleSet' : 'GeoIP',
                rulePayload: id <= 2 ? 'video' : 'CN',
                upload: 0,
                download: 100,
              ),
          ],
        ),
      ),
    );
    await tester.runAsync(store.flush);
    final container = ProviderContainer(
      overrides: [trafficHistoryProvider.overrideWithValue(store)],
    );
    globalState.container = container;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: TrafficHistorySheet()),
      ),
    );
    await tester.pump();
    expect(find.text('Traffic overview'), findsOneWidget);
    Finder tileOf(String label) => find
        .ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container && widget.decoration is ShapeDecoration,
          ),
        )
        .first;
    final runtimeTile = tileOf('Recorded runtime');
    final splitTile = tileOf('Direct');
    expect(
      tester.widget<Container>(runtimeTile).decoration,
      tester.widget<Container>(splitTile).decoration,
    );
    expect(tester.getSize(runtimeTile), tester.getSize(splitTile));
    final runtimeBounds = tester.getRect(runtimeTile);
    final splitBounds = tester.getRect(splitTile);
    expect(runtimeBounds.top, splitBounds.top);
    expect(runtimeBounds.right, lessThan(splitBounds.left));
    expect(tester.takeException(), isNull);
    final scroll = find.byType(Scrollable).first;
    for (final (rule, share) in [('RuleSet(video)', 1.0), ('GeoIP(CN)', 0.5)]) {
      await tester.scrollUntilVisible(find.text(rule), 200, scrollable: scroll);
      final card = find
          .ancestor(of: find.text(rule), matching: find.byType(Card))
          .first;
      final track = find.descendant(of: card, matching: find.byType(Stack));
      final fill = find.descendant(
        of: track,
        matching: find.byType(DecoratedBox),
      );
      final trackSize = tester.getSize(track);
      final fillSize = tester.getSize(fill);
      expect(fillSize.height, greaterThan(0));
      expect(fillSize.height, trackSize.height);
      expect(fillSize.width, closeTo(trackSize.width * share, 0.01));
    }
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Week'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Month'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    for (var i = 0; i < 4; i++) {
      await tester.drag(scroll, const Offset(0, -350));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Traffic ranking'), findsOneWidget);
    await tester.tap(find.text('Node'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('No connection details for this period'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(store.flush);
    container.dispose();
    store.dispose();
    await tester.runAsync(() => dir.delete(recursive: true));
  });

  testWidgets('dominant chart point never overflows in any period', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = Directory.systemTemp.createTempSync('traffic-history-widget-');
    var now = DateTime(2026, 11, 19, 17);
    final store = (await tester.runAsync(() async {
      final store = TrafficHistoryStore(
        directory: () async => dir,
        now: () => now,
      );
      await store.setRecording(true);
      return store;
    }))!;
    store.recordSample(
      const TrafficSample(up: 0, down: 0, totalUp: 0, totalDown: 0),
      onlyProxy: false,
    );
    now = now.add(const Duration(seconds: 5));
    store.recordSample(
      const TrafficSample(up: 0, down: 0, totalUp: 1000, totalDown: 306700000),
      onlyProxy: false,
    );
    await tester.runAsync(store.flush);
    final container = ProviderContainer(
      overrides: [trafficHistoryProvider.overrideWithValue(store)],
    );
    globalState.container = container;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: TrafficHistorySheet()),
      ),
    );
    await tester.pump();
    expect(find.text('Traffic overview'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Week'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Month'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('11/1'), findsOneWidget);
    expect(find.text('11/19'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(store.flush);
    container.dispose();
    store.dispose();
    await tester.runAsync(() => dir.delete(recursive: true));
  });

  testWidgets('ranking shares use the attributed category total', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = Directory.systemTemp.createTempSync('traffic-history-widget-');
    var now = DateTime(2026, 11, 19, 17);
    final store = (await tester.runAsync(() async {
      final store = TrafficHistoryStore(
        directory: () async => dir,
        now: () => now,
      );
      await store.setRecording(true);
      return store;
    }))!;
    store.recordSample(
      const TrafficSample(up: 0, down: 0, totalUp: 0, totalDown: 0),
      onlyProxy: false,
    );
    now = now.add(const Duration(seconds: 5));
    store.recordSample(
      const TrafficSample(up: 0, down: 0, totalUp: 1000, totalDown: 306700000),
      onlyProxy: false,
    );
    store.recordConnections(
      ConnectionsChanged(
        ConnectionDelta(
          opened: [
            ConnectionInfo(
              id: 1,
              start: 1,
              network: 'tcp',
              sourceIp: '127.0.0.1',
              sourcePort: 1001,
              destinationPort: 443,
              host: 'a.example',
              inboundType: 'mixed',
              chains: const [],
              rule: 'RuleSet',
              rulePayload: 'video',
              upload: 0,
              download: 20000,
            ),
            ConnectionInfo(
              id: 2,
              start: 1,
              network: 'tcp',
              sourceIp: '127.0.0.1',
              sourcePort: 1002,
              destinationPort: 443,
              host: 'b.example',
              inboundType: 'mixed',
              chains: const [],
              rule: 'GeoIP',
              rulePayload: 'CN',
              upload: 0,
              download: 10000,
            ),
          ],
        ),
      ),
    );
    await tester.runAsync(store.flush);
    final container = ProviderContainer(
      overrides: [trafficHistoryProvider.overrideWithValue(store)],
    );
    globalState.container = container;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: TrafficHistorySheet()),
      ),
    );
    await tester.pump();
    final scroll = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('67%'), 200, scrollable: scroll);
    expect(find.text('67%'), findsOneWidget);
    expect(find.text('33%'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(store.flush);
    container.dispose();
    store.dispose();
    await tester.runAsync(() => dir.delete(recursive: true));
  });
}
