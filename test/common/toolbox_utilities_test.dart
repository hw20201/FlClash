import 'dart:io';

import 'package:fl_clash/common/toolbox_utilities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'IPv4 CIDR handles network, point-to-point, host and default routes',
    () {
      expect(ipv4Subnet('192.168.1.99/24'), {
        'network': '192.168.1.0/24',
        'mask': '255.255.255.0',
        'lastAddress': '192.168.1.255',
        'firstHost': '192.168.1.1',
        'lastHost': '192.168.1.254',
        'hosts': '254',
      });
      expect(ipv4Subnet('10.0.0.1/31')['hosts'], '2');
      expect(ipv4Subnet('10.0.0.1/31')['firstHost'], '10.0.0.0');
      expect(ipv4Subnet('10.0.0.1/32')['hosts'], '1');
      expect(ipv4Subnet('10.0.0.1/32')['lastHost'], '10.0.0.1');
      expect(ipv4Subnet('10.0.0.1/0')['mask'], '0.0.0.0');
      expect(ipv4Subnet('10.0.0.1/0')['hosts'], '4294967294');
      for (final bad in [
        '',
        'a/24',
        '1.2.3.4/33',
        '256.0.0.0/24',
        '1.2.3/24',
        '::1/128',
        '1.2.3.4/-1',
      ]) {
        expect(() => ipv4Subnet(bad), throwsFormatException, reason: bad);
      }
    },
  );
  test('HEAD returns headers without following a redirect', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final methods = <String>[];
    server.listen((request) {
      methods.add(request.method);
      request.response.statusCode = 302;
      request.response.headers.set('location', '/should-not-follow');
      request.response.headers.set('x-toolbox', 'tested');
      request.response.close();
    });
    final result = await inspectHttpHeaders(
      Uri.parse('http://127.0.0.1:${server.port}'),
      const Duration(seconds: 2),
    );
    expect(result, contains('HTTP 302'));
    expect(result, contains('x-toolbox: tested'));
    expect(methods, ['HEAD']);
  });
  test('rejects non-HTTP and embedded credentials', () async {
    for (final url in ['file:///tmp/file', 'https://user:secret@example.com']) {
      await expectLater(
        inspectHttpHeaders(Uri.parse(url), const Duration(seconds: 1)),
        throwsFormatException,
      );
    }
  });
}
