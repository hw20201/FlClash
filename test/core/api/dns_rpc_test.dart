import 'dart:async';

import 'package:fl_clash/core/api/core_api.dart';
import 'package:fl_clash/core/api/core_client.dart';
import 'package:fl_clash/core/api/dto.dart';
import 'package:fl_clash/core/api/errors.dart';
import 'package:fl_clash/core/api/rpc_core_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_channel.dart';

void main() {
  late FakeFrameChannel channel;
  late CoreClient client;
  late CoreApi api;
  late JsonMap response;
  JsonMap? error;
  var respond = true;

  setUp(() {
    channel = FakeFrameChannel();
    client = CoreClient(channel);
    api = RpcCoreApi(client);
    response = {
      'rcode': 0,
      'questions': [
        {'name': 'example.com.', 'qtype': 1, 'qclass': 1},
      ],
      'truncated': false,
      'recursionDesired': true,
      'recursionAvailable': true,
      'authenticData': false,
      'checkingDisabled': false,
      'answers': [
        {'name': 'example.com.', 'rtype': 1, 'ttl': 60, 'data': '192.0.2.1'},
      ],
      'authorities': <Object?>[],
      'additionals': <Object?>[],
    };
    error = null;
    respond = true;
    channel.sentListener = (message) {
      switch (message['method']) {
        case 'core.hello':
          channel.answerHello();
        case 'dns.query':
          if (respond) {
            final failure = error;
            if (failure == null) {
              channel.answer(message['id'], response);
            } else {
              channel.fail(message['id'], failure);
            }
          }
      }
    };
    channel.connect();
  });

  tearDown(() async {
    await client.close();
    await channel.close();
  });

  test('queryDns defaults to A and decodes the DNS wire result', () async {
    final DnsQueryResult result = await api.queryDns('example.com');
    expect(channel.lastCall('dns.query')['params'], {
      'name': 'example.com',
      'qtype': 'A',
    });
    expect(result.questions.single.qtype, 1);
    expect(result.answers.single.rtype, 1);
    expect(result.answers.single.data, '192.0.2.1');
    expect(result.answers.single.ttl, 60);
    expect(result.recursionDesired, isTrue);
    expect(result.authorities, isEmpty);
    expect(result.additionals, isEmpty);
    expect(client.pendingCount, 0);
  });

  test('queryDns maps type to qtype without rewriting input', () async {
    await api.queryDns('_service.example.com.', type: 'TXT');
    expect(channel.lastCall('dns.query')['params'], {
      'name': '_service.example.com.',
      'qtype': 'TXT',
    });
  });

  test('DNS negative answers retain rcode as a result', () async {
    response
      ..['rcode'] = 3
      ..['answers'] = <Object?>[];
    final result = await api.queryDns('missing.example.com');
    expect(result.rcode, 3);
    expect(result.answers, isEmpty);
  });

  test('configuration-required conflicts reach the caller', () async {
    error = {
      'code': -32012,
      'message': 'config.apply has not run',
      'data': {'kind': 'conflict', 'state': 'initialized'},
    };
    await expectLater(
      api.queryDns('example.com'),
      throwsA(
        isA<CoreMethodException>()
            .having((error) => error.code, 'code', 'conflict')
            .having(
              (error) => error.message,
              'message',
              'config.apply has not run',
            )
            .having(
              (error) => error.details,
              'details',
              containsPair('state', 'initialized'),
            ),
      ),
    );
  });

  test('an incomplete wire result reports invalid_response', () async {
    response.remove('recursionDesired');
    await expectLater(
      api.queryDns('example.com'),
      throwsA(
        isA<CoreMethodException>().having(
          (error) => error.code,
          'code',
          'invalid_response',
        ),
      ),
    );
  });

  test('pre-cancelled tokens prevent hello and DNS traffic', () async {
    final token = CoreCancellationToken()..cancel();
    await expectLater(
      api.queryDns('example.com', cancellation: token),
      throwsA(
        isA<CoreMethodException>()
            .having((error) => error.code, 'code', 'cancelled')
            .having(
              (error) => error.message,
              'message',
              'Core request cancelled',
            ),
      ),
    );
    expect(channel.sent, isEmpty);
    expect(client.pendingCount, 0);
  });

  test('queryDns forwards cancellation to its request id', () async {
    respond = false;
    final token = CoreCancellationToken();
    final result = api.queryDns('example.com', cancellation: token);
    final checked = expectLater(
      result,
      throwsA(
        isA<CoreMethodException>().having(
          (error) => error.code,
          'code',
          'cancelled',
        ),
      ),
    );
    await pumpEventQueue();
    final id = channel.lastCall('dns.query')['id'];
    token.cancel();
    await checked;
    expect(channel.lastCall(r'$/cancel')['params'], {'id': id});
    expect(client.pendingCount, 0);
  });

  testWidgets('queryDns forwards timeout outside params', (tester) async {
    respond = false;
    const timeout = Duration(milliseconds: 25);
    final result = api.queryDns('example.com', timeout: timeout);
    final checked = expectLater(result, throwsA(isA<TimeoutException>()));
    await tester.pump();
    final call = channel.lastCall('dns.query');
    expect(call['params'], {'name': 'example.com', 'qtype': 'A'});
    await tester.pump(timeout);
    expect(client.pendingCount, 0);
    await checked;
    expect(channel.lastCall(r'$/cancel')['params'], {'id': call['id']});
  });
}
