import 'dart:convert';
import 'dart:io';

class IpInfo {
  const IpInfo({
    required this.ip,
    this.country,
    this.region,
    this.city,
    this.isp,
    this.org,
    this.asn,
  });

  final String ip;
  final String? country;
  final String? region;
  final String? city;
  final String? isp;
  final String? org;
  final String? asn;
}

/// Parse an ip-api.com response into an [IpInfo]. Throws on a failed lookup.
IpInfo parseIpInfo(Map<String, dynamic> data) {
  if (data['status'] != 'success') {
    throw FormatException('${data['message'] ?? 'Lookup failed'}');
  }
  return IpInfo(
    ip: '${data['query']}',
    country: data['country'] as String?,
    region: data['regionName'] as String?,
    city: data['city'] as String?,
    isp: data['isp'] as String?,
    org: data['org'] as String?,
    asn: data['as'] as String?,
  );
}

/// The device's public (exit) IP, as seen by a public echo service.
Future<String> publicIp(Duration timeout) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client.getUrl(
      Uri.parse('https://api.ipify.org?format=json'),
    );
    final response = await request.close().timeout(timeout);
    final body = await response.transform(utf8.decoder).join().timeout(timeout);
    final ip = (jsonDecode(body) as Map<String, dynamic>)['ip'] as String?;
    if (ip == null || ip.isEmpty) {
      throw const FormatException('Could not read public IP');
    }
    return ip;
  } finally {
    client.close(force: true);
  }
}

/// Geolocation and network owner for an IP or a hostname. An empty query
/// looks up the device's own public IP.
Future<IpInfo> lookupIp(
  String query,
  Duration timeout, {
  String geoBaseUrl = 'http://ip-api.com',
}) async {
  final host = query.trim();
  final ip = host.isEmpty
      ? await publicIp(timeout)
      : InternetAddress.tryParse(host)?.address ??
            await _resolve(host, timeout);
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final uri = Uri.parse(
      '$geoBaseUrl/json/$ip'
      '?fields=status,message,country,regionName,city,isp,org,as,query',
    );
    final request = await client.getUrl(uri);
    final response = await request.close().timeout(timeout);
    final body = await response.transform(utf8.decoder).join().timeout(timeout);
    return parseIpInfo(jsonDecode(body) as Map<String, dynamic>);
  } finally {
    client.close(force: true);
  }
}

Future<String> _resolve(String host, Duration timeout) async {
  final addresses = await InternetAddress.lookup(host).timeout(timeout);
  if (addresses.isEmpty) {
    throw FormatException('Could not resolve $host');
  }
  return addresses.first.address;
}
