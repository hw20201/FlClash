import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/models/core.dart';
import 'package:fl_clash/models/network_diagnostics.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/network_diagnostics.dart';
import 'package:fl_clash/providers/route_state.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

import '../helpers/core_mocks.dart';
import '../helpers/probe_dtos.dart';

const _v4 = 'https://api.ipify.org?format=json';
const _v6 = 'https://api6.ipify.org?format=json';
const _address4 = '8.8.8.8';
const _address6 = '2001:4860:4860::8888';
const _exitHit = RouteHitDto(host: 'api.ipify.org:443', exit: 'Exit');
const _geoHit = RouteHitDto(host: 'get.geojs.io:443', exit: 'Geo');

OutboundIp _exit(String source, String address, {int epoch = 1}) =>
    outboundIpOf(
      url: source,
      body: jsonEncode({'ip': address}),
      chains: const ['Exit', 'Proxy'],
      epoch: epoch,
      hits: const [_exitHit],
    );

OutboundIp _location(
  String source,
  String address, {
  int epoch = 1,
  int version = 1,
  Object? asn = 15169,
  String organization = 'Google LLC',
}) => outboundIpOf(
  url: source,
  body: jsonEncode({
    'ip': address,
    'country': 'United States',
    'region': 'California',
    'asn': asn,
    'organization_name': organization,
  }),
  chains: const ['Geo', 'Proxy'],
  epoch: epoch,
  version: version,
  hits: const [_geoHit],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CoreMocks mocks;
  late List<OutboundAsk> asks;

  setUp(() {
    mocks = coreMocks();
    asks = [];
    stubOutboundIp(mocks.api, (ask) async {
      asks.add(ask);
      final source = ask.urls.single;
      if (source == _v4) return _exit(source, _address4);
      if (source == _v6) return _exit(source, _address6);
      final address = Uri.parse(
        source,
      ).pathSegments.last.replaceFirst('.json', '');
      return _location(source, address);
    });
  });

  ProviderContainer build({bool proxied = true, bool synced = true}) {
    final container = ProviderContainer(
      overrides: [
        routeTrackerProvider.overrideWithBuild(
          (_, _) => RouteState(
            coreEpoch: 1,
            routeVersion: 1,
            hostEpoch: 1,
            proxied: proxied,
            synced: synced,
            live: synced,
          ),
        ),
        coreHandlerProvider.overrideWithValue(mocks.controller),
      ],
    );
    addTearDown(container.dispose);
    container.listen(networkDiagnosticsProvider, (_, _) {});
    return container;
  }

  ProbeEntry<DiagnosticExit> entryOf(
    ProviderContainer container, [
    DiagnosticFamily family = DiagnosticFamily.ipv4,
  ]) => container.read(networkDiagnosticsProvider).entryOf(family);

  Future<ProbeEntry<DiagnosticExit>> refresh(
    ProviderContainer container, [
    DiagnosticFamily family = DiagnosticFamily.ipv4,
  ]) async {
    container.read(networkDiagnosticsProvider.notifier).refresh([family]);
    await pumpEventQueue();
    return entryOf(container, family);
  }

  test(
    'independently probes both families and exact-IP location data',
    () async {
      final container = build();
      final before = DateTime.now();
      container
          .read(networkDiagnosticsProvider.notifier)
          .refresh(DiagnosticFamily.values);
      await pumpEventQueue();

      expect(asks, hasLength(4));
      expect(asks.every((ask) => ask.urls.length == 1), isTrue);
      expect(asks.every((ask) => ask.proxy.isEmpty), isTrue);
      expect(asks.take(2).map((ask) => ask.urls.single), [_v4, _v6]);
      expect(asks.take(2).map((ask) => ask.timeout), [8000, 8000]);
      expect(asks.skip(2).map((ask) => ask.timeout), [5000, 5000]);
      for (final family in DiagnosticFamily.values) {
        final entry = entryOf(container, family);
        final value = entry.value!;
        final address = family == DiagnosticFamily.ipv4 ? _address4 : _address6;
        expect(entry.phase, ProbePhase.fresh);
        expect(value.isSuccess, isTrue);
        expect(value.family, family);
        expect(value.address, address);
        expect(value.source, family == DiagnosticFamily.ipv4 ? _v4 : _v6);
        expect(value.country, 'United States');
        expect(value.region, 'California');
        expect(value.asn, '15169');
        expect(value.organization, 'Google LLC');
        expect(value.enrichmentErrorKind, isNull);
        expect(value.chains, ['Exit', 'Proxy']);
        expect(value.checkedAt.isBefore(before), isFalse);
        expect(value.checkedAt.isAfter(DateTime.now()), isFalse);
        expect(Uri.parse(value.geoSource!).path, '/v1/ip/geo/$address.json');
        expect(entry.stamp?.coreEpoch, 1);
        expect(entry.stamp?.routeVersion, 1);
        expect(entry.stamp?.hostEpoch, 1);
        expect(entry.stamp?.hits, const [
          RouteHit(host: 'api.ipify.org:443', exit: 'Exit'),
          RouteHit(host: 'get.geojs.io:443', exit: 'Geo'),
        ]);
      }
    },
  );

  test('pins both requests to DIRECT while the proxy is off', () async {
    final container = build(proxied: false);
    await refresh(container);

    expect(asks, hasLength(2));
    expect(asks.every((ask) => ask.proxy == 'DIRECT'), isTrue);
    expect(entryOf(container).stamp?.proxied, isFalse);
  });

  test('waits for the existing route tracker to become live', () async {
    final container = build(synced: false);
    await refresh(container);
    expect(asks, isEmpty);

    container
        .read(routeTrackerProvider.notifier)
        .applySnapshot(
          const RouteSnapshot(coreEpoch: 1, routeVersion: 1, running: true),
        );
    await pumpEventQueue();
    expect(asks, hasLength(2));
    expect(entryOf(container).phase, ProbePhase.fresh);
  });

  test('waits while hidden and launches when the app is visible', () async {
    final container = build();
    container.read(appVisibleProvider.notifier).value = false;
    await refresh(container);
    expect(asks, isEmpty);

    container.read(appVisibleProvider.notifier).value = true;
    await pumpEventQueue();
    expect(asks, hasLength(2));
    expect(entryOf(container).phase, ProbePhase.fresh);
  });

  for (final (family, source, wrongAddress) in [
    (DiagnosticFamily.ipv4, _v4, _address6),
    (DiagnosticFamily.ipv6, _v6, _address4),
    (DiagnosticFamily.ipv6, _v6, '::ffff:8.8.8.8'),
  ]) {
    test('$family rejects the wrong literal family $wrongAddress', () async {
      stubOutboundIp(mocks.api, (ask) async {
        asks.add(ask);
        return _exit(source, wrongAddress);
      });
      final entry = await refresh(build(), family);

      expect(asks, hasLength(1));
      expect(entry.phase, ProbePhase.failed);
      expect(entry.value?.isSuccess, isFalse);
      expect(entry.value?.address, isNull);
      expect(entry.value?.errorKind, DiagnosticErrorKind.familyMismatch);
      expect(entry.stamp?.coreEpoch, 1);
      expect(entry.stamp?.hits, isNotEmpty);
    });
  }

  for (final body in [
    '<html>8.8.8.8</html>',
    '[]',
    '{"ip":"example.com"}',
    '{"ip":"8.8.8.8/path"}',
    '{"ip":"fe80::1%wlan0"}',
    '{"ip":"192.168.1.1"}',
    '{"ip":"100.64.0.1"}',
    '{"ip":"fd00::1"}',
  ]) {
    test('rejects an invalid exit response $body', () async {
      stubOutboundIp(mocks.api, (ask) async {
        asks.add(ask);
        return outboundIpOf(url: _v4, body: body);
      });
      final entry = await refresh(build());

      expect(asks, hasLength(1));
      expect(entry.phase, ProbePhase.failed);
      expect(entry.value?.errorKind, DiagnosticErrorKind.invalidResponse);
      expect(entry.value?.address, isNull);
    });
  }

  test('rejects a native response from an unexpected source', () async {
    stubOutboundIp(mocks.api, (_) async => _exit(_v6, _address4));
    final entry = await refresh(build());

    expect(entry.phase, ProbePhase.failed);
    expect(entry.value?.errorKind, DiagnosticErrorKind.invalidResponse);
  });

  for (final error in ['timeout', 'failed', 'TLS handshake failed']) {
    test('preserves the native error category and stamp for $error', () async {
      stubOutboundIp(
        mocks.api,
        (_) async => outboundIpOf(error: error, hits: const [_exitHit]),
      );
      final entry = await refresh(build());

      expect(entry.phase, ProbePhase.failed);
      expect(
        entry.value?.errorKind,
        error == 'timeout'
            ? DiagnosticErrorKind.timeout
            : DiagnosticErrorKind.unknown,
      );
      expect(entry.value?.errorDetail, error);
      expect(entry.stamp?.coreEpoch, 1);
      expect(entry.stamp?.routeVersion, 1);
      expect(entry.stamp?.hits, const [
        RouteHit(host: 'api.ipify.org:443', exit: 'Exit'),
      ]);
    });
  }

  for (final (error, kind) in [
    (
      const CoreMethodException(
        code: 'transport_disconnected',
        message: 'Core disconnected',
      ),
      DiagnosticErrorKind.unavailable,
    ),
    (
      const CoreMethodException(
        code: 'internal',
        message: 'DNS may have failed',
      ),
      DiagnosticErrorKind.unknown,
    ),
    (TimeoutException('Core method timed out'), DiagnosticErrorKind.timeout),
  ]) {
    test('returns a failure value for a thrown ${kind.name} error', () async {
      stubOutboundIp(mocks.api, (_) => Future<OutboundIp>.error(error));
      final entry = await refresh(build());

      expect(entry.phase, ProbePhase.failed);
      expect(entry.value?.errorKind, kind);
      expect(entry.value?.errorDetail, error.toString());
      expect(entry.stamp?.coreEpoch, 1);
      expect(entry.stamp?.hits, isEmpty);
    });
  }

  test(
    'an incorrect geo IP cannot attach location to an observed exit',
    () async {
      stubOutboundIp(mocks.api, (ask) async {
        asks.add(ask);
        final source = ask.urls.single;
        return source == _v4
            ? _exit(source, _address4)
            : _location(source, '1.1.1.1');
      });
      final entry = await refresh(build());

      expect(asks, hasLength(2));
      expect(entry.phase, ProbePhase.fresh);
      expect(entry.value?.address, _address4);
      expect(entry.value?.country, isNull);
      expect(entry.value?.asn, isNull);
      expect(
        entry.value?.enrichmentErrorKind,
        DiagnosticErrorKind.invalidResponse,
      );
    },
  );

  test(
    'compares IPv6 geo addresses as literals rather than spelling',
    () async {
      stubOutboundIp(mocks.api, (ask) async {
        final source = ask.urls.single;
        return source == _v6
            ? _exit(source, _address6)
            : _location(source, '2001:4860:4860:0:0:0:0:8888');
      });
      final entry = await refresh(build(), DiagnosticFamily.ipv6);

      expect(entry.value?.country, 'United States');
      expect(entry.value?.enrichmentErrorKind, isNull);
    },
  );

  test('retains the exit when optional location lookup times out', () async {
    stubOutboundIp(mocks.api, (ask) async {
      asks.add(ask);
      return ask.urls.single == _v4
          ? _exit(_v4, _address4)
          : outboundIpOf(error: 'timeout', hits: const [_geoHit]);
    });
    final entry = await refresh(build());

    expect(asks, hasLength(2));
    expect(entry.phase, ProbePhase.fresh);
    expect(entry.value?.isSuccess, isTrue);
    expect(entry.value?.address, _address4);
    expect(entry.value?.country, isNull);
    expect(entry.value?.enrichmentErrorKind, DiagnosticErrorKind.timeout);
    expect(entry.value?.enrichmentErrorDetail, 'timeout');
    expect(entry.stamp?.hits, hasLength(2));
  });

  test('does not invent GeoJS unknown ASN or organization values', () async {
    stubOutboundIp(mocks.api, (ask) async {
      final source = ask.urls.single;
      return source == _v4
          ? _exit(source, _address4)
          : _location(source, _address4, asn: 64512, organization: 'Unknown');
    });
    final entry = await refresh(build());

    expect(entry.value?.asn, isNull);
    expect(entry.value?.organization, isNull);
    expect(entry.value?.country, 'United States');
  });

  test('does not promote an old exit to a newer enrichment epoch', () async {
    stubOutboundIp(mocks.api, (ask) async {
      final source = ask.urls.single;
      return source == _v4
          ? _exit(source, _address4)
          : _location(source, _address4, epoch: 2);
    });
    final entry = await refresh(build());

    expect(entry.phase, ProbePhase.empty);
    expect(entry.value, isNull);
  });

  testWidgets('a route reset supersedes a stale exit before enrichment', (
    tester,
  ) async {
    final first = Completer<OutboundIp>();
    var exits = 0;
    stubOutboundIp(mocks.api, (ask) {
      asks.add(ask);
      final source = ask.urls.single;
      if (source == _v4 && ++exits == 1) return first.future;
      return Future.value(
        source == _v4
            ? _exit(source, '1.1.1.1', epoch: 2)
            : _location(source, '1.1.1.1', epoch: 2),
      );
    });
    final container = build();
    final notifier = container.read(networkDiagnosticsProvider.notifier);
    notifier.watch(DiagnosticFamily.ipv4);
    await tester.pump();
    expect(asks, hasLength(1));

    container
        .read(routeTrackerProvider.notifier)
        .applySnapshot(
          const RouteSnapshot(coreEpoch: 2, routeVersion: 1, running: true),
        );
    await tester.pump(probeMoveSettleDuration);
    expect(entryOf(container).value?.address, '1.1.1.1');
    first.complete(_exit(_v4, _address4));
    await tester.pump();

    expect(entryOf(container).value?.address, '1.1.1.1');
    expect(entryOf(container).stamp?.coreEpoch, 2);
    expect(asks, hasLength(3));
    notifier.unwatch(DiagnosticFamily.ipv4);
    container.dispose();
  });

  testWidgets('a failed watched payload never becomes a fresh result', (
    tester,
  ) async {
    stubOutboundIp(mocks.api, (_) async => _exit(_v6, _address4));
    final container = build();
    final notifier = container.read(networkDiagnosticsProvider.notifier);
    notifier.watch(DiagnosticFamily.ipv6);
    await tester.pump();
    expect(entryOf(container, DiagnosticFamily.ipv6).isLoading, isTrue);

    await tester.pump(probeConfirmDelay);
    final entry = entryOf(container, DiagnosticFamily.ipv6);
    expect(entry.phase, ProbePhase.failed);
    expect(entry.value?.errorKind, DiagnosticErrorKind.familyMismatch);
    notifier.unwatch(DiagnosticFamily.ipv6);
    container.dispose();
  });
}
