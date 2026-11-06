import 'dart:io';

import 'package:fl_clash/common/network_toolbox.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('validates hostnames, IPs and rejects URLs and ports', () {
    for (final host in ['example.com', 'localhost', '127.0.0.1', '::1']) {
      expect(validDiagnosticHost(host), isTrue, reason: host);
    }
    for (final host in [
      '',
      'example.com:443',
      'https://example.com',
      'a b',
      '-bad.example',
    ]) {
      expect(validDiagnosticHost(host), isFalse, reason: host);
    }
  });
  test('system DNS resolves localhost', () async {
    expect(
      await systemDnsLookup('localhost', const Duration(seconds: 2)),
      isNotEmpty,
    );
  });
  test('TCP connects to a local listener and reports refused ports', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    final duration = await tcpConnectLatency(
      '127.0.0.1',
      port,
      const Duration(seconds: 2),
    );
    expect(duration, greaterThanOrEqualTo(Duration.zero));
    await server.close();
    await expectLater(
      tcpConnectLatency('127.0.0.1', port, const Duration(seconds: 2)),
      throwsA(isA<SocketException>()),
    );
  });
}
