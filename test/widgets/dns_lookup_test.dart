import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fl_clash/core/api/cancellation.dart';
import 'package:fl_clash/core/api/dto.dart';
import 'package:fl_clash/core/state_sync.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/dns_lookup.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/core_mocks.dart';
import '../helpers/test_app.dart';

const _liveRoute = RouteState(
  coreEpoch: 4,
  routeVersion: 9,
  hostEpoch: 2,
  proxied: true,
  synced: true,
  live: true,
);
const _longIpv6 = '2001:0db8:1234:5678:9abc:def0:1234:5678';

DnsQueryResult _response({
  int rcode = 0,
  List<DnsRecordDto> answers = const [],
  List<DnsRecordDto> authorities = const [],
  List<DnsRecordDto> additionals = const [],
}) => DnsQueryResult(
  rcode: rcode,
  questions: const [
    DnsQuestionDto(name: 'fixture.example.test.', qtype: 1, qclass: 1),
  ],
  truncated: false,
  recursionDesired: true,
  recursionAvailable: true,
  authenticData: false,
  checkingDisabled: false,
  answers: answers,
  authorities: authorities,
  additionals: additionals,
);

const _fullResponse = DnsQueryResult(
  rcode: 0,
  questions: [
    DnsQuestionDto(name: 'fixture.example.test.', qtype: 1, qclass: 1),
  ],
  truncated: false,
  recursionDesired: true,
  recursionAvailable: true,
  authenticData: false,
  checkingDisabled: false,
  answers: [
    DnsRecordDto(
      name: 'fixture.example.test.',
      rtype: 1,
      ttl: 301,
      data: '192.0.2.10',
    ),
    DnsRecordDto(
      name: 'fixture.example.test.',
      rtype: 28,
      ttl: 302,
      data: _longIpv6,
    ),
    DnsRecordDto(
      name: 'fixture.example.test.',
      rtype: 5,
      ttl: 303,
      data: 'canonical.example.test.',
    ),
  ],
  authorities: [
    DnsRecordDto(
      name: 'example.test.',
      rtype: 6,
      ttl: 900,
      data: 'ns.example.test. hostmaster.example.test. 1 2 3 4 5',
    ),
  ],
  additionals: [
    DnsRecordDto(
      name: 'ns.example.test.',
      rtype: 1,
      ttl: 120,
      data: '192.0.2.53',
    ),
  ],
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

  void replace(RouteState route) => state = route;
}

class _FixtureVisibility extends AppVisible {
  _FixtureVisibility(this.initial);

  final bool initial;

  @override
  bool build() => initial;

  void setVisible(bool visible) => state = visible;
}

typedef _QueryCall = ({
  String name,
  String type,
  Duration? timeout,
  CoreCancellationToken cancellation,
});
typedef _DnsReply = Future<DnsQueryResult> Function(_QueryCall call);
typedef _Fixture = ({
  _FixtureRoutes routes,
  _FixtureVisibility visibility,
  CoreStateSync sync,
  List<_QueryCall> calls,
  GlobalKey shot,
});

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<_Fixture> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  RouteState route = _liveRoute,
  bool visible = true,
  double textScale = 1,
  CoreStateSync? sync,
  _DnsReply? reply,
}) async {
  _size(tester, size);
  final routes = _FixtureRoutes(route);
  final visibility = _FixtureVisibility(visible);
  final core = coreMocks();
  final syncState = sync ?? CoreStateSync();
  final calls = <_QueryCall>[];
  final onReply = reply ?? (_) async => _response();
  when(
    () => core.api.queryDns(
      any(),
      type: any(named: 'type'),
      timeout: const Duration(seconds: 8),
      cancellation: any(named: 'cancellation'),
    ),
  ).thenAnswer((invocation) {
    final call = (
      name: invocation.positionalArguments.single as String,
      type: invocation.namedArguments[#type] as String,
      timeout: invocation.namedArguments[#timeout] as Duration?,
      cancellation:
          invocation.namedArguments[#cancellation] as CoreCancellationToken,
    );
    calls.add(call);
    return onReply(call);
  });
  final container = ProviderContainer(
    overrides: [
      routeTrackerProvider.overrideWith(() => routes),
      appVisibleProvider.overrideWith(() => visibility),
      coreStateSyncProvider.overrideWithValue(syncState),
      coreHandlerProvider.overrideWithValue(core.controller),
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
          locale: const Locale('en'),
          theme: ThemeData(
            platform: size.width < 680
                ? TargetPlatform.android
                : TargetPlatform.linux,
            fontFamily: 'DnsLookupFixture',
          ),
          themeMode: ThemeMode.light,
          homeBuilder: (child) => MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(textScale),
            ),
            child: child,
          ),
          child: const DnsLookupView(),
        ),
      ),
    ),
  );
  await tester.pump();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
  return (
    routes: routes,
    visibility: visibility,
    sync: syncState,
    calls: calls,
    shot: shot,
  );
}

Finder _button(String key) => find.byKey(ValueKey(key));

Finder _nameField() => find.descendant(
  of: _button('dns-lookup-name'),
  matching: find.byType(EditableText),
);

Future<void> _query(WidgetTester tester, String name) async {
  await tester.enterText(_nameField(), name);
  await tester.ensureVisible(_button('dns-lookup-run'));
  await tester.tap(_button('dns-lookup-run'));
  await tester.pump();
  await tester.pump();
}

Future<void> _export(WidgetTester tester, GlobalKey key, String name) async {
  final output = Platform.environment['FLOWCAT_DNS_SCREENSHOT_DIR'];
  if (output == null || output.isEmpty) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = await Directory(output).create(recursive: true);
      await File('${directory.path}/$name.png').writeAsBytes(
        bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    registerFallbackValue(CoreCancellationToken());
    final fontPath = Platform.environment['FLOWCAT_DIAGNOSTICS_FONT_PATH'];
    final fontData = fontPath == null || fontPath.isEmpty
        ? rootBundle.load('assets/fonts/JetBrainsMono-Regular.ttf')
        : File(
            fontPath,
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes));
    final font = FontLoader('DnsLookupFixture')..addFont(fontData);
    await font.load();
  });

  testWidgets('idle and unavailable runtime show distinct guarded states', (
    tester,
  ) async {
    final fixture = await _pump(tester, route: const RouteState());
    expect(find.byKey(const ValueKey('dns-lookup-idle')), findsOneWidget);
    expect(find.text('Start with a domain'), findsOneWidget);
    expect(
      find.text('Apply a profile and wait for the Core to connect.'),
      findsOneWidget,
    );

    await _query(tester, 'unavailable.example.test');

    expect(
      find.byKey(const ValueKey('dns-lookup-unavailable')),
      findsOneWidget,
    );
    expect(fixture.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('apply in progress is not mislabeled as offline', (tester) async {
    final sync = CoreStateSync()..applyStarted();
    final fixture = await _pump(
      tester,
      sync: sync,
      reply: (_) async => _fullResponse,
    );
    expect(
      find.text('Apply a profile and wait for the Core to connect.'),
      findsNothing,
    );

    await _query(tester, 'fixture.example.test');
    expect(fixture.calls, isEmpty);
    expect(
      find.byKey(const ValueKey('dns-lookup-unavailable')),
      findsOneWidget,
    );

    fixture.sync.applyEnded(101);
    await tester.tap(_button('dns-lookup-run'));
    await tester.pump();
    await tester.pump();

    expect(fixture.calls, hasLength(1));
    expect(find.byKey(const ValueKey('dns-lookup-result')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders all DNS sections and enforces the Core timeout', (
    tester,
  ) async {
    final fixture = await _pump(tester, reply: (_) async => _fullResponse);
    await _query(tester, 'Fixture.Example.Test.');

    expect(find.byKey(const ValueKey('dns-lookup-result')), findsOneWidget);
    expect(find.text('Answers (3)'), findsOneWidget);
    expect(find.text('Authority records (1)'), findsOneWidget);
    expect(find.text('Additional records (1)'), findsOneWidget);
    expect(find.text('CNAME'), findsOneWidget);
    expect(find.text('TTL (seconds): 301'), findsOneWidget);
    expect(find.text('TTL (seconds): 900'), findsOneWidget);
    expect(find.text(_longIpv6), findsOneWidget);
    expect(find.text('canonical.example.test.'), findsOneWidget);
    expect(fixture.calls, hasLength(1));
    expect(fixture.calls.single.name, 'fixture.example.test.');
    expect(fixture.calls.single.type, 'A');
    expect(fixture.calls.single.timeout, const Duration(seconds: 8));
    expect(fixture.calls.single.cancellation.isCancelled, isFalse);
    await _export(tester, fixture.shot, 'dns-lookup-success');
    expect(tester.takeException(), isNull);
  });

  testWidgets('NOERROR with no answers differs from NXDOMAIN', (tester) async {
    var count = 0;
    final fixture = await _pump(
      tester,
      reply: (_) async => ++count == 1 ? _response() : _response(rcode: 3),
    );
    await _query(tester, 'empty.example.test');
    expect(find.text('No records of this type were returned.'), findsOneWidget);
    expect(find.text('The domain does not exist (NXDOMAIN).'), findsNothing);
    await tester.tap(_button('dns-lookup-run'));
    await tester.pump();
    await tester.pump();
    expect(find.text('The domain does not exist (NXDOMAIN).'), findsOneWidget);
    expect(find.text('No records of this type were returned.'), findsNothing);
    expect(fixture.calls, hasLength(2));
    await _export(tester, fixture.shot, 'dns-lookup-nxdomain');
  });

  testWidgets('timeout is retryable and never renders the raw error', (
    tester,
  ) async {
    final fixture = await _pump(
      tester,
      reply: (_) => Future<DnsQueryResult>.error(
        TimeoutException('upstream password=secret'),
      ),
    );
    await _query(tester, 'timeout.example.test');

    expect(find.byKey(const ValueKey('dns-lookup-timedOut')), findsOneWidget);
    expect(
      find.text('The DNS query timed out. You can try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('secret'), findsNothing);
    expect(
      tester.widget<TonalButton>(_button('dns-lookup-run')).onPressed,
      isNotNull,
    );
    expect(fixture.calls, hasLength(1));
  });

  testWidgets('cancel button stops the request and suppresses its answer', (
    tester,
  ) async {
    final reply = Completer<DnsQueryResult>();
    final fixture = await _pump(tester, reply: (_) => reply.future);
    await tester.enterText(_nameField(), 'cancel.example.test');
    await tester.tap(_button('dns-lookup-run'));
    await tester.pump();
    final token = fixture.calls.single.cancellation;

    await tester.tap(_button('dns-lookup-cancel'));
    await tester.pump();

    expect(token.isCancelled, isTrue);
    expect(find.byKey(const ValueKey('dns-lookup-cancelled')), findsOneWidget);
    reply.complete(_fullResponse);
    await tester.pump();
    expect(find.byKey(const ValueKey('dns-lookup-result')), findsNothing);
  });

  testWidgets(
    'editing the name cancels the request and drops its late answer',
    (tester) async {
      final reply = Completer<DnsQueryResult>();
      final fixture = await _pump(tester, reply: (_) => reply.future);
      await tester.enterText(_nameField(), 'first.example.test');
      await tester.tap(_button('dns-lookup-run'));
      await tester.pump();
      final token = fixture.calls.single.cancellation;
      expect(find.byKey(const ValueKey('dns-lookup-loading')), findsOneWidget);

      await tester.enterText(_nameField(), 'second.example.test');
      await tester.pump();
      expect(token.isCancelled, isTrue);
      expect(find.byKey(const ValueKey('dns-lookup-idle')), findsOneWidget);

      reply.complete(_fullResponse);
      await tester.pump();
      expect(find.byKey(const ValueKey('dns-lookup-result')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('changing record type cancels an in-flight request', (
    tester,
  ) async {
    final reply = Completer<DnsQueryResult>();
    var callCount = 0;
    final fixture = await _pump(
      tester,
      reply: (_) =>
          ++callCount == 1 ? reply.future : Future.value(_fullResponse),
    );
    await tester.enterText(_nameField(), 'fixture.example.test');
    await tester.tap(_button('dns-lookup-run'));
    await tester.pump();
    final token = fixture.calls.single.cancellation;

    await tester.tap(_button('dns-lookup-type'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('AAAA').last);
    await tester.pumpAndSettle();

    expect(token.isCancelled, isTrue);
    expect(find.byKey(const ValueKey('dns-lookup-idle')), findsOneWidget);
    reply.complete(_fullResponse);
    await tester.pump();
    expect(find.byKey(const ValueKey('dns-lookup-result')), findsNothing);
    await tester.tap(_button('dns-lookup-run'));
    await tester.pump();
    await tester.pump();
    expect(fixture.calls, hasLength(2));
    expect(fixture.calls.last.type, 'AAAA');
    expect(find.byKey(const ValueKey('dns-lookup-result')), findsOneWidget);
  });

  testWidgets('closing the page during type selection ignores its callback', (
    tester,
  ) async {
    final reply = Completer<DnsQueryResult>();
    final fixture = await _pump(tester, reply: (_) => reply.future);
    await _query(tester, 'fixture.example.test');
    final token = fixture.calls.single.cancellation;

    await tester.tap(_button('dns-lookup-type'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('AAAA').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(token.isCancelled, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(token.isCancelled, isTrue);
    reply.complete(_fullResponse);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final (name, update) in <(String, RouteState Function(RouteState))>[
    ('core epoch', (route) => route.copyWith(coreEpoch: route.coreEpoch + 1)),
    (
      'route version',
      (route) => route.copyWith(routeVersion: route.routeVersion + 1),
    ),
    ('host epoch', (route) => route.copyWith(hostEpoch: route.hostEpoch + 1)),
    ('proxy mode', (route) => route.copyWith(proxied: !route.proxied)),
    ('local pick', (route) => route.copyWith(picks: route.picks + 1)),
    ('sync state', (route) => route.copyWith(synced: false)),
    ('live state', (route) => route.copyWith(live: false)),
  ]) {
    testWidgets('route $name cancels and invalidates an in-flight query', (
      tester,
    ) async {
      final reply = Completer<DnsQueryResult>();
      final fixture = await _pump(tester, reply: (_) => reply.future);
      await tester.enterText(_nameField(), 'route.example.test');
      await tester.tap(_button('dns-lookup-run'));
      await tester.pump();
      final token = fixture.calls.single.cancellation;

      fixture.routes.replace(update(_liveRoute));
      await tester.pump();

      expect(token.isCancelled, isTrue);
      expect(find.byKey(const ValueKey('dns-lookup-stale')), findsOneWidget);
      reply.complete(_fullResponse);
      await tester.pump();
      expect(find.byKey(const ValueKey('dns-lookup-result')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a local pick invalidates a completed answer', (tester) async {
    final fixture = await _pump(tester);
    await _query(tester, 'picked.example.test');
    expect(find.byKey(const ValueKey('dns-lookup-result')), findsOneWidget);

    fixture.routes.replace(_liveRoute.copyWith(picks: _liveRoute.picks + 1));
    await tester.pump();

    expect(find.byKey(const ValueKey('dns-lookup-stale')), findsOneWidget);
    expect(find.byKey(const ValueKey('dns-lookup-result')), findsNothing);
    expect(fixture.calls, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('hiding the app cancels a pending query', (tester) async {
    final reply = Completer<DnsQueryResult>();
    final fixture = await _pump(tester, reply: (_) => reply.future);
    await tester.enterText(_nameField(), 'hidden.example.test');
    await tester.tap(_button('dns-lookup-run'));
    await tester.pump();
    final token = fixture.calls.single.cancellation;

    fixture.visibility.setVisible(false);
    await tester.pump();

    expect(token.isCancelled, isTrue);
    expect(find.byKey(const ValueKey('dns-lookup-cancelled')), findsOneWidget);
    reply.complete(_fullResponse);
    await tester.pump();
    expect(find.byKey(const ValueKey('dns-lookup-result')), findsNothing);
  });

  testWidgets('long TXT and IPv6 records fit a narrow large-text viewport', (
    tester,
  ) async {
    final longTxt = '"${'diagnostic-value-' * 24}"';
    final fixture = await _pump(
      tester,
      size: const Size(320, 740),
      textScale: 2,
      reply: (_) async => _response(
        answers: [
          const DnsRecordDto(
            name: 'fixture.example.test.',
            rtype: 28,
            ttl: 180,
            data: _longIpv6,
          ),
          DnsRecordDto(
            name: 'fixture.example.test.',
            rtype: 16,
            ttl: 240,
            data: longTxt,
          ),
        ],
      ),
    );
    await _query(tester, 'fixture.example.test');

    expect(find.text(_longIpv6), findsOneWidget);
    expect(find.text(longTxt), findsOneWidget);
    expect(fixture.calls.single.type, 'A');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'copy report includes observed TTL and rcode, not invented metadata',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied =
                (call.arguments as Map<Object?, Object?>)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final fixture = await _pump(
        tester,
        reply: (_) async => _response(
          answers: const [
            DnsRecordDto(
              name: 'fixture.example.test.',
              rtype: 1,
              ttl: 321,
              data: '192.0.2.33',
            ),
          ],
        ),
      );
      await _query(tester, 'fixture.example.test');
      await tester.tap(find.byTooltip('Copy report'));
      await tester.pump();

      expect(copied, contains('Response code: NOERROR (0)'));
      expect(copied, contains('fixture.example.test.\t321\tA\t192.0.2.33'));
      expect(
        copied,
        contains('This API does not identify the upstream or cache hit'),
      );
      expect(
        RegExp(
          r'^(?:Upstream|Cache hit|Class):',
          caseSensitive: false,
          multiLine: true,
        ).hasMatch(copied!),
        isFalse,
      );
      expect(copied, isNot(contains('Class: IN')));
      expect(fixture.calls.single.cancellation.isCancelled, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
