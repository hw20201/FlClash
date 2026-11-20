import 'dart:convert';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/exit_map_geo.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/core/api/model_api.dart';
import 'package:fl_clash/models/models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'core.dart';
import 'route_state.dart';
import 'routed_probe.dart';

part 'generated/exit_map.g.dart';

@Riverpod(keepAlive: true)
class ExitMapOrigin extends _$ExitMapOrigin
    with RoutedProbe<String, ExitMapPlace> {
  @override
  RoutedProbeState<String, ExitMapPlace> build() => buildProbe();

  @override
  Future<Map<String, ProbeAnswer<ExitMapPlace>>> probe(
    String target,
    RouteState route,
  ) async {
    final result = await ref
        .read(coreHandlerProvider)
        .api
        .probeOutboundIp(
          OutboundIpParams(
            proxyName: directOutbound,
            urls: const [
              'https://api.ip.sb/geoip',
              'https://ipinfo.io/json',
              'https://ipwho.is',
              'https://get.geojs.io/v1/ip/geo.json',
              'https://www.cloudflare.com/cdn-cgi/trace',
            ],
            timeout: outboundIpTimeoutDuration.inMilliseconds,
          ),
        );
    return {
      target: ProbeAnswer(
        value: result.error == null ? parseExitMapOrigin(result.body) : null,
        coreEpoch: result.coreEpoch,
        routeVersion: result.routeVersion,
        hits: result.hits,
        timedOut: result.error == probeErrorTimeout,
      ),
    };
  }
}

ExitMapPlace? parseExitMapOrigin(String body) {
  try {
    if (!body.trimLeft().startsWith('{')) {
      final values = <String, String>{};
      for (final line in const LineSplitter().convert(body)) {
        final index = line.indexOf('=');
        if (index > 0) {
          values[line.substring(0, index)] = line.substring(index + 1);
        }
      }
      // The Cloudflare edge city can differ from the user's location.
      return exitMapCountry(values['loc'] ?? '');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic> || decoded['success'] == false) {
      return null;
    }
    final location = decoded['location'];
    final data = location is Map<String, dynamic> ? location : decoded;
    final rawCountry =
        data['country_code'] ??
        data['countryCode'] ??
        data['cc'] ??
        data['country'];
    final country = rawCountry is String && rawCountry.length == 2
        ? rawCountry.toUpperCase()
        : '';
    double? number(Object? value) =>
        value is num ? value.toDouble() : double.tryParse('$value');
    var lat = number(data['latitude'] ?? data['lat']);
    var lon = number(data['longitude'] ?? data['lon']);
    final loc = data['loc'];
    if (loc is String) {
      final parts = loc.split(',');
      if (parts.length == 2) {
        lat = number(parts[0]);
        lon = number(parts[1]);
      }
    }
    if (lat != null &&
        lon != null &&
        lat.isFinite &&
        lon.isFinite &&
        lat >= -90 &&
        lat <= 90 &&
        lon >= -180 &&
        lon <= 180) {
      final city = data['city'];
      return ExitMapPlace(
        country: country,
        city: city is String ? city.trim() : '',
        latitude: lat,
        longitude: lon,
      );
    }
    return exitMapCountry(country);
  } on FormatException {
    return null;
  }
}
