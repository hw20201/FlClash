import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/exit_map.dart';
import 'package:fl_clash/providers/route_state.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

import '../helpers/core_mocks.dart';
import '../helpers/probe_dtos.dart';

void main() {
  test('parses supported geolocation payloads and validates coordinates', () {
    for (final body in [
      '{"ip":"1.2.3.4","country_code":"JP","city":"Tokyo","latitude":35.7,"longitude":139.7}',
      '{"ip":"1.2.3.4","country":"JP","city":"Tokyo","loc":"35.7,139.7"}',
      '{"ip":"1.2.3.4","location":{"countryCode":"JP","city":"Tokyo","lat":"35.7","lon":"139.7"}}',
    ]) {
      final place = parseExitMapOrigin(body);
      expect(place?.country, 'JP');
      expect(place?.city, 'Tokyo');
      expect(place?.latitude, 35.7);
      expect(place?.longitude, 139.7);
      expect(place?.approximate, isFalse);
    }
    expect(parseExitMapOrigin('{"latitude":0,"longitude":0}')?.city, isEmpty);
    for (final body in [
      '',
      '{',
      '[]',
      '{"success":false}',
      '{"lat":91,"lon":0}',
      '{"lat":0,"lon":181}',
      '{"latitude":"NaN","longitude":0}',
    ]) {
      expect(parseExitMapOrigin(body), isNull, reason: body);
    }
  });

  test('falls back to a country without using the Cloudflare edge city', () {
    final place = parseExitMapOrigin('ip=1.2.3.4\nloc=JP\ncolo=LAX\n');
    expect(place?.country, 'JP');
    expect(place?.city, '东京');
    expect(place?.approximate, isTrue);
    expect(parseExitMapOrigin('{"country_code":"US"}')?.approximate, isTrue);
  });

  test(
    'origin probes always pin DIRECT even when the route is proxied',
    () async {
      final mocks = coreMocks();
      final asks = <OutboundAsk>[];
      stubOutboundIp(mocks.api, (ask) async {
        asks.add(ask);
        return outboundIpOf(
          body:
              '{"ip":"1.2.3.4","country":"JP","city":"Tokyo","loc":"35.7,139.7"}',
        );
      });
      final container = ProviderContainer(
        overrides: [
          coreHandlerProvider.overrideWithValue(mocks.controller),
          routeTrackerProvider.overrideWithBuild(
            (_, _) => const RouteState(
              coreEpoch: 1,
              routeVersion: 1,
              hostEpoch: 1,
              proxied: true,
              synced: true,
              live: true,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(exitMapOriginProvider, (_, _) {});
      final probe = container.read(exitMapOriginProvider.notifier);
      probe.watch(directOutbound);
      await pumpEventQueue();
      expect(asks.single.proxy, directOutbound);
      expect(asks.single.urls.first, 'https://api.ip.sb/geoip');
      expect(
        container.read(exitMapOriginProvider).entryOf(directOutbound).phase,
        ProbePhase.fresh,
      );
      expect(
        container.read(exitMapOriginProvider).valueOf(directOutbound)?.city,
        'Tokyo',
      );
      probe.unwatch(directOutbound);
    },
  );
}
