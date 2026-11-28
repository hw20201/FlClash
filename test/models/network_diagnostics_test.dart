import 'package:fl_clash/models/network_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final checkedAt = DateTime.utc(2026, 11, 27);

  test('failure payloads and absent addresses cannot count as success', () {
    DiagnosticExit value({String? address, DiagnosticErrorKind? error}) =>
        DiagnosticExit(
          family: DiagnosticFamily.ipv4,
          address: address,
          source: 'https://api.ipify.org?format=json',
          checkedAt: checkedAt,
          errorKind: error,
        );

    expect(value().isSuccess, isFalse);
    expect(value(error: DiagnosticErrorKind.timeout).isSuccess, isFalse);
    expect(
      value(address: '8.8.8.8', error: DiagnosticErrorKind.unknown).isSuccess,
      isFalse,
    );
    expect(value(address: '8.8.8.8').isSuccess, isTrue);
  });

  test('location failure does not erase a successful observed exit', () {
    final value = DiagnosticExit(
      family: DiagnosticFamily.ipv6,
      address: '2001:4860:4860::8888',
      source: 'https://api6.ipify.org?format=json',
      checkedAt: checkedAt,
      enrichmentErrorKind: DiagnosticErrorKind.timeout,
    );

    expect(value.isSuccess, isTrue);
    expect(value.country, isNull);
    expect(value.asn, isNull);
  });

  test('copies route chains and keeps them immutable', () {
    final chains = ['Exit', 'Proxy'];
    final value = DiagnosticExit(
      family: DiagnosticFamily.ipv4,
      source: 'source',
      checkedAt: checkedAt,
      chains: chains,
    );
    chains.clear();

    expect(value.chains, ['Exit', 'Proxy']);
    expect(() => value.chains.add('DIRECT'), throwsUnsupportedError);
  });

  test('value equality includes failure details and route evidence', () {
    DiagnosticExit value({String detail = 'failed', String chain = 'Exit'}) =>
        DiagnosticExit(
          family: DiagnosticFamily.ipv4,
          source: 'source',
          checkedAt: checkedAt,
          chains: [chain],
          errorKind: DiagnosticErrorKind.unknown,
          errorDetail: detail,
        );

    expect(value(), value());
    expect(value().hashCode, value().hashCode);
    expect(value(detail: 'timeout'), isNot(value()));
    expect(value(chain: 'DIRECT'), isNot(value()));
  });
}
