import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/speed_test.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SpeedtestServer.base strips the upload file', () {
    const server = SpeedtestServer(
      id: '1',
      name: 'Test',
      country: 'Testland',
      sponsor: 'Test',
      url: 'http://example.com:8080/speedtest/upload.php',
      distanceKm: 3,
    );
    expect(server.base, 'http://example.com:8080/speedtest');
  });

  test('parseSpeedtestServers reads the list JSON', () {
    final servers = parseSpeedtestServers(
      jsonEncode([
        {
          'id': '1',
          'name': 'Dallas, TX',
          'country': 'United States',
          'sponsor': 'Test',
          'url': 'http://a:8080/speedtest/upload.php',
          'distance': 8,
        },
        {
          'id': '2',
          'name': 'Austin, TX',
          'country': 'United States',
          'sponsor': 'Test',
          'url': 'http://b:8080/speedtest/upload.php',
          'distance': '12',
        },
      ]),
    );
    expect(servers.length, 2);
    expect(servers.first.name, 'Dallas, TX');
    expect(servers.first.distanceKm, 8);
    expect(servers.last.distanceKm, 12);
  });

  test('latency, download and upload run against a local server', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      if (request.method == 'POST') {
        await request.drain<void>();
        request.response.write('ok');
      } else if (request.uri.path.endsWith('latency.txt')) {
        request.response.write('test=test');
      } else {
        request.response.add(List<int>.filled(4096, 65));
      }
      await request.response.close();
    });
    final target = SpeedtestServer(
      id: '1',
      name: 'Local',
      country: 'Test',
      sponsor: 'Test',
      url: 'http://127.0.0.1:${server.port}/speedtest/upload.php',
      distanceKm: 0,
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final latency = await speedtestLatency(
      client,
      target,
      const Duration(seconds: 5),
    );
    expect(latency.inMicroseconds, greaterThan(0));
    final download = await speedtestDownload(
      client,
      target,
      const Duration(seconds: 5),
    );
    expect(download, greaterThan(0));
    final upload = await speedtestUpload(
      client,
      target,
      const Duration(seconds: 10),
    );
    expect(upload, greaterThan(0));
  });
}
