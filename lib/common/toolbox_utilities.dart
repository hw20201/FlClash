import 'dart:io';

/// Local IPv4 subnet arithmetic. No DNS or network traffic is performed.
Map<String, String> ipv4Subnet(String cidr) {
  final parts = cidr.trim().split('/');
  if (parts.length != 2)
    throw const FormatException('Use IPv4/prefix, e.g. 192.168.1.10/24');
  final octets = parts[0].split('.');
  final prefix = int.tryParse(parts[1]);
  if (octets.length != 4 ||
      prefix == null ||
      prefix < 0 ||
      prefix > 32 ||
      octets.any(
        (s) => !RegExp(r'^\d{1,3}$').hasMatch(s) || int.parse(s) > 255,
      )) {
    throw const FormatException('Invalid IPv4 CIDR');
  }
  final address = octets.fold<int>(0, (n, s) => (n << 8) | int.parse(s));
  final mask = prefix == 0 ? 0 : (0xffffffff << (32 - prefix)) & 0xffffffff;
  final network = address & mask;
  final broadcast = network | (0xffffffff ^ mask);
  String ip(int n) => [24, 16, 8, 0].map((s) => (n >> s) & 255).join('.');
  final total = 1 << (32 - prefix);
  // RFC 3021 point-to-point /31 and host routes /32 have no broadcast host.
  return {
    'network': '${ip(network)}/$prefix',
    'mask': ip(mask),
    'lastAddress': ip(broadcast),
    'firstHost': ip(prefix >= 31 ? network : network + 1),
    'lastHost': ip(prefix >= 31 ? broadcast : broadcast - 1),
    'hosts': '${prefix >= 31 ? total : total - 2}',
  };
}

/// Local interface addresses only; this does not discover the public exit IP.
Future<List<String>> localInterfaceAddresses() async {
  final interfaces = await NetworkInterface.list(
    includeLinkLocal: true,
    includeLoopback: false,
  );
  return [
    for (final interface in interfaces)
      for (final address in interface.addresses)
        '${interface.name} · ${address.type.name}\n${address.address}',
  ];
}

/// HEAD only, no body download, normal TLS validation and no redirects.
/// Caller controls the destination; no background traffic or telemetry.
Future<String> inspectHttpHeaders(Uri uri, Duration timeout) async {
  if (!['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException('HTTP(S) URL without credentials required');
  }
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    return await (() async {
      final request = await client.openUrl('HEAD', uri);
      request.followRedirects = false;
      final response = await request.close();
      final lines = <String>[
        'HTTP ${response.statusCode} ${response.reasonPhrase}',
      ];
      response.headers.forEach(
        (name, values) => lines.add('$name: ${values.join(', ')}'),
      );
      return lines.join('\n');
    })().timeout(timeout);
  } finally {
    client.close(force: true);
  }
}
