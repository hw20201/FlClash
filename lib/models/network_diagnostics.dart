import 'package:flutter/foundation.dart';

enum DiagnosticFamily { ipv4, ipv6 }

enum DiagnosticErrorKind {
  dns,
  connect,
  tls,
  timeout,
  http,
  unavailable,
  invalidResponse,
  familyMismatch,
  unknown,
}

@immutable
class DiagnosticExit {
  DiagnosticExit({
    required this.family,
    this.address,
    this.country,
    this.region,
    this.asn,
    this.organization,
    required this.source,
    this.geoSource,
    required this.checkedAt,
    List<String> chains = const [],
    this.errorKind,
    this.errorDetail,
    this.enrichmentErrorKind,
    this.enrichmentErrorDetail,
  }) : chains = List.unmodifiable(chains);

  final DiagnosticFamily family;
  final String? address;
  final String? country;
  final String? region;
  final String? asn;
  final String? organization;
  final String source;
  final String? geoSource;
  final DateTime checkedAt;
  final List<String> chains;
  final DiagnosticErrorKind? errorKind;
  final String? errorDetail;
  final DiagnosticErrorKind? enrichmentErrorKind;
  final String? enrichmentErrorDetail;

  bool get isSuccess => address != null && errorKind == null;

  @override
  bool operator ==(Object other) =>
      other is DiagnosticExit &&
      other.family == family &&
      other.address == address &&
      other.country == country &&
      other.region == region &&
      other.asn == asn &&
      other.organization == organization &&
      other.source == source &&
      other.geoSource == geoSource &&
      other.checkedAt == checkedAt &&
      listEquals(other.chains, chains) &&
      other.errorKind == errorKind &&
      other.errorDetail == errorDetail &&
      other.enrichmentErrorKind == enrichmentErrorKind &&
      other.enrichmentErrorDetail == enrichmentErrorDetail;

  @override
  int get hashCode => Object.hash(
    family,
    address,
    country,
    region,
    asn,
    organization,
    source,
    geoSource,
    checkedAt,
    Object.hashAll(chains),
    errorKind,
    errorDetail,
    enrichmentErrorKind,
    enrichmentErrorDetail,
  );
}
