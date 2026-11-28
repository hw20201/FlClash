import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:fl_clash/core/api/core_api.dart';
import 'package:fl_clash/core/api/core_client.dart';
import 'package:fl_clash/core/api/dto.dart';
import 'package:fl_clash/core/api/errors.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_channel.dart';

class _CancellationChannel extends FakeFrameChannel {
  int connectionWaits = 0;
  void Function(JsonMap message)? onSend;

  @override
  Future<int> waitUntilConnected(Duration timeout) {
    connectionWaits++;
    return super.waitUntilConnected(timeout);
  }

  @override
  void send(List<int> frame) {
    super.send(frame);
    onSend?.call(sent.last);
  }
}

class _CancelOnEncode {
  final CoreCancellationToken token;

  _CancelOnEncode(this.token);

  String toJson() {
    token.cancel();
    return 'encoded';
  }
}

Matcher get _cancelled => isA<CoreMethodException>()
    .having((error) => error.code, 'code', 'cancelled')
    .having((error) => error.message, 'message', 'Core request cancelled');

Matcher get _disconnected => isA<CoreMethodException>().having(
  (error) => error.code,
  'code',
  'transport_disconnected',
);

Future<void> _microtasks() async {
  for (var turn = 0; turn < 30; turn++) {
    await Future<void>.value();
  }
}

Decoder<String> _decodeAndNotify(SendPort port) => (_) {
  port.send(true);
  return 'decoded';
};

void main() {
  late _CancellationChannel channel;
  late CoreClient client;

  setUp(() {
    channel = _CancellationChannel();
    client = CoreClient(channel);
  });

  tearDown(() async {
    await client.close();
    await channel.close();
  });

  Future<void> ready() async {
    channel.connect();
    final result = client.ready();
    await _microtasks();
    channel.answerHello();
    await result;
  }

  Future<String> request(
    CoreCancellationToken token, {
    Duration? timeout,
    Object? params,
  }) => client.call<String>(
    'dns.query',
    params: params ?? {'name': 'example.com', 'qtype': 'A'},
    decode: (result) => result as String,
    timeout: timeout,
    cancellation: token,
  );

  test('a token cancels once and detaches listeners', () {
    final token = CoreCancellationToken();
    var kept = 0;
    var removed = 0;
    void keep() => kept++;
    void remove() => removed++;
    expect(token.isCancelled, isFalse);
    token.addListener(keep);
    token.addListener(remove);
    token.removeListener(remove);
    token.cancel();
    token.cancel();
    expect(token.isCancelled, isTrue);
    expect(kept, 1);
    expect(removed, 0);
    token.addListener(() => kept++);
    expect(kept, 2);
  });

  for (final connected in [false, true]) {
    test('pre-cancellation sends nothing with connected=$connected', () async {
      if (connected) {
        channel.connect();
      }
      final token = CoreCancellationToken()..cancel();
      await expectLater(request(token), throwsA(_cancelled));
      expect(channel.connectionWaits, 0);
      expect(channel.sent, isEmpty);
      expect(client.pendingCount, 0);
    });
  }

  test('cancelled connection waits ignore a late connection', () async {
    final token = CoreCancellationToken();
    final result = request(token);
    final checked = expectLater(result, throwsA(_cancelled));
    expect(channel.connectionWaits, 1);
    token.cancel();
    await checked;
    expect(client.pendingCount, 0);
    channel.connect();
    await _microtasks();
    expect(channel.sent, isEmpty);
  });

  test('cancelled connection waits handle late timeouts', () async {
    final token = CoreCancellationToken();
    final checked = expectLater(
      request(token, timeout: const Duration(milliseconds: 1)),
      throwsA(_cancelled),
    );
    token.cancel();
    await checked;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(channel.sent, isEmpty);
    expect(client.pendingCount, 0);
  });

  test('cancelling as the connection resolves prevents the hello', () async {
    final token = CoreCancellationToken();
    final result = request(token);
    final checked = expectLater(result, throwsA(_cancelled));
    channel.connect();
    token.cancel();
    await checked;
    await _microtasks();
    expect(channel.sent, isEmpty);
  });

  test('a cancelled hello waiter does not stop another caller', () async {
    channel.connect();
    final token = CoreCancellationToken();
    final cancelled = expectLater(request(token), throwsA(_cancelled));
    final other = client.call<String>(
      'core.stats',
      decode: (result) => result as String,
    );
    await _microtasks();
    expect(channel.calls('core.hello'), hasLength(1));
    token.cancel();
    await cancelled;
    expect(channel.calls('dns.query'), isEmpty);
    channel.answerHello();
    await _microtasks();
    final id = channel.lastCall('core.stats')['id'];
    channel.answer(id, 'other');
    expect(await other, 'other');
    expect(channel.calls('dns.query'), isEmpty);
    expect(channel.calls(r'$/cancel'), isEmpty);
    expect(client.pendingCount, 0);
  });

  test('a late hello failure after cancellation is still handled', () async {
    channel.connect();
    final token = CoreCancellationToken();
    final checked = expectLater(request(token), throwsA(_cancelled));
    await _microtasks();
    token.cancel();
    await checked;
    channel.fail(channel.lastCall('core.hello')['id'], {
      'code': -32000,
      'message': 'unavailable',
      'data': {'kind': 'unavailable'},
    });
    await _microtasks();
    expect(channel.calls('dns.query'), isEmpty);
    expect(client.pendingCount, 0);
  });

  test('cancelling during hello send blocks later requests', () async {
    channel.connect();
    final token = CoreCancellationToken();
    channel.onSend = (message) {
      if (message['method'] == 'core.hello') {
        token.cancel();
      }
    };
    await expectLater(request(token), throwsA(_cancelled));
    await client.close();
    await _microtasks();
    expect(channel.calls('dns.query'), isEmpty);
    expect(client.pendingCount, 0);
  });

  test('cancellation targets only its pending request id', () async {
    await ready();
    final token = CoreCancellationToken();
    final checked = expectLater(request(token), throwsA(_cancelled));
    final other = client.call<String>(
      'core.stats',
      decode: (result) => result as String,
    );
    await _microtasks();
    final id = channel.lastCall('dns.query')['id'];
    final otherId = channel.lastCall('core.stats')['id'];
    expect(client.pendingCount, 2);
    token.cancel();
    expect(client.pendingCount, 1);
    await checked;
    expect(channel.lastCall(r'$/cancel')['params'], {'id': id});
    token.cancel();
    channel.answer(id, 'late');
    channel.answer(otherId, 'kept');
    expect(await other, 'kept');
    expect(channel.calls(r'$/cancel'), hasLength(1));
    expect(client.pendingCount, 0);
  });

  test('a response that wins over cancellation stays successful', () async {
    await ready();
    final token = CoreCancellationToken();
    channel.onSend = (message) {
      if (message['method'] == 'dns.query') {
        channel.answer(message['id'], 'answer');
        token.cancel();
      }
    };
    expect(await request(token), 'answer');
    expect(channel.calls(r'$/cancel'), isEmpty);
    expect(client.pendingCount, 0);
  });

  test('cancellation while encoding prevents even an inline send', () async {
    await ready();
    final token = CoreCancellationToken();
    await expectLater(
      request(token, params: {'name': _CancelOnEncode(token)}),
      throwsA(_cancelled),
    );
    expect(channel.calls('dns.query'), isEmpty);
    expect(channel.calls(r'$/cancel'), hasLength(1));
    expect(client.pendingCount, 0);
  });

  test('cancellation wins over a send failure in the same stack', () async {
    await ready();
    final token = CoreCancellationToken();
    channel.onSend = (message) {
      if (message['method'] == 'dns.query') {
        token.cancel();
        throw StateError('send failed after cancellation');
      }
    };
    await expectLater(request(token), throwsA(_cancelled));
    expect(channel.calls(r'$/cancel'), hasLength(1));
    expect(client.pendingCount, 0);
  });

  test('a send failure detaches cancellation from the failed call', () async {
    await ready();
    final token = CoreCancellationToken();
    channel.failSend = true;
    await expectLater(
      request(token),
      throwsA(
        isA<CoreMethodException>().having(
          (error) => error.code,
          'code',
          'transport_error',
        ),
      ),
    );
    channel.failSend = false;
    token.cancel();
    expect(channel.calls(r'$/cancel'), isEmpty);
    expect(client.pendingCount, 0);
  });

  test('a completed call releases a token reused by another call', () async {
    await ready();
    final token = CoreCancellationToken();
    final first = request(token);
    await _microtasks();
    final firstId = channel.lastCall('dns.query')['id'];
    channel.answer(firstId, 'first');
    expect(await first, 'first');
    final second = request(token);
    final checked = expectLater(second, throwsA(_cancelled));
    await _microtasks();
    final secondId = channel.lastCall('dns.query')['id'];
    token.cancel();
    await checked;
    expect(secondId, isNot(firstId));
    expect(channel.calls(r'$/cancel'), hasLength(1));
    expect(channel.lastCall(r'$/cancel')['params'], {'id': secondId});
  });

  testWidgets('timeout keeps its type and starts after hello', (tester) async {
    channel.connect();
    final token = CoreCancellationToken();
    const timeout = Duration(milliseconds: 40);
    final result = request(token, timeout: timeout);
    final checked = expectLater(
      result,
      throwsA(
        isA<TimeoutException>().having(
          (error) => error.duration,
          'duration',
          timeout,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(channel.calls('dns.query'), isEmpty);
    channel.answerHello();
    await tester.pump();
    final id = channel.lastCall('dns.query')['id'];
    await tester.pump(const Duration(milliseconds: 39));
    expect(client.pendingCount, 1);
    await tester.pump(const Duration(milliseconds: 1));
    await checked;
    token.cancel();
    expect(channel.lastCall(r'$/cancel')['params'], {'id': id});
    expect(channel.calls(r'$/cancel'), hasLength(1));
    expect(client.pendingCount, 0);
  });

  testWidgets('cancellation removes the request timer', (tester) async {
    await ready();
    final token = CoreCancellationToken();
    final checked = expectLater(
      request(token, timeout: const Duration(seconds: 1)),
      throwsA(_cancelled),
    );
    await tester.pump();
    token.cancel();
    await checked;
    await tester.pump(const Duration(days: 1));
    expect(channel.calls(r'$/cancel'), hasLength(1));
    expect(client.pendingCount, 0);
  });

  for (final cancelFirst in [true, false]) {
    test('close and cancel settle once: cancelFirst=$cancelFirst', () async {
      await ready();
      final token = CoreCancellationToken();
      final result = request(token);
      final checked = expectLater(
        result,
        throwsA(cancelFirst ? _cancelled : _disconnected),
      );
      await _microtasks();
      final id = channel.lastCall('dns.query')['id'];
      if (cancelFirst) {
        token.cancel();
      }
      await client.close();
      token.cancel();
      channel.answer(id, 'late');
      await checked;
      expect(client.pendingCount, 0);
      expect(channel.calls(r'$/cancel'), hasLength(cancelFirst ? 1 : 0));
    });
  }

  test('cancelled queued requests are never sent', () async {
    await ready();
    channel.sentListener = (message) {
      if (message['method'] == 'mitm.readModule') {
        channel.answer(message['id'], 'large');
      }
    };
    final large = client.call<String>(
      'mitm.readModule',
      params: {'text': 'x' * coreOffloadBytes},
      decode: (result) => result as String,
    );
    final token = CoreCancellationToken();
    final checked = expectLater(request(token), throwsA(_cancelled));
    await _microtasks();
    expect(channel.calls('dns.query'), isEmpty);
    expect(client.pendingCount, 2);
    token.cancel();
    await checked;
    expect(await large, 'large');
    await pumpEventQueue();
    expect(channel.calls('dns.query'), isEmpty);
    expect(channel.calls(r'$/cancel'), hasLength(1));
    expect(client.pendingCount, 0);
  });

  test('queued send failures after cancellation are handled', () async {
    await ready();
    final large = client.call<String>(
      'mitm.readModule',
      params: {'text': 'x' * coreOffloadBytes},
      decode: (result) => result as String,
    );
    final failed = expectLater(
      large,
      throwsA(
        isA<CoreMethodException>().having(
          (error) => error.code,
          'code',
          'transport_error',
        ),
      ),
    );
    final token = CoreCancellationToken();
    final cancelled = expectLater(request(token), throwsA(_cancelled));
    await _microtasks();
    channel.failSend = true;
    token.cancel();
    await cancelled;
    await failed;
    await pumpEventQueue();
    expect(channel.calls('dns.query'), isEmpty);
    expect(client.pendingCount, 0);
  });

  test('late large responses cannot settle cancelled calls', () async {
    await ready();
    final token = CoreCancellationToken();
    final decoded = ReceivePort();
    addTearDown(decoded.close);
    final result = client.call<String>(
      'dns.query',
      decode: _decodeAndNotify(decoded.sendPort),
      cancellation: token,
    );
    final checked = expectLater(result, throwsA(_cancelled));
    await _microtasks();
    final id = channel.lastCall('dns.query')['id'];
    channel.pushRaw(
      Uint8List.fromList(
        utf8.encode(
          json.encode({
            'jsonrpc': '2.0',
            'id': id,
            'result': 'x' * coreOffloadBytes,
          }),
        ),
      ),
    );
    token.cancel();
    await checked;
    await decoded.first.timeout(const Duration(seconds: 5));
    await pumpEventQueue();
    expect(client.pendingCount, 0);
    expect(channel.calls(r'$/cancel'), hasLength(1));
  });
}
