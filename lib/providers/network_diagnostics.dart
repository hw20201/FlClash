import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/core/api/errors.dart';
import 'package:fl_clash/core/api/model_api.dart';
import 'package:fl_clash/models/core.dart';
import 'package:fl_clash/models/network_diagnostics.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod/riverpod.dart';

import 'core.dart';
import 'route_state.dart';
import 'routed_probe.dart';

final networkDiagnosticsProvider =
    NotifierProvider<
      NetworkDiagnostics,
      RoutedProbeState<DiagnosticFamily, DiagnosticExit>
    >(NetworkDiagnostics.new);

class NetworkDiagnostics
    extends Notifier<RoutedProbeState<DiagnosticFamily, DiagnosticExit>>
    with RoutedProbe<DiagnosticFamily, DiagnosticExit> {
  static const _exitTimeout = Duration(seconds: 8);
  static const _geoTimeout = Duration(seconds: 5);

  @override
  RoutedProbeState<DiagnosticFamily, DiagnosticExit> build() => buildProbe();

  @override
  bool isFailure(DiagnosticExit value) => !value.isSuccess;

  @override
  Future<Map<DiagnosticFamily, ProbeAnswer<DiagnosticExit>>> probe(
    DiagnosticFamily target,
    RouteState route,
  ) async {
    final source = switch (target) {
      DiagnosticFamily.ipv4 => 'https://api.ipify.org?format=json',
      DiagnosticFamily.ipv6 => 'https://api6.ipify.org?format=json',
    };
    final api = ref.read(coreHandlerProvider).api;
    final proxy = route.proxied ? routedOutbound : directOutbound;
    OutboundIpResult? result;
    final OutboundIpResult exit;
    final InternetAddress address;
    try {
      exit = await api.probeOutboundIp(
        OutboundIpParams(
          proxyName: proxy,
          urls: [source],
          timeout: _exitTimeout.inMilliseconds,
        ),
        guard: _exitTimeout + const Duration(seconds: 1),
      );
      result = exit;
      address = _readAddress(_readJson(exit, source)['ip']);
      final matches = switch (target) {
        DiagnosticFamily.ipv4 => address.type == InternetAddressType.IPv4,
        DiagnosticFamily.ipv6 =>
          address.type == InternetAddressType.IPv6 && !_isMapped(address),
      };
      if (!matches) {
        throw const _DiagnosticFailure(
          DiagnosticErrorKind.familyMismatch,
          'The endpoint returned a different address family',
        );
      }
    } catch (error) {
      final failure = _failureOf(error);
      return {
        target: ProbeAnswer(
          value: DiagnosticExit(
            family: target,
            source: source,
            checkedAt: DateTime.now(),
            chains: result?.chains ?? const [],
            errorKind: failure.kind,
            errorDetail: failure.detail,
          ),
          coreEpoch: result?.coreEpoch,
          routeVersion: result?.routeVersion,
          hits: result?.hits ?? const [],
          timedOut: failure.kind == DiagnosticErrorKind.timeout,
        ),
      };
    }

    final checkedAt = DateTime.now();
    var hits = exit.hits;
    Map<String, Object?>? geo;
    String? geoSource;
    _DiagnosticFailure? enrichmentFailure;
    final stamp = RouteStamp(
      coreEpoch: exit.coreEpoch,
      routeVersion: exit.routeVersion,
      hostEpoch: route.hostEpoch,
      proxied: route.proxied,
      hits: exit.hits,
    );
    if (ref.mounted && ref.read(routeTrackerProvider).isFresh(stamp)) {
      geoSource = Uri.https(
        'get.geojs.io',
        '/v1/ip/geo/${address.address}.json',
      ).toString();
      try {
        final location = await api.probeOutboundIp(
          OutboundIpParams(
            proxyName: proxy,
            urls: [geoSource],
            timeout: _geoTimeout.inMilliseconds,
          ),
          guard: _geoTimeout + const Duration(seconds: 1),
        );
        if (location.coreEpoch != exit.coreEpoch ||
            location.routeVersion != exit.routeVersion) {
          return {
            target: ProbeAnswer(
              value: DiagnosticExit(
                family: target,
                source: source,
                geoSource: geoSource,
                checkedAt: checkedAt,
                errorKind: DiagnosticErrorKind.unknown,
                errorDetail: 'Route changed during location lookup',
              ),
              coreEpoch: location.coreEpoch,
              routeVersion: location.routeVersion,
              hits: location.hits,
            ),
          };
        }
        hits = {...hits, ...location.hits}.toList(growable: false);
        final data = _readJson(location, geoSource);
        if (!listEquals(
          _readAddress(data['ip']).rawAddress,
          address.rawAddress,
        )) {
          throw const _DiagnosticFailure(
            DiagnosticErrorKind.invalidResponse,
            'Location response does not describe the observed address',
          );
        }
        geo = data;
      } catch (error) {
        enrichmentFailure = _failureOf(error);
      }
    }
    return {
      target: ProbeAnswer(
        value: DiagnosticExit(
          family: target,
          address: address.address,
          country: _text(geo?['country']),
          region: _text(geo?['region']),
          asn: _asn(geo?['asn']),
          organization: _text(geo?['organization_name']),
          source: source,
          geoSource: geoSource,
          checkedAt: checkedAt,
          chains: exit.chains,
          enrichmentErrorKind: enrichmentFailure?.kind,
          enrichmentErrorDetail: enrichmentFailure?.detail,
        ),
        coreEpoch: exit.coreEpoch,
        routeVersion: exit.routeVersion,
        hits: hits,
      ),
    };
  }
}

Map<String, Object?> _readJson(OutboundIpResult result, String source) {
  if (result.error case final error?) {
    // The native outbound probe exposes only timeout/failed, not dial stages.
    throw _DiagnosticFailure(
      error == probeErrorTimeout
          ? DiagnosticErrorKind.timeout
          : DiagnosticErrorKind.unknown,
      error,
    );
  }
  if (result.url != source) {
    throw const _DiagnosticFailure(
      DiagnosticErrorKind.invalidResponse,
      'The Core returned an unexpected probe source',
    );
  }
  try {
    final data = jsonDecode(result.body);
    if (data is Map<String, dynamic>) return data;
  } on FormatException {
    throw const _DiagnosticFailure(
      DiagnosticErrorKind.invalidResponse,
      'The endpoint returned invalid JSON',
    );
  }
  throw const _DiagnosticFailure(
    DiagnosticErrorKind.invalidResponse,
    'The endpoint returned a non-object response',
  );
}

InternetAddress _readAddress(Object? value) {
  final text = value is String ? value.trim() : '';
  final address = text.contains('%') ? null : InternetAddress.tryParse(text);
  if (address == null || !_isPublic(address)) {
    throw const _DiagnosticFailure(
      DiagnosticErrorKind.invalidResponse,
      'The response does not contain a public literal IP address',
    );
  }
  return address;
}

bool _isMapped(InternetAddress address) {
  final bytes = address.rawAddress;
  return bytes.length == 16 &&
      bytes.take(10).every((byte) => byte == 0) &&
      bytes[10] == 255 &&
      bytes[11] == 255;
}

bool _isPublic(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
    return false;
  }
  final bytes = address.rawAddress;
  if (bytes.every((byte) => byte == 0)) return false;
  if (address.type == InternetAddressType.IPv6 && !_isMapped(address)) {
    return (bytes.first & 0xfe) != 0xfc;
  }
  final v4 = bytes.length == 4 ? bytes : bytes.sublist(12);
  return !(v4[0] == 10 ||
      v4[0] == 127 ||
      v4[0] == 169 && v4[1] == 254 ||
      v4[0] == 172 && v4[1] >= 16 && v4[1] <= 31 ||
      v4[0] == 192 && v4[1] == 168 ||
      v4[0] == 100 && v4[1] >= 64 && v4[1] <= 127 ||
      v4.every((byte) => byte == 0) ||
      v4.every((byte) => byte == 255) ||
      v4[0] >= 224 && v4[0] <= 239);
}

String? _text(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  return text.isEmpty || text.toLowerCase() == 'unknown' || text == 'None'
      ? null
      : text;
}

String? _asn(Object? value) {
  final number = value is int
      ? value
      : value is String
      ? int.tryParse(value)
      : null;
  // GeoJS uses 64512 as its unknown-ASN sentinel.
  return number != null && number > 0 && number != 64512 ? '$number' : null;
}

_DiagnosticFailure _failureOf(Object error) => switch (error) {
  _DiagnosticFailure() => error,
  TimeoutException() => _DiagnosticFailure(
    DiagnosticErrorKind.timeout,
    error.toString(),
  ),
  CoreMethodException(:final isCoreUnavailable) when isCoreUnavailable =>
    _DiagnosticFailure(DiagnosticErrorKind.unavailable, error.toString()),
  _ => _DiagnosticFailure(DiagnosticErrorKind.unknown, error.toString()),
};

class _DiagnosticFailure implements Exception {
  const _DiagnosticFailure(this.kind, this.detail);

  final DiagnosticErrorKind kind;
  final String detail;
}
