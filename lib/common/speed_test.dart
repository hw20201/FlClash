import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// A Speedtest.net server from the public server list.
class SpeedtestServer {
  const SpeedtestServer({
    required this.id,
    required this.name,
    required this.country,
    required this.sponsor,
    required this.url,
    required this.distanceKm,
  });

  final String id;
  final String name;
  final String country;
  final String sponsor;
  final String url;
  final double distanceKm;

  /// The directory holding latency.txt and the random images.
  String get base => url.substring(0, url.lastIndexOf('/'));
}

class SpeedtestResult {
  const SpeedtestResult({
    required this.server,
    required this.latency,
    required this.downloadMbps,
    required this.uploadMbps,
  });

  final SpeedtestServer server;
  final Duration latency;
  final double downloadMbps;
  final double uploadMbps;
}

/// Parse the speedtest.net server-list JSON into servers.
List<SpeedtestServer> parseSpeedtestServers(String json) {
  final list = jsonDecode(json) as List;
  return [
    for (final entry in list)
      if (entry is Map<String, dynamic>)
        SpeedtestServer(
          id: '${entry['id']}',
          name: '${entry['name']}',
          country: '${entry['country']}',
          sponsor: '${entry['sponsor']}',
          url: '${entry['url']}',
          distanceKm: double.tryParse('${entry['distance']}') ?? 0,
        ),
  ];
}

Future<({double lat, double lon})> _clientLocation(
  HttpClient client,
  Duration timeout,
) async {
  final request = await client.getUrl(
    Uri.parse('https://www.speedtest.net/speedtest-config.php'),
  );
  final response = await request.close().timeout(timeout);
  final body = await response.transform(utf8.decoder).join().timeout(timeout);
  final lat = RegExp(r'lat="(-?[\d.]+)"').firstMatch(body)?.group(1);
  final lon = RegExp(r'lon="(-?[\d.]+)"').firstMatch(body)?.group(1);
  if (lat == null || lon == null) {
    throw const FormatException('Could not read location from speedtest.net');
  }
  return (lat: double.parse(lat), lon: double.parse(lon));
}

Future<List<SpeedtestServer>> _nearbyServers(
  HttpClient client,
  double lat,
  double lon,
  Duration timeout,
) async {
  final uri = Uri.parse(
    'https://www.speedtest.net/api/js/servers'
    '?engine=js&https_functional=true&limit=10&lat=$lat&lon=$lon',
  );
  final request = await client.getUrl(uri);
  final response = await request.close().timeout(timeout);
  final body = await response.transform(utf8.decoder).join().timeout(timeout);
  return parseSpeedtestServers(body);
}

/// Best of three latency.txt fetches against one server.
Future<Duration> speedtestLatency(
  HttpClient client,
  SpeedtestServer server,
  Duration timeout,
) async {
  final uri = Uri.parse(
    '${server.base}/latency.txt?x=${Random().nextInt(1 << 30)}',
  );
  var best = Duration.zero;
  for (var i = 0; i < 3; i++) {
    final timer = Stopwatch()..start();
    final request = await client.getUrl(uri);
    final response = await request.close().timeout(timeout);
    if (response.statusCode != 200) {
      throw HttpException('Latency check failed: ${response.statusCode}');
    }
    await response.drain<void>().timeout(timeout);
    timer.stop();
    if (best == Duration.zero || timer.elapsed < best) {
      best = timer.elapsed;
    }
  }
  return best;
}

/// Download speed in Mbps from a server's random images.
Future<double> speedtestDownload(
  HttpClient client,
  SpeedtestServer server,
  Duration timeout,
) async {
  var totalBytes = 0;
  final timer = Stopwatch()..start();
  for (final size in [2000, 4000]) {
    final uri = Uri.parse(
      '${server.base}/random${size}x$size.jpg?x=${Random().nextInt(1 << 30)}',
    );
    final request = await client.getUrl(uri);
    final response = await request.close().timeout(timeout);
    if (response.statusCode != 200) {
      throw HttpException('Download failed: ${response.statusCode}');
    }
    await for (final chunk in response.timeout(timeout)) {
      totalBytes += chunk.length;
    }
  }
  timer.stop();
  return totalBytes * 8 / (timer.elapsedMicroseconds / 1e6) / 1e6;
}

/// Upload speed in Mbps by posting 1 MB to a server's upload endpoint.
Future<double> speedtestUpload(
  HttpClient client,
  SpeedtestServer server,
  Duration timeout,
) async {
  final payload = List<int>.generate(1024 * 1024, (i) => 48 + (i % 74));
  final timer = Stopwatch()..start();
  final request = await client.postUrl(Uri.parse(server.url));
  request.headers.contentType = ContentType.binary;
  request.contentLength = payload.length;
  request.add(payload);
  final response = await request.close().timeout(timeout);
  await response.drain<void>().timeout(timeout);
  timer.stop();
  return payload.length * 8 / (timer.elapsedMicroseconds / 1e6) / 1e6;
}

/// Measure latency, download and upload against the best nearby
/// Speedtest.net server. Throws when no server answers.
Future<SpeedtestResult> runSpeedtest({
  Duration timeout = const Duration(seconds: 90),
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final location = await _clientLocation(
      client,
      const Duration(seconds: 10),
    ).timeout(timeout);
    final servers = await _nearbyServers(
      client,
      location.lat,
      location.lon,
      const Duration(seconds: 10),
    ).timeout(timeout);
    if (servers.isEmpty) {
      throw const FormatException('No speedtest.net servers found');
    }
    SpeedtestServer? best;
    Duration? bestLatency;
    for (final server in servers.take(5)) {
      try {
        final latency = await speedtestLatency(
          client,
          server,
          const Duration(seconds: 8),
        ).timeout(timeout);
        if (bestLatency == null || latency < bestLatency) {
          best = server;
          bestLatency = latency;
        }
      } catch (_) {
        continue;
      }
    }
    if (best == null || bestLatency == null) {
      throw const FormatException('No speedtest.net server answered');
    }
    final download = await speedtestDownload(
      client,
      best,
      const Duration(seconds: 30),
    ).timeout(timeout);
    final upload = await speedtestUpload(
      client,
      best,
      const Duration(seconds: 30),
    ).timeout(timeout);
    return SpeedtestResult(
      server: best,
      latency: bestLatency,
      downloadMbps: download,
      uploadMbps: upload,
    );
  } finally {
    client.close(force: true);
  }
}
