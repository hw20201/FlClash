import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/ip_lookup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseIpInfo reads a success response', () {
    final info = parseIpInfo({
      'status': 'success',
      'query': '1.2.3.4',
      'country': 'United States',
      'regionName': 'Texas',
      'city': 'Dallas',
      'isp': 'Test ISP',
      'org': 'Test Org',
      'as': 'AS12345 Test',
    });
    expect(info.ip, '1.2.3.4');
    expect(info.country, 'United States');
    expect(info.city, 'Dallas');
    expect(info.asn, 'AS12345 Test');
  });

  test('parseIpInfo throws on a failed lookup', () {
    expect(
      () => parseIpInfo({'status': 'fail', 'message': 'invalid query'}),
      throwsFormatException,
    );
  });

  test('lookupIp queries a local geo service', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'status': 'success',
          'query': '1.2.3.4',
          'country': 'United States',
          'regionName': 'Texas',
          'city': 'Dallas',
          'isp': 'Test ISP',
          'org': 'Test Org',
          'as': 'AS12345 Test',
        }),
      );
      await request.response.close();
    });
    final info = await lookupIp(
      '1.2.3.4',
      const Duration(seconds: 5),
      geoBaseUrl: 'http://127.0.0.1:${server.port}',
    );
    expect(info.ip, '1.2.3.4');
    expect(info.isp, 'Test ISP');
  });
}
