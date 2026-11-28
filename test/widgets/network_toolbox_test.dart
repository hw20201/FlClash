import 'dart:io';

import 'package:fl_clash/core/state_sync.dart';
import 'package:fl_clash/models/network_diagnostics.dart';
import 'package:fl_clash/providers/network_diagnostics.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:fl_clash/providers/traffic_history.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/network_diagnostics.dart';
import 'package:fl_clash/views/network_toolbox.dart';
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

class _FixtureRoutes extends RouteTracker {
  _FixtureRoutes(this.initial);

  final RouteState initial;

  @override
  RouteState build() => initial;

  @override
  void attach() {}

  @override
  void detach() {}
}

class _FixtureVisibility extends AppVisible {
  @override
  bool build() => true;
}

class _FixtureDiagnostics extends NetworkDiagnostics {
  var watches = 0;
  var refreshes = 0;

  @override
  RoutedProbeState<DiagnosticFamily, DiagnosticExit> build() =>
      const RoutedProbeState();

  @override
  void watch(DiagnosticFamily target) => watches++;

  @override
  void unwatch(DiagnosticFamily target) {}

  @override
  void refresh(Iterable<DiagnosticFamily> targets) => refreshes++;
}

typedef _ToolboxFixture = ({
  ProviderContainer container,
  GlobalKey<NavigatorState> innerNavigator,
  _FixtureDiagnostics diagnostics,
  ModalRoute<dynamic>? Function() rootRoute,
});

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<_ToolboxFixture> _pumpToolbox(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  TrafficHistoryStore? traffic,
}) async {
  _size(tester, size);
  final routes = _FixtureRoutes(_liveRoute);
  final diagnostics = _FixtureDiagnostics();
  final innerNavigator = GlobalKey<NavigatorState>();
  ModalRoute<dynamic>? root;
  final container = ProviderContainer(
    overrides: [
      routeTrackerProvider.overrideWith(() => routes),
      appVisibleProvider.overrideWith(() => _FixtureVisibility()),
      coreStateSyncProvider.overrideWithValue(CoreStateSync()),
      networkDiagnosticsProvider.overrideWith(() => diagnostics),
      if (traffic != null) trafficHistoryProvider.overrideWithValue(traffic),
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
            return Navigator(
              key: innerNavigator,
              onGenerateRoute: (settings) => PageRouteBuilder<void>(
                settings: settings,
                pageBuilder: (_, _, _) => child,
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

  testWidgets('toolbox cards push within the current nested navigator', (
    tester,
  ) async {
    final fixture = await _pumpToolbox(tester);
    final rootRoute = fixture.rootRoute();
    final inner = fixture.innerNavigator.currentState!;
    expect(rootRoute?.isCurrent, isTrue);
    expect(inner.canPop(), isFalse);

    await tester.tap(find.byKey(const ValueKey('toolbox-dns-lookup')));
    await tester.pumpAndSettle();

    expect(inner.canPop(), isTrue);
    expect(rootRoute?.isCurrent, isTrue);
    expect(find.byKey(const ValueKey('dns-lookup-list')), findsOneWidget);
    expect(fixture.diagnostics.watches, 0);
    expect(fixture.diagnostics.refreshes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('traffic card opens the traffic tab without exit probes', (
    tester,
  ) async {
    final temporaryDirectory = await tester.runAsync(
      () => Directory.systemTemp.createTemp('flowcat-toolbox-traffic-'),
    );
    expect(temporaryDirectory, isNotNull);
    final store = (await tester.runAsync(() async {
      final store = TrafficHistoryStore(
        directory: () async => temporaryDirectory!,
      );
      await store.refresh();
      return store;
    }))!;
    addTearDown(() async {
      await tester.runAsync(() async {
        await store.flush();
        store.dispose();
        await temporaryDirectory!.delete(recursive: true);
      });
    });
    final fixture = await _pumpToolbox(tester, traffic: store);

    await tester.tap(find.byKey(const ValueKey('toolbox-traffic')));
    await tester.pumpAndSettle();

    final tabs = tester.widget<ConnectedButtonBar<NetworkDiagnosticTab>>(
      find.byType(ConnectedButtonBar<NetworkDiagnosticTab>),
    );
    expect(tabs.value, NetworkDiagnosticTab.traffic);
    expect(
      find.byKey(const ValueKey('network-diagnostics-list')),
      findsOneWidget,
    );
    expect(find.text('No connection details for this period'), findsOneWidget);
    expect(fixture.diagnostics.watches, 0);
    expect(fixture.diagnostics.refreshes, 0);
    expect(tester.takeException(), isNull);
  });
}
