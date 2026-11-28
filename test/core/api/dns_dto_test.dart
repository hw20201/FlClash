import 'package:fl_clash/core/api/dto.dart';
import 'package:flutter_test/flutter_test.dart';

JsonMap _response() => {
  'rcode': 0,
  'questions': [
    {'name': 'example.com.', 'qtype': 28, 'qclass': 1},
  ],
  'truncated': true,
  'recursionDesired': false,
  'recursionAvailable': true,
  'authenticData': false,
  'checkingDisabled': true,
  'answers': [
    {'name': 'example.com.', 'rtype': 28, 'ttl': 60, 'data': '2001:db8::1'},
  ],
  'authorities': [
    {'name': 'example.com.', 'rtype': 2, 'ttl': 120, 'data': 'ns.example.com.'},
  ],
  'additionals': [
    {'name': 'ns.example.com.', 'rtype': 1, 'ttl': 0, 'data': '192.0.2.1'},
  ],
};

void main() {
  test('reads every query field and keeps the DNS sections separate', () {
    final result = DnsQueryResult.fromJson(_response());
    expect(result.rcode, 0);
    expect(result.questions.single.name, 'example.com.');
    expect(result.questions.single.qtype, 28);
    expect(result.questions.single.qclass, 1);
    expect(result.truncated, isTrue);
    expect(result.recursionDesired, isFalse);
    expect(result.recursionAvailable, isTrue);
    expect(result.authenticData, isFalse);
    expect(result.checkingDisabled, isTrue);
    expect(result.answers.single.name, 'example.com.');
    expect(result.answers.single.rtype, 28);
    expect(result.answers.single.ttl, 60);
    expect(result.answers.single.data, '2001:db8::1');
    expect(result.authorities.single.rtype, 2);
    expect(result.authorities.single.data, 'ns.example.com.');
    expect(result.additionals.single.rtype, 1);
    expect(result.additionals.single.ttl, 0);
    expect(result.additionals.single.data, '192.0.2.1');
  });

  test('retains presentation data and numeric types without guessing them', () {
    const data = r'"a; b" "\000"';
    final record = DnsRecordDto.fromJson({
      'name': '_service.example.com.',
      'rtype': 65535,
      'ttl': 4294967295,
      'data': data,
    });
    final question = DnsQuestionDto.fromJson({
      'name': '_service.example.com.',
      'qtype': 65535,
      'qclass': 255,
    });
    expect(record.rtype, 65535);
    expect(record.ttl, 4294967295);
    expect(record.data, data);
    expect(question.qtype, 65535);
    expect(question.qclass, 255);
  });

  test('keeps a negative DNS response as a result with its authority', () {
    final json = _response()
      ..['rcode'] = 3
      ..['answers'] = <Object?>[]
      ..['additionals'] = <Object?>[];
    final result = DnsQueryResult.fromJson(json);
    expect(result.rcode, 3);
    expect(result.answers, isEmpty);
    expect(result.authorities.single.name, 'example.com.');
    expect(result.additionals, isEmpty);
  });

  for (final field in _response().keys) {
    test('does not invent the required $field field', () {
      final json = _response()..remove(field);
      expect(() => DnsQueryResult.fromJson(json), throwsA(isA<TypeError>()));
    });
  }

  test('rejects a malformed record instead of silently dropping it', () {
    final json = _response()
      ..['answers'] = [
        {'name': 'example.com.', 'rtype': 'AAAA', 'ttl': 1, 'data': '::1'},
      ];
    expect(() => DnsQueryResult.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('supports const DTO construction with the complete public contract', () {
    const result = DnsQueryResult(
      rcode: 0,
      questions: [DnsQuestionDto(name: 'a.test.', qtype: 1, qclass: 1)],
      truncated: false,
      recursionDesired: true,
      recursionAvailable: true,
      authenticData: true,
      checkingDisabled: false,
      answers: [
        DnsRecordDto(name: 'a.test.', rtype: 1, ttl: 1, data: '192.0.2.2'),
      ],
      authorities: [],
      additionals: [],
    );
    expect(result.answers.single.data, '192.0.2.2');
    expect(result.authenticData, isTrue);
  });
}
