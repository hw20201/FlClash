import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/api/core_api.dart' show ConnectionsChanged;
import 'package:fl_clash/core/api/dto.dart';
import 'package:fl_clash/core/state_sync.dart';
import 'package:fl_clash/enum/enum.dart' show GroupType;
import 'package:fl_clash/features/dns_lookup/controller.dart'
    show DnsLookupPhase;
import 'package:fl_clash/models/common.dart' show TrafficShowExt;
import 'package:fl_clash/models/config.dart' show AppSettingProps;
import 'package:fl_clash/models/models.dart' show Group, Profile, Proxy;
import 'package:fl_clash/models/network_diagnostics.dart';
import 'package:fl_clash/models/toolbox_layout.dart';
import 'package:fl_clash/models/traffic_history.dart' show TrafficHistoryPeriod;
import 'package:fl_clash/providers/network_diagnostics.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:fl_clash/providers/traffic_history.dart';
import 'package:fl_clash/providers/toolbox_dns_summary.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/dns_lookup.dart';
import 'package:fl_clash/views/exit_ip.dart';
import 'package:fl_clash/views/network_diagnostics.dart';
import 'package:fl_clash/views/network_toolbox.dart';
import 'package:fl_clash/views/observed_dns.dart';
import 'package:fl_clash/views/traffic_statistics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../helpers/test_app.dart';

const _liveRoute = RouteState(
  coreEpoch: 2,
  routeVersion: 5,
  hostEpoch: 1,
  proxied: true,
  synced: true,
  live: true,
);
const _profile = Profile(
  id: 101,
  label: 'Fixture profile',
  autoUpdateDuration: Duration(days: 1),
);
const _group = Group(
  name: 'Fixture selector',
  type: GroupType.Selector,
  hidden: false,
  now: 'Fixture node',
  testUrl: 'https://latency.example.test/generate_204',
  all: [Proxy(name: 'Fixture node', type: 'Direct')],
);

class _FixtureRoutes extends RouteTracker {
  _FixtureRoutes(this.initial);

  final RouteState initial;

  @override
  RouteState build() => initial;

  @override
  void attach() {}

  @override
  void detach() {}

  void pick() => state = state.copyWith(picks: state.picks + 1);
}

class _FixtureVisibility extends AppVisible {
  @override
  bool build() => true;
}

class _FixtureDiagnostics extends NetworkDiagnostics {
  _FixtureDiagnostics(this.initial);

  final RoutedProbeState<DiagnosticFamily, DiagnosticExit> initial;
  final watches = <DiagnosticFamily>[];
  var refreshes = 0;

  @override
  RoutedProbeState<DiagnosticFamily, DiagnosticExit> build() => initial;

  @override
  void watch(DiagnosticFamily target) => watches.add(target);

  @override
  void unwatch(DiagnosticFamily target) {}

  @override
  void refresh(Iterable<DiagnosticFamily> targets) => refreshes++;
}

RoutedProbeState<DiagnosticFamily, DiagnosticExit> _diagnosticsWithExits() {
  final stamp = RouteStamp(
    coreEpoch: _liveRoute.coreEpoch,
    routeVersion: _liveRoute.routeVersion,
    hostEpoch: _liveRoute.hostEpoch,
    proxied: _liveRoute.proxied,
    picks: _liveRoute.picks,
  );
  return RoutedProbeState({
    for (final family in DiagnosticFamily.values)
      family: ProbeEntry(
        phase: ProbePhase.fresh,
        stamp: stamp,
        value: DiagnosticExit(
          family: family,
          address: family == DiagnosticFamily.ipv4
              ? '192.0.2.42'
              : '2001:0db8:1234:5678:9abc:def0:1234:5678',
          source: 'https://ip.example.test',
          checkedAt: DateTime(2026, 11, 28, 12, 30),
        ),
      ),
  });
}

typedef _ToolboxFixture = ({
  ProviderContainer container,
  GlobalKey<NavigatorState> innerNavigator,
  _FixtureDiagnostics diagnostics,
  TrafficHistoryStore traffic,
  void Function() pickRoute,
  ModalRoute<dynamic>? Function() rootRoute,
});

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<TrafficHistoryStore> _trafficStore(
  WidgetTester tester, {
  bool seed = false,
  String? application,
}) async {
  final directory = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('flowcat-toolbox-traffic-'),
  ))!;
  var now = DateTime(2026, 11, 28, 12, 30);
  final store = (await tester.runAsync(() async {
    final store = TrafficHistoryStore(
      directory: () async => directory,
      now: () => now,
    );
    await store.refresh();
    if (seed) {
      await store.setRecording(true);
      store.recordSample(
        const TrafficSample(up: 0, down: 0, totalUp: 0, totalDown: 0),
        onlyProxy: false,
      );
      now = now.add(const Duration(seconds: 5));
      store.recordSample(
        const TrafficSample(
          up: 0,
          down: 0,
          totalUp: 1048576,
          totalDown: 7340032,
        ),
        onlyProxy: false,
      );
      if (application != null) {
        store.recordConnections(
          ConnectionsChanged(
            ConnectionDelta(
              opened: [
                ConnectionInfo(
                  id: 1,
                  start: 1,
                  network: 'tcp',
                  sourceIp: '127.0.0.1',
                  sourcePort: 10001,
                  destinationPort: 443,
                  host: 'fixture.example.test',
                  process: application,
                  inboundType: 'mixed',
                  chains: const ['Fixture node'],
                  rule: 'DOMAIN',
                  upload: 4096,
                  download: 8192,
                ),
              ],
            ),
          ),
          profile: _profile.label,
        );
      }
      await store.flush();
    }
    return store;
  }))!;
  addTearDown(() async {
    await tester.runAsync(() async {
      await store.flush();
      store.dispose();
      await directory.delete(recursive: true);
    });
  });
  return store;
}

Future<_ToolboxFixture> _pumpToolbox(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
  TrafficHistoryStore? traffic,
  AppSettingProps? settings,
  RoutedProbeState<DiagnosticFamily, DiagnosticExit>? diagnosticsState,
}) async {
  _size(tester, size);
  final routes = _FixtureRoutes(_liveRoute);
  final diagnostics = _FixtureDiagnostics(
    diagnosticsState ?? const RoutedProbeState(),
  );
  final innerNavigator = GlobalKey<NavigatorState>();
  final trafficStore = traffic ?? await _trafficStore(tester);
  final initialSettings =
      settings ??
      AppSettingProps(toolboxLayoutJson: ToolboxLayout.defaults().encode());
  ModalRoute<dynamic>? root;
  final container = ProviderContainer(
    overrides: [
      routeTrackerProvider.overrideWith(() => routes),
      appVisibleProvider.overrideWith(() => _FixtureVisibility()),
      appSettingProvider.overrideWithBuild((_, _) => initialSettings),
      currentProfileProvider.overrideWithValue(_profile),
      profilesProvider.overrideWithValue([_profile]),
      groupsProvider.overrideWithBuild((_, _) => const [_group]),
      coreStateSyncProvider.overrideWithValue(
        CoreStateSync()..applyEnded(_profile.id),
      ),
      networkDiagnosticsProvider.overrideWith(() => diagnostics),
      trafficHistoryProvider.overrideWithValue(trafficStore),
    ],
  );
  globalState.container = container;
  container.read(viewSizeProvider.notifier).update((_) => size);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: TestApp(
        locale: const Locale('en'),
        theme: ThemeData(
          platform: size.width < 680
              ? TargetPlatform.android
              : TargetPlatform.linux,
          fontFamily: 'ToolboxFixture',
        ),
        themeMode: ThemeMode.light,
        homeBuilder: (child) => Builder(
          builder: (context) {
            root = ModalRoute.of(context);
            return MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(textScale),
              ),
              child: Navigator(
                key: innerNavigator,
                onGenerateRoute: (settings) => PageRouteBuilder<void>(
                  settings: settings,
                  pageBuilder: (_, _, _) => child,
                ),
              ),
            );
          },
        ),
        child: const NetworkToolboxView(),
      ),
    ),
  );
  await tester.pump();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
  return (
    container: container,
    innerNavigator: innerNavigator,
    diagnostics: diagnostics,
    traffic: trafficStore,
    pickRoute: routes.pick,
    rootRoute: () => root,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('en');
    final fontPath = Platform.environment['FLOWCAT_DIAGNOSTICS_FONT_PATH'];
    final fontData = fontPath == null || fontPath.isEmpty
        ? rootBundle.load('assets/fonts/JetBrainsMono-Regular.ttf')
        : File(
            fontPath,
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes));
    final font = FontLoader('ToolboxFixture')..addFont(fontData);
    await font.load();
  });

  testWidgets('shows the three cards and separate additional checks', (
    tester,
  ) async {
    final fixture = await _pumpToolbox(tester);

    for (final (key, title) in [
      ('toolbox-exit-ip', 'Exit IP'),
      ('toolbox-dns-lookup', 'DNS lookup'),
      ('toolbox-traffic', 'Traffic statistics'),
      ('toolbox-node-delay', 'Node delay test'),
      ('toolbox-observed-dns', 'Observed DNS'),
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
      expect(find.text(title), findsOneWidget);
    }
    expect(fixture.diagnostics.watches, isEmpty);
    expect(fixture.diagnostics.refreshes, 0);
    expect(tester.takeException(), isNull);
  });

  for (final destination in [
    (
      key: 'toolbox-exit-ip',
      title: 'Exit IP',
      page: ExitIpView,
      listKey: 'network-diagnostics-list',
    ),
    (
      key: 'toolbox-dns-lookup',
      title: 'DNS lookup',
      page: DnsLookupView,
      listKey: 'dns-lookup-list',
    ),
    (
      key: 'toolbox-traffic',
      title: 'Traffic statistics',
      page: TrafficStatisticsView,
      listKey: 'traffic-statistics-list',
    ),
    (
      key: 'toolbox-node-delay',
      title: 'Node delay test',
      page: NodeDelayTestView,
      listKey: 'network-diagnostics-list',
    ),
    (
      key: 'toolbox-observed-dns',
      title: 'Observed DNS',
      page: ObservedDnsView,
      listKey: 'observed-dns-list',
    ),
  ]) {
    testWidgets('${destination.title} opens in the nested navigator', (
      tester,
    ) async {
      final traffic = await _trafficStore(
        tester,
        seed: destination.page == TrafficStatisticsView,
      );
      final fixture = await _pumpToolbox(tester, traffic: traffic);
      final target = find.byKey(ValueKey(destination.key));
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();

      expect(find.byType(destination.page), findsOneWidget);
      expect(find.byKey(ValueKey(destination.listKey)), findsOneWidget);
      expect(fixture.innerNavigator.currentState!.canPop(), isTrue);
      expect(fixture.rootRoute()?.isCurrent, isTrue);
      if (destination.page == ExitIpView) {
        expect(fixture.diagnostics.watches, DiagnosticFamily.values);
      } else {
        expect(fixture.diagnostics.watches, isEmpty);
      }
      expect(fixture.diagnostics.refreshes, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('traffic summary and destination read the supplied store', (
    tester,
  ) async {
    final traffic = await _trafficStore(tester, seed: true);
    final fixture = await _pumpToolbox(tester, traffic: traffic);
    final total = traffic.snapshot(TrafficHistoryPeriod.day).total.traffic.show;

    expect(fixture.container.read(trafficHistoryProvider), same(traffic));
    expect(find.text(total), findsOneWidget);
    expect(traffic.recording, isTrue);
    await tester.tap(find.byKey(const ValueKey('toolbox-traffic')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('traffic-statistics-list')),
      findsOneWidget,
    );
    expect(find.text(total), findsWidgets);
    expect(find.text('Record traffic history'), findsOneWidget);
    expect(traffic.recording, isTrue);
    expect(fixture.diagnostics.watches, isEmpty);
    expect(fixture.diagnostics.refreshes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden IPs stay masked until an exit detail page opens', (
    tester,
  ) async {
    final fixture = await _pumpToolbox(
      tester,
      settings: AppSettingProps(
        hideIp: true,
        toolboxLayoutJson: ToolboxLayout.defaults().encode(),
      ),
      diagnosticsState: _diagnosticsWithExits(),
    );

    expect(find.text('*****'), findsNWidgets(2));
    expect(find.text('192.0.2.42'), findsNothing);
    expect(find.text('2001:0db8:1234:5678:9abc:def0:1234:5678'), findsNothing);
    expect(fixture.diagnostics.watches, isEmpty);
    expect(fixture.diagnostics.refreshes, 0);

    await tester.tap(find.byKey(const ValueKey('toolbox-edit-layout')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('toolbox-resize-handle-exitIp')),
    );
    await tester.pumpAndSettle();
    expect(fixture.diagnostics.watches, isEmpty);
    expect(fixture.diagnostics.refreshes, 0);

    await tester.tap(find.byKey(const ValueKey('toolbox-cancel-layout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('toolbox-exit-ip')));
    await tester.pumpAndSettle();
    expect(find.byType(ExitIpView), findsOneWidget);
    expect(fixture.diagnostics.watches, DiagnosticFamily.values);
    expect(fixture.diagnostics.refreshes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('handle drags resize both axes without scrolling or committing', (
    tester,
  ) async {
    final initialJson = ToolboxLayout.defaults().encode();
    final fixture = await _pumpToolbox(
      tester,
      size: const Size(390, 520),
      settings: AppSettingProps(toolboxLayoutJson: initialJson),
    );
    final exitCard = find.byKey(const ValueKey('toolbox-exit-ip'));
    final resizeHandle = find.byKey(
      const ValueKey('toolbox-resize-handle-exitIp'),
    );
    final originalSize = tester.getSize(exitCard);

    await tester.tap(find.byKey(const ValueKey('toolbox-edit-layout')));
    await tester.pump();

    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    scrollable.position.jumpTo(48);
    await tester.pump();
    final initialScrollOffset = scrollable.position.pixels;
    expect(initialScrollOffset, greaterThan(0));
    final writes = <String>[];
    final subscription = fixture.container.listen(
      appSettingProvider,
      (_, next) => writes.add(next.toolboxLayoutJson),
    );
    addTearDown(subscription.close);

    Future<void> dragHandle(Offset delta) async {
      await tester.dragFrom(tester.getCenter(resizeHandle), delta);
      await tester.pumpAndSettle();
      expect(
        fixture.container.read(appSettingProvider).toolboxLayoutJson,
        initialJson,
      );
      expect(writes, isEmpty);
      expect(scrollable.position.pixels, initialScrollOffset);
      expect(find.byType(ExitIpView), findsNothing);
      expect(fixture.diagnostics.watches, isEmpty);
      expect(fixture.diagnostics.refreshes, 0);
    }

    await dragHandle(const Offset(0, 80));
    expect(tester.getSize(exitCard).height, greaterThan(originalSize.height));
    await dragHandle(const Offset(0, -80));
    expect(tester.getSize(exitCard).height, closeTo(originalSize.height, .01));
    await dragHandle(const Offset(80, 0));
    expect(tester.getSize(exitCard).width, greaterThan(originalSize.width));
    await dragHandle(const Offset(-80, 0));
    expect(tester.getSize(exitCard).width, closeTo(originalSize.width, .01));
    await dragHandle(const Offset(80, 0));
    expect(tester.getSize(exitCard).width, greaterThan(originalSize.width));

    await tester.tap(find.byKey(const ValueKey('toolbox-finish-layout')));
    await tester.pumpAndSettle();

    final savedJson = fixture.container
        .read(appSettingProvider)
        .toolboxLayoutJson;
    expect(
      ToolboxLayout.decode(savedJson).sizeOf(ToolboxModuleId.exitIp),
      ToolboxCardSize.wide,
    );
    expect(writes, [savedJson]);
    expect(scrollable.position.pixels, initialScrollOffset);
    expect(find.byType(ExitIpView), findsNothing);
    expect(fixture.diagnostics.watches, isEmpty);
    expect(fixture.diagnostics.refreshes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a local node pick marks cached summaries stale', (tester) async {
    const longDomain = 'cached.example.test';
    final fixture = await _pumpToolbox(
      tester,
      diagnosticsState: _diagnosticsWithExits(),
    );
    final stamp = RouteStamp(
      coreEpoch: _liveRoute.coreEpoch,
      routeVersion: _liveRoute.routeVersion,
      hostEpoch: _liveRoute.hostEpoch,
      proxied: _liveRoute.proxied,
      picks: _liveRoute.picks,
    );
    fixture.container
        .read(toolboxDnsSummaryProvider.notifier)
        .publish(
          ToolboxDnsQuerySummary(
            domain: longDomain,
            type: 'A',
            phase: DnsLookupPhase.complete,
            result: const DnsQueryResult(
              rcode: 0,
              questions: [],
              truncated: false,
              recursionDesired: true,
              recursionAvailable: true,
              authenticData: false,
              checkingDisabled: false,
              answers: [],
              authorities: [],
              additionals: [],
            ),
            checkedAt: DateTime(2026, 11, 28, 12, 30),
            elapsed: const Duration(milliseconds: 12),
            stamp: stamp,
            routeLive: true,
            routeSynced: true,
          ),
        );
    await tester.pump();

    expect(find.text(longDomain), findsOneWidget);
    expect(find.text('192.0.2.42'), findsOneWidget);
    fixture.pickRoute();
    await tester.pump();

    expect(find.text(longDomain), findsOneWidget);
    expect(find.text('192.0.2.42'), findsNothing);
    expect(
      find.text('The route or configuration changed. Run the check again.'),
      findsWidgets,
    );
    expect(fixture.diagnostics.watches, isEmpty);
    expect(fixture.diagnostics.refreshes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('size menu changes draft without losing edit focus', (
    tester,
  ) async {
    final initialJson = ToolboxLayout.defaults().encode();
    final fixture = await _pumpToolbox(
      tester,
      settings: AppSettingProps(toolboxLayoutJson: initialJson),
    );
    final exitCard = find.byKey(const ValueKey('toolbox-exit-ip'));
    final originalSize = tester.getSize(exitCard);

    await tester.tap(find.byKey(const ValueKey('toolbox-edit-layout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('toolbox-size-exitIp')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 × 1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('toolbox-finish-layout')), findsOneWidget);
    expect(tester.getSize(exitCard).width, greaterThan(originalSize.width));
    expect(
      fixture.container.read(appSettingProvider).toolboxLayoutJson,
      initialJson,
    );
    expect(fixture.diagnostics.watches, isEmpty);
    expect(fixture.diagnostics.refreshes, 0);
    await tester.tap(find.byKey(const ValueKey('toolbox-cancel-layout')));
    await tester.pumpAndSettle();
    expect(
      fixture.container.read(appSettingProvider).toolboxLayoutJson,
      initialJson,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing changes only the draft and cancel restores the grid', (
    tester,
  ) async {
    final initialJson = ToolboxLayout.defaults().encode();
    final fixture = await _pumpToolbox(
      tester,
      settings: AppSettingProps(toolboxLayoutJson: initialJson),
    );
    final exitCard = find.byKey(const ValueKey('toolbox-exit-ip'));
    final originalSize = tester.getSize(exitCard);

    await tester.tap(find.byKey(const ValueKey('toolbox-edit-layout')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('toolbox-resize-handle-exitIp')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('toolbox-resize-handle-exitIp')),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(exitCard).width, greaterThan(originalSize.width));
    expect(
      fixture.container.read(appSettingProvider).toolboxLayoutJson,
      initialJson,
    );
    expect(fixture.diagnostics.watches, isEmpty);
    expect(fixture.diagnostics.refreshes, 0);
    await tester.tap(exitCard);
    await tester.pump();
    expect(find.byType(ExitIpView), findsNothing);

    await tester.tap(find.byKey(const ValueKey('toolbox-reset-layout')));
    await tester.pumpAndSettle();
    expect(tester.getSize(exitCard).width, closeTo(originalSize.width, .01));
    expect(
      fixture.container.read(appSettingProvider).toolboxLayoutJson,
      initialJson,
    );
    await tester.tap(
      find.byKey(const ValueKey('toolbox-resize-handle-exitIp')),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(exitCard).width, greaterThan(originalSize.width));

    await tester.tap(find.byKey(const ValueKey('toolbox-cancel-layout')));
    await tester.pumpAndSettle();

    expect(
      fixture.container.read(appSettingProvider).toolboxLayoutJson,
      initialJson,
    );
    expect(tester.getSize(exitCard).width, closeTo(originalSize.width, .01));
    expect(find.byKey(const ValueKey('toolbox-edit-layout')), findsOneWidget);
    expect(fixture.diagnostics.watches, isEmpty);
    expect(fixture.diagnostics.refreshes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('finish writes one valid layout JSON and makes no probes', (
    tester,
  ) async {
    final initialJson = ToolboxLayout.defaults().encode();
    final fixture = await _pumpToolbox(
      tester,
      settings: AppSettingProps(toolboxLayoutJson: initialJson),
    );
    final writes = <String>[];
    final subscription = fixture.container.listen(
      appSettingProvider,
      (_, next) => writes.add(next.toolboxLayoutJson),
    );
    addTearDown(subscription.close);

    await tester.tap(find.byKey(const ValueKey('toolbox-edit-layout')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('toolbox-resize-handle-exitIp')),
    );
    await tester.pumpAndSettle();
    expect(
      fixture.container.read(appSettingProvider).toolboxLayoutJson,
      initialJson,
    );

    await tester.tap(find.byKey(const ValueKey('toolbox-finish-layout')));
    await tester.pumpAndSettle();

    final savedJson = fixture.container
        .read(appSettingProvider)
        .toolboxLayoutJson;
    final decoded = jsonDecode(savedJson) as Map<String, dynamic>;
    expect(decoded['schemaVersion'], ToolboxLayout.schemaVersion);
    expect(decoded['modules'], isA<Map<String, dynamic>>());
    expect(
      ToolboxLayout.decode(savedJson).sizeOf(ToolboxModuleId.exitIp),
      ToolboxCardSize.wide,
    );
    expect(writes, [savedJson]);
    expect(find.byKey(const ValueKey('toolbox-edit-layout')), findsOneWidget);
    expect(fixture.diagnostics.watches, isEmpty);
    expect(fixture.diagnostics.refreshes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long summaries stay within stable card geometry at large text', (
    tester,
  ) async {
    final longDomain =
        '${List.filled(16, 'long-subdomain').join('-')}.example.test';
    final longApplication = List.filled(10, 'LongApplicationName').join('-');
    final traffic = await _trafficStore(
      tester,
      seed: true,
      application: longApplication,
    );
    final fixture = await _pumpToolbox(
      tester,
      size: const Size(320, 740),
      textScale: 2,
      traffic: traffic,
      settings: AppSettingProps(
        toolboxLayoutJson: ToolboxLayout.fromSizes({
          ToolboxModuleId.trafficStatistics: ToolboxCardSize.large,
        }).encode(),
      ),
    );
    final cardKeys = [
      const ValueKey('toolbox-exit-ip'),
      const ValueKey('toolbox-dns-lookup'),
      const ValueKey('toolbox-traffic'),
    ];
    final originalBounds = [
      for (final key in cardKeys) tester.getRect(find.byKey(key)),
    ];
    final stamp = RouteStamp(
      coreEpoch: _liveRoute.coreEpoch,
      routeVersion: _liveRoute.routeVersion,
      hostEpoch: _liveRoute.hostEpoch,
      proxied: _liveRoute.proxied,
      picks: _liveRoute.picks,
    );
    fixture.container
        .read(toolboxDnsSummaryProvider.notifier)
        .publish(
          ToolboxDnsQuerySummary(
            domain: longDomain,
            type: 'A',
            phase: DnsLookupPhase.complete,
            result: const DnsQueryResult(
              rcode: 0,
              questions: [],
              truncated: false,
              recursionDesired: true,
              recursionAvailable: true,
              authenticData: false,
              checkingDisabled: false,
              answers: [],
              authorities: [],
              additionals: [],
            ),
            checkedAt: DateTime(2026, 11, 28, 12, 30),
            elapsed: const Duration(milliseconds: 12),
            stamp: stamp,
            routeLive: true,
            routeSynced: true,
          ),
        );
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    final contentBottom =
        scrollable.position.viewportDimension +
        scrollable.position.maxScrollExtent;
    final currentBounds = [
      for (final key in cardKeys) tester.getRect(find.byKey(key)),
    ];
    expect(currentBounds, originalBounds);
    expect(find.text(longDomain), findsOneWidget);
    expect(find.text(longApplication), findsOneWidget);
    for (var index = 0; index < currentBounds.length; index++) {
      final bounds = currentBounds[index];
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(320));
      expect(bounds.bottom, lessThanOrEqualTo(contentBottom));
      for (var other = index + 1; other < currentBounds.length; other++) {
        expect(bounds.overlaps(currentBounds[other]), isFalse);
      }
    }
    expect(tester.takeException(), isNull);
  });
}
