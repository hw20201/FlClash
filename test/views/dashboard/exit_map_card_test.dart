import 'package:fl_clash/common/exit_map_geo.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/exit_map.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/widgets/exit_map.dart';
import 'package:fl_clash/widgets/widgets.dart';
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
