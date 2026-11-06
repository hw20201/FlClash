import 'dart:io';

/// Validate a bare hostname/IP. URLs and host:port belong in separate fields.
bool validDiagnosticHost(String host) {
  if (InternetAddress.tryParse(host) != null) return true;
  if (host.length > 253 || host.isEmpty) return false;
  final name = host.endsWith('.') ? host.substring(0, host.length - 1) : host;
  return name
      .split('.')
      .every(
        (part) =>
            part.isNotEmpty &&
            part.length <= 63 &&
            RegExp(
              r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?$',
            ).hasMatch(part),
      );
}

Future<List<String>> systemDnsLookup(String host, Duration timeout) async =>
    (await InternetAddress.lookup(
      host,
    ).timeout(timeout)).map((address) => address.address).toSet().toList();

/// Measures total TCP connect time including any platform name resolution.
Future<Duration> tcpConnectLatency(
  String host,
  int port,
  Duration timeout,
) async {
  final timer = Stopwatch()..start();
  final socket = await Socket.connect(host, port, timeout: timeout);
  timer.stop();
  socket.destroy();
  return timer.elapsed;
}
