import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/api/core_api.dart' show ConnectionsChanged;
import 'package:fl_clash/core/api/dto.dart';
import 'package:fl_clash/core/state_sync.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/models/network_diagnostics.dart';
import 'package:fl_clash/models/traffic_history.dart';
import 'package:fl_clash/providers/network_diagnostics.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:fl_clash/providers/traffic_history.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/exit_ip.dart';
import 'package:fl_clash/views/network_diagnostics.dart';
import 'package:fl_clash/views/observed_dns.dart';
import 'package:fl_clash/views/traffic_statistics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/core_mocks.dart';
import '../helpers/test_app.dart';

const _longIpv6 = '2001:0db8:1234:5678:9abc:def0:1234:5678';
const _organization = 'Example Research and Education Network International';
const _testUrl = 'https://latency.example.test/generate_204';
const _appliedProfile = Profile(
  id: 101,
  label: 'Fixture profile',
  autoUpdateDuration: Duration(days: 1),
);
const _liveRoute = RouteState(
  coreEpoch: 1,
  routeVersion: 3,
  hostEpoch: 1,
  proxied: true,
  synced: true,
  live: true,
);
final _clock = DateTime(2026, 11, 27, 12, 30);
const _group = Group(
  name: 'Fixture selector',
  type: GroupType.Selector,
  hidden: false,
  now: 'Fixture node',
  testUrl: _testUrl,
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

  void move() => state = state.copyWith(routeVersion: state.routeVersion + 1);

  void replace(RouteState route) => state = route;
}

class _FixtureDiagnostics extends NetworkDiagnostics {
  _FixtureDiagnostics(this.initial);

  final RoutedProbeState<DiagnosticFamily, DiagnosticExit> initial;
  var refreshes = 0;

  @override
  RoutedProbeState<DiagnosticFamily, DiagnosticExit> build() => initial;

  @override
  void watch(DiagnosticFamily target) {}

  @override
  void unwatch(DiagnosticFamily target) {}

  @override
  void refresh(Iterable<DiagnosticFamily> targets) => refreshes++;
}

RoutedProbeState<DiagnosticFamily, DiagnosticExit> _exits() =>
    RoutedProbeState({
      for (final family in DiagnosticFamily.values)
        family: ProbeEntry(
          phase: ProbePhase.fresh,
          stamp: RouteStamp(
            coreEpoch: _liveRoute.coreEpoch,
            routeVersion: _liveRoute.routeVersion,
            hostEpoch: _liveRoute.hostEpoch,
            proxied: _liveRoute.proxied,
          ),
          value: DiagnosticExit(
            family: family,
            address: family == DiagnosticFamily.ipv4 ? '192.0.2.42' : _longIpv6,
            country: 'United Kingdom',
            region: 'Greater London',
            asn: 'AS64496',
            organization: _organization,
            source: family == DiagnosticFamily.ipv4
                ? 'https://v4.example.test/ip'
                : 'https://v6.example.test/ip',
            geoSource: 'https://metadata.example.test/lookup',
            checkedAt: _clock,
            chains: const ['Fixture node', 'Fixture selector'],
          ),
        ),
    });

DnsQuery _query({bool cached = false}) => DnsQuery(
  id: 7,
  domain: 'fixture.example.test',
  type: 'AAAA',
  upstream:
      'https://user:password@dns.example.test/dns-query?token=hidden#DIRECT',
  cached: cached,
  answers: const [_longIpv6],
  delay: 12,
  time: _clock,
);

enum _DiagnosticsPage { exit, dns, delay, traffic }

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<({ProviderContainer container, GlobalKey shot})> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  Brightness brightness = Brightness.light,
  bool live = false,
  bool populated = false,
  _DiagnosticsPage page = _DiagnosticsPage.exit,
  List<DnsQuery> queries = const [],
  TrafficHistoryStore? traffic,
  CoreMocks? core,
  Profile selected = _appliedProfile,
  List<Profile> profiles = const [_appliedProfile],
  CoreStateSync? sync,
  List<Group> groups = const [_group],
  bool includeNavigatorKey = true,
}) async {
  _size(tester, size);
  final routes = _FixtureRoutes(live ? _liveRoute : const RouteState());
  final diagnostics = _FixtureDiagnostics(
    populated ? _exits() : const RoutedProbeState(),
  );
  final container = ProviderContainer(
    overrides: [
      routeTrackerProvider.overrideWith(() => routes),
      networkDiagnosticsProvider.overrideWith(() => diagnostics),
      currentProfileProvider.overrideWithValue(selected),
      profilesProvider.overrideWithValue(profiles),
      coreStateSyncProvider.overrideWithValue(
        sync ?? (CoreStateSync()..applyEnded(_appliedProfile.id)),
      ),
      groupsProvider.overrideWithBuild((_, _) => groups),
      dnsQueriesProvider.overrideWithValue(FixedList(10, list: queries)),
      appVisibleProvider.overrideWithBuild((_, _) => true),
      if (traffic != null) trafficHistoryProvider.overrideWithValue(traffic),
      if (core != null) coreHandlerProvider.overrideWithValue(core.controller),
    ],
  );
  globalState.container = container;
  container.read(viewSizeProvider.notifier).update((_) => size);
  final shot = GlobalKey();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(
        key: shot,
        child: TestApp(
          includeNavigatorKey: includeNavigatorKey,
          locale: const Locale('en'),
          theme: ThemeData(
            brightness: brightness,
            platform: size.width < 680
                ? TargetPlatform.android
                : TargetPlatform.linux,
            fontFamily: 'DiagnosticsFixture',
          ),
          themeMode: ThemeMode.light,
          child: switch (page) {
            _DiagnosticsPage.exit => const ExitIpView(),
            _DiagnosticsPage.dns => const ObservedDnsView(),
            _DiagnosticsPage.delay => const NodeDelayTestView(),
            _DiagnosticsPage.traffic => const TrafficStatisticsView(),
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
  return (container: container, shot: shot);
}

Finder _button(String key) => find.byKey(ValueKey(key));

Future<TrafficHistoryStore> _traffic(WidgetTester tester) async {
  final result = (await tester.runAsync(() async {
    final dir = await Directory.systemTemp.createTemp('diagnostics-fixture-');
    var now = _clock;
    final store = TrafficHistoryStore(
      directory: () async => dir,
      now: () => now,
    );
    await store.setRecording(true);
    store.recordSample(
      const TrafficSample(up: 0, down: 0, totalUp: 0, totalDown: 0),
      onlyProxy: false,
    );
    now = now.add(const Duration(seconds: 5));
    store.recordSample(
      const TrafficSample(up: 0, down: 0, totalUp: 1048576, totalDown: 7340032),
      onlyProxy: false,
    );
    store.recordConnections(
      ConnectionsChanged(
        ConnectionDelta(
          opened: [
            for (final (id, process, domain, down) in [
              (1, 'Browser', 'video.example.test', 5242880),
              (2, 'Chat', 'chat.example.test', 1048576),
            ])
              ConnectionInfo(
                id: id,
                start: id,
                network: 'tcp',
                sourceIp: '127.0.0.1',
                sourcePort: 10000 + id,
                destinationPort: 443,
                host: domain,
                process: process,
                inboundType: 'mixed',
                chains: const ['Fixture node'],
                rule: 'DOMAIN',
                upload: 524288,
                download: down,
              ),
          ],
        ),
      ),
      profile: 'Fixture profile',
    );
    await store.flush();
    return (store: store, dir: dir);
  }))!;
  addTearDown(() async {
    await tester.runAsync(() async {
      await result.store.flush();
      result.store.dispose();
      await result.dir.delete(recursive: true);
    });
  });
  return result.store;
}

Future<void> _export(WidgetTester tester, GlobalKey key, String name) async {
  final output = Platform.environment['FLOWCAT_DIAGNOSTICS_SCREENSHOT_DIR'];
  if (output == null || output.isEmpty) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final directory = await Directory(output).create(recursive: true);
      await File('${directory.path}/$name.png').writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('en');
    final fontPath = Platform.environment['FLOWCAT_DIAGNOSTICS_FONT_PATH'];
    final data = fontPath == null || fontPath.isEmpty
        ? rootBundle.load('assets/fonts/JetBrainsMono-Regular.ttf')
        : File(
            fontPath,
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes));
    final font = FontLoader('DiagnosticsFixture')..addFont(data);
    await font.load();
  });

  testWidgets('offline exit stays idle', (tester) async {
    final app = await _pump(tester);
    expect(find.text('Ready to check'), findsNWidgets(2));
    expect(
      find.text('Start the connection to inspect its route'),
      findsOneWidget,
    );
    expect(
      tester.widget<TonalButton>(_button('diagnostics-run')).onPressed,
      isNull,
    );
    expect(find.byType(ActivityIndicator), findsNothing);
    await tester.tap(_button('diagnostics-run'));
    await tester.pump();
    final diagnostics =
        app.container.read(networkDiagnosticsProvider.notifier)
            as _FixtureDiagnostics;
    expect(diagnostics.refreshes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('observed DNS redacts credentials and never claims leak safety', (
    tester,
  ) async {
    await _pump(tester, page: _DiagnosticsPage.dns, queries: [_query()]);
    expect(find.text('fixture.example.test'), findsOneWidget);
    expect(
      find.text('AAAA · https://dns.example.test/dns-query'),
      findsOneWidget,
    );
    expect(find.text('12 ms'), findsOneWidget);
    expect(find.text('Not externally verified'), findsOneWidget);
    expect(find.textContaining('password'), findsNothing);
    expect(find.textContaining('token=hidden'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final (device, size) in [
    ('phone', const Size(390, 844)),
    ('desktop', const Size(1280, 900)),
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        '$device ${brightness.name} injected exit and traffic fixtures',
        (tester) async {
          final store = await _traffic(tester);
          final app = await _pump(
            tester,
            size: size,
            brightness: brightness,
            live: true,
            populated: true,
          );
          final ipv4 = _button('diagnostics-exit-ipv4');
          final ipv6 = _button('diagnostics-exit-ipv6');
          final first = tester.getRect(ipv4);
          final second = tester.getRect(ipv6);
          if (device == 'phone') {
            expect(second.top, greaterThanOrEqualTo(first.bottom));
            expect(second.left, closeTo(first.left, .01));
          } else {
            expect(second.top, closeTo(first.top, .01));
            expect(second.left, greaterThan(first.right));
          }
          expect(
            find.byWidgetPredicate(
              (widget) => widget is SelectableText && widget.data == _longIpv6,
            ),
            findsOneWidget,
          );
          expect(find.text(_organization), findsNWidgets(2));
          expect(
            find.text('United Kingdom · Greater London'),
            findsNWidgets(2),
          );
          expect(find.text('AS64496 · 12:30'), findsNWidgets(2));
          expect(tester.takeException(), isNull);
          await _export(
            tester,
            app.shot,
            'diagnostics-$device-${brightness.name}-exit-injected-fixture',
          );

          final trafficApp = await _pump(
            tester,
            size: size,
            brightness: brightness,
            page: _DiagnosticsPage.traffic,
            traffic: store,
            includeNavigatorKey: false,
          );
          expect(find.byType(TrafficStatisticsView), findsOneWidget);
          expect(
            find.byKey(const ValueKey('diagnostics-exit-ipv4')),
            findsNothing,
          );
          expect(store.snapshot(TrafficHistoryPeriod.day).total, 8388608);
          expect(tester.takeException(), isNull);
          await _export(
            tester,
            trafficApp.shot,
            'diagnostics-$device-${brightness.name}-traffic-injected-fixture',
          );
        },
      );
    }
  }

  testWidgets(
    'sample rankings switch dimensions and clear cancellation preserves data',
    (tester) async {
      final store = await _traffic(tester);
      await _pump(
        tester,
        size: const Size(1280, 1200),
        page: _DiagnosticsPage.traffic,
        traffic: store,
      );
      final browser = _button('diagnostics-rank-application-Browser');
      final chat = _button('diagnostics-rank-application-Chat');
      await tester.ensureVisible(browser);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.getTopLeft(browser).dy,
        lessThan(tester.getTopLeft(chat).dy),
      );
      final primary = tester.element(browser).colorScheme.primary;
      Finder fill(Finder row) => find.descendant(
        of: row,
        matching: find.byWidgetPredicate(
          (widget) => widget is ColoredBox && widget.color == primary,
        ),
      );
      final browserBar = tester.getSize(fill(browser));
      final chatBar = tester.getSize(fill(chat));
      expect(browserBar.height, closeTo(4, .01));
      expect(chatBar.height, closeTo(4, .01));
      expect(chatBar.width, greaterThan(0));
      expect(browserBar.width / chatBar.width, closeTo(11 / 3, .01));
      await tester.tap(find.text('Domain'));
      await tester.pump();
      expect(
        _button('diagnostics-rank-domain-video.example.test'),
        findsOneWidget,
      );
      expect(_button('diagnostics-rank-application-Browser'), findsNothing);
      await tester.tap(find.text('Profile'));
      await tester.pump();
      expect(
        _button('diagnostics-rank-profile-Fixture profile'),
        findsOneWidget,
      );
      for (final period in ['Week', 'Month', 'Day']) {
        await tester.ensureVisible(find.text(period));
        await tester.tap(find.text(period));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
      }
      final clear = find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Clear history',
      );
      await tester.ensureVisible(clear);
      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Delete all recorded traffic, rankings, and runtime from this device?',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.snapshot(TrafficHistoryPeriod.day).total, 8388608);
      expect(
        store
            .snapshot(TrafficHistoryPeriod.day)
            .ranks('application')
            .map((rank) => rank.name),
        ['Browser', 'Chat'],
      );
      expect(store.recording, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'fresh delay calls Core without selecting and rejects an old route completion',
    (tester) async {
      final core = coreMocks();
      final first = Completer<DelayResult>();
      final stale = Completer<DelayResult>();
      var calls = 0;
      when(
        () => core.api.testDelay(
          'Fixture selector',
          url: _testUrl,
          timeout: 5000,
        ),
      ).thenAnswer((_) => ++calls == 1 ? first.future : stale.future);
      final app = await _pump(
        tester,
        size: const Size(1280, 1000),
        live: true,
        core: core,
        page: _DiagnosticsPage.delay,
      );
      final run = _button('diagnostics-delay-run');
      await tester.tap(run);
      await tester.pump();
      expect(tester.widget<TonalButton>(run).onPressed, isNull);
      first.complete(
        const DelayResult(name: 'Fixture selector', url: _testUrl, value: 47),
      );
      await tester.pump();
      expect(find.text('47 ms'), findsOneWidget);
      expect(find.text(_testUrl), findsOneWidget);
      expect(tester.widget<TonalButton>(run).onPressed, isNotNull);
      await tester.tap(run);
      await tester.pump();
      expect(find.text('47 ms'), findsNothing);
      (app.container.read(routeTrackerProvider.notifier) as _FixtureRoutes)
          .move();
      await tester.pump();
      stale.complete(
        const DelayResult(name: 'Fixture selector', url: _testUrl, value: 999),
      );
      await tester.pump();
      expect(find.text('999 ms'), findsNothing);
      expect(find.text(_testUrl), findsNothing);
      expect(tester.widget<TonalButton>(run).onPressed, isNotNull);
      verify(
        () => core.api.testDelay(
          'Fixture selector',
          url: _testUrl,
          timeout: 5000,
        ),
      ).called(2);
      verifyNoMoreInteractions(core.api);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('runtime heading reports applied A instead of selected B', (
    tester,
  ) async {
    const applied = Profile(
      id: 201,
      label: 'Applied A',
      autoUpdateDuration: Duration(days: 1),
    );
    const selected = Profile(
      id: 202,
      label: 'Selected B',
      autoUpdateDuration: Duration(days: 1),
    );
    final sync = CoreStateSync()..applyEnded(applied.id);
    final app = await _pump(
      tester,
      live: true,
      selected: selected,
      profiles: const [applied, selected],
      sync: sync,
    );
    expect(find.text('Applied A'), findsOneWidget);
    expect(find.text('Selected B'), findsNothing);
    final routes =
        app.container.read(routeTrackerProvider.notifier) as _FixtureRoutes;
    routes.replace(_liveRoute.copyWith(synced: false));
    await tester.pump();
    expect(find.text('Applied A'), findsNothing);
    expect(find.text('Selected B'), findsNothing);
    sync.applyStarted();
    routes.replace(_liveRoute.copyWith(routeVersion: 4));
    await tester.pump();
    expect(find.text('Applied A'), findsNothing);
    expect(find.text('Selected B'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'same delay tuple survives metadata refresh but empty groups clear it',
    (tester) async {
      final core = coreMocks();
      when(
        () => core.api.testDelay(
          'Fixture selector',
          url: _testUrl,
          timeout: 5000,
        ),
      ).thenAnswer(
        (_) async => const DelayResult(
          name: 'Fixture selector',
          url: _testUrl,
          value: 47,
        ),
      );
      final app = await _pump(
        tester,
        size: const Size(1280, 1000),
        live: true,
        core: core,
        page: _DiagnosticsPage.delay,
      );
      final run = _button('diagnostics-delay-run');
      await tester.tap(run);
      await tester.pump();
      expect(find.text('47 ms'), findsOneWidget);
      final groups = app.container.read(groupsProvider.notifier);
      groups.value = [_group.copyWith(icon: 'refreshed-fixture')];
      await tester.pump();
      expect(find.text('47 ms'), findsOneWidget);
      expect(find.text(_testUrl), findsOneWidget);
      groups.value = const [];
      await tester.pump();
      expect(find.text('47 ms'), findsNothing);
      expect(find.text(_testUrl), findsNothing);
      expect(tester.widget<TonalButton>(run).onPressed, isNull);
      verify(
        () => core.api.testDelay(
          'Fixture selector',
          url: _testUrl,
          timeout: 5000,
        ),
      ).called(1);
      verifyNoMoreInteractions(core.api);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (change, replacement) in [
    (
      'group fallback',
      const Group(
        name: 'Replacement selector',
        type: GroupType.Selector,
        now: 'Replacement node',
        testUrl: _testUrl,
        all: [Proxy(name: 'Replacement node', type: 'Direct')],
      ),
    ),
    (
      'URL change',
      _group.copyWith(testUrl: 'https://replacement.example.test/generate_204'),
    ),
  ]) {
    testWidgets('inflight delay rejects $change and preserves its new result', (
      tester,
    ) async {
      final core = coreMocks();
      final stale = Completer<DelayResult>();
      when(
        () => core.api.testDelay(
          'Fixture selector',
          url: _testUrl,
          timeout: 5000,
        ),
      ).thenAnswer((_) => stale.future);
      when(
        () => core.api.testDelay(
          replacement.name,
          url: replacement.testUrl!,
          timeout: 5000,
        ),
      ).thenAnswer(
        (_) async => DelayResult(
          name: replacement.name,
          url: replacement.testUrl!,
          value: 61,
        ),
      );
      final app = await _pump(
        tester,
        size: const Size(1280, 1000),
        live: true,
        core: core,
        page: _DiagnosticsPage.delay,
      );
      final run = _button('diagnostics-delay-run');
      await tester.tap(run);
      await tester.pump();
      expect(tester.widget<TonalButton>(run).onPressed, isNull);
      app.container.read(groupsProvider.notifier).value = [replacement];
      await tester.pump();
      expect(tester.widget<TonalButton>(run).onPressed, isNotNull);
      await tester.tap(run);
      await tester.pump();
      expect(find.text('61 ms'), findsOneWidget);
      stale.complete(
        const DelayResult(name: 'Fixture selector', url: _testUrl, value: 999),
      );
      await tester.pump();
      expect(find.text('999 ms'), findsNothing);
      expect(find.text('61 ms'), findsOneWidget);
      expect(find.text(replacement.testUrl!), findsOneWidget);
      expect(tester.widget<TonalButton>(run).onPressed, isNotNull);
      verify(
        () => core.api.testDelay(
          'Fixture selector',
          url: _testUrl,
          timeout: 5000,
        ),
      ).called(1);
      verify(
        () => core.api.testDelay(
          replacement.name,
          url: replacement.testUrl!,
          timeout: 5000,
        ),
      ).called(1);
      verifyNoMoreInteractions(core.api);
      expect(tester.takeException(), isNull);
    });
  }

  for (final offline in [false, true]) {
    testWidgets(
      'retained successful probe hides its chain after ${offline ? 'disconnect' : 'route movement'}',
      (tester) async {
        final app = await _pump(
          tester,
          size: const Size(1280, 1000),
          live: true,
          populated: true,
          page: _DiagnosticsPage.delay,
        );
        const chain = 'Fixture selector → Fixture node';
        expect(find.text(chain), findsNWidgets(2));
        final routes =
            app.container.read(routeTrackerProvider.notifier) as _FixtureRoutes;
        if (offline) {
          routes.replace(_liveRoute.copyWith(live: false));
        } else {
          routes.move();
        }
        await tester.pump();
        expect(find.text(chain), findsNothing);
        final retained = app.container.read(networkDiagnosticsProvider);
        for (final family in DiagnosticFamily.values) {
          final entry = retained.entryOf(family);
          expect(entry.phase, ProbePhase.fresh);
          expect(entry.value?.isSuccess, isTrue);
          expect(entry.value?.chains, ['Fixture node', 'Fixture selector']);
          expect(entry.stamp?.routeVersion, _liveRoute.routeVersion);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'delay sends full credential URL to Core and only displays its endpoint',
    (tester) async {
      const url =
          'https://user:password@check.example.test/generate_204?token=secret#tag';
      final core = coreMocks();
      when(
        () => core.api.testDelay('Fixture selector', url: url, timeout: 5000),
      ).thenAnswer(
        (_) async =>
            const DelayResult(name: 'Fixture selector', url: url, value: 47),
      );
      await _pump(
        tester,
        size: const Size(1280, 1000),
        live: true,
        core: core,
        page: _DiagnosticsPage.delay,
        groups: [_group.copyWith(testUrl: url)],
      );
      await tester.tap(_button('diagnostics-delay-run'));
      await tester.pump();
      expect(find.text('47 ms'), findsOneWidget);
      expect(
        find.text('https://check.example.test/generate_204'),
        findsOneWidget,
      );
      for (final secret in ['user:', 'password', 'token=', 'secret', '#tag']) {
        expect(find.textContaining(secret), findsNothing);
      }
      verify(
        () => core.api.testDelay('Fixture selector', url: url, timeout: 5000),
      ).called(1);
      verifyNoMoreInteractions(core.api);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'delay errors release the action and timeout never renders as zero',
    (tester) async {
      final core = coreMocks();
      var calls = 0;
      when(
        () => core.api.testDelay(
          'Fixture selector',
          url: _testUrl,
          timeout: 5000,
        ),
      ).thenAnswer((_) async {
        if (++calls == 1) throw StateError('injected unavailable Core');
        return const DelayResult(
          name: 'Fixture selector',
          url: _testUrl,
          value: -1,
        );
      });
      await _pump(
        tester,
        size: const Size(1280, 1000),
        live: true,
        core: core,
        page: _DiagnosticsPage.delay,
      );
      final run = _button('diagnostics-delay-run');
      await tester.tap(run);
      await tester.pump();
      expect(find.text('Request failed'), findsOneWidget);
      expect(tester.widget<TonalButton>(run).onPressed, isNotNull);
      await tester.tap(run);
      await tester.pump();
      expect(find.text('Timeout'), findsOneWidget);
      expect(find.text('0 ms'), findsNothing);
      expect(find.text('-1 ms'), findsNothing);
      expect(tester.widget<TonalButton>(run).onPressed, isNotNull);
      expect(find.byType(ActivityIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
