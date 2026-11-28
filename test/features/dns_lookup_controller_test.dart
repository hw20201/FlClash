import 'dart:async';

import 'package:fl_clash/core/api/cancellation.dart';
import 'package:fl_clash/core/api/dto.dart';
import 'package:fl_clash/core/api/errors.dart';
import 'package:fl_clash/features/dns_lookup/controller.dart';
import 'package:flutter_test/flutter_test.dart';

DnsQueryResult _result() => const DnsQueryResult(
  rcode: 0,
  questions: [DnsQuestionDto(name: 'example.com', qtype: 1, qclass: 1)],
  truncated: false,
  recursionDesired: true,
  recursionAvailable: true,
  authenticData: false,
  checkingDisabled: false,
  answers: [
    DnsRecordDto(name: 'example.com', rtype: 1, ttl: 60, data: '192.0.2.1'),
  ],
  authorities: [],
  additionals: [],
);

void main() {
  test('normalizes ASCII, Punycode, service labels, and root names', () async {
    final calls = <(String, String)>[];
    final controller = DnsLookupController(
      query: (name, type, _) async {
        calls.add((name, type));
        return _result();
      },
    );
    addTearDown(controller.dispose);

    for (final (input, expected) in [
      ('  Example.COM.  ', 'example.com.'),
      ('XN--BCHER-KVA.example', 'xn--bcher-kva.example'),
      ('_sip._tcp.Example.COM', '_sip._tcp.example.com'),
      ('.', '.'),
    ]) {
      await controller.query(input, 'AAAA', available: true);
      expect(controller.state.phase, DnsLookupPhase.complete);
      expect(controller.state.name, expected);
      expect(controller.state.type, 'AAAA');
    }

    expect(calls, [
      ('example.com.', 'AAAA'),
      ('xn--bcher-kva.example', 'AAAA'),
      ('_sip._tcp.example.com', 'AAAA'),
      ('.', 'AAAA'),
    ]);
  });

  test(
    'rejects malformed names and unsupported record types before querying',
    () async {
      var calls = 0;
      final controller = DnsLookupController(
        query: (_, _, _) async {
          calls++;
          return _result();
        },
      );
      addTearDown(controller.dispose);

      for (final input in [
        '',
        'https://example.com',
        'example.com:53',
        'example.com/path',
        'bücher.example',
        'a..example',
        '-bad.example',
        'bad-.example',
        '${'a' * 64}.example',
      ]) {
        await controller.query(input, 'A', available: true);
        expect(controller.state.phase, DnsLookupPhase.invalid, reason: input);
      }
      await controller.query('example.com', 'UNKNOWN', available: true);

      expect(controller.state.phase, DnsLookupPhase.invalid);
      expect(calls, 0);
    },
  );

  test('unavailable runtime prevents a query', () async {
    var calls = 0;
    final controller = DnsLookupController(
      query: (_, _, _) async {
        calls++;
        return _result();
      },
    );
    addTearDown(controller.dispose);

    await controller.query('example.com', 'A', available: false);

    expect(controller.state.phase, DnsLookupPhase.unavailable);
    expect(calls, 0);
  });

  test('one in-flight query ignores repeated submissions', () async {
    final reply = Completer<DnsQueryResult>();
    final tokens = <CoreCancellationToken>[];
    var calls = 0;
    final controller = DnsLookupController(
      query: (_, _, cancellation) {
        calls++;
        tokens.add(cancellation);
        return reply.future;
      },
    );
    addTearDown(controller.dispose);

    final first = controller.query('example.com', 'A', available: true);
    await controller.query('other.example', 'AAAA', available: true);
    expect(controller.state.phase, DnsLookupPhase.loading);
    expect(calls, 1);

    reply.complete(_result());
    await first;
    expect(controller.state.phase, DnsLookupPhase.complete);
    expect(controller.state.name, 'example.com');
    expect(controller.state.canCopy, isTrue);
    expect(controller.state.elapsed, isNotNull);
    expect(controller.state.checkedAt, isNotNull);
    expect(tokens.single.isCancelled, isFalse);
  });

  test(
    'classifies timeout and Core errors without retaining raw messages',
    () async {
      final cases = <(Object, DnsLookupPhase)>[
        (TimeoutException('secret upstream'), DnsLookupPhase.timedOut),
        (
          const CoreMethodException(code: 'cancelled', message: 'token=secret'),
          DnsLookupPhase.cancelled,
        ),
        (
          const CoreMethodException(
            code: 'transport_disconnected',
            message: 'secret endpoint',
          ),
          DnsLookupPhase.unavailable,
        ),
        (
          const CoreMethodException(
            code: 'transport_error',
            message: 'secret endpoint',
          ),
          DnsLookupPhase.unavailable,
        ),
        (
          const CoreMethodException(
            code: 'core_unavailable',
            message: 'secret endpoint',
          ),
          DnsLookupPhase.unavailable,
        ),
        (
          const CoreMethodException(
            code: 'not_configured',
            message: 'sensitive',
          ),
          DnsLookupPhase.unavailable,
        ),
        (
          const CoreMethodException(
            code: 'not_initialized',
            message: 'sensitive',
          ),
          DnsLookupPhase.unavailable,
        ),
        (
          const CoreMethodException(code: 'conflict', message: 'sensitive'),
          DnsLookupPhase.unavailable,
        ),
        (
          const CoreMethodException(code: 'invalid_params', message: 'secret'),
          DnsLookupPhase.invalid,
        ),
        (
          const CoreMethodException(code: 'invalid_field', message: 'secret'),
          DnsLookupPhase.invalid,
        ),
        (
          const CoreMethodException(code: 'internal', message: 'token=secret'),
          DnsLookupPhase.failed,
        ),
        (StateError('password=secret'), DnsLookupPhase.failed),
      ];

      for (final (error, phase) in cases) {
        final controller = DnsLookupController(
          query: (_, _, _) => Future<DnsQueryResult>.error(error),
        );

        await controller.query('example.com', 'A', available: true);

        expect(controller.state.phase, phase, reason: '$error');
        expect(controller.state.result, isNull);
        expect(controller.state.checkedAt, isNotNull);
        controller.dispose();
      }
    },
  );

  test(
    'cancel and reset suppress late replies; invalidate marks results stale',
    () async {
      final cancelReply = Completer<DnsQueryResult>();
      late CoreCancellationToken cancelToken;
      final cancelled = DnsLookupController(
        query: (_, _, token) {
          cancelToken = token;
          return cancelReply.future;
        },
      );
      final pendingCancel = cancelled.query(
        'example.com',
        'A',
        available: true,
      );
      cancelled.cancel();
      expect(cancelToken.isCancelled, isTrue);
      expect(cancelled.state.phase, DnsLookupPhase.cancelled);
      cancelReply.complete(_result());
      await pendingCancel;
      expect(cancelled.state.phase, DnsLookupPhase.cancelled);
      cancelled.dispose();

      final resetReply = Completer<DnsQueryResult>();
      late CoreCancellationToken resetToken;
      final reset = DnsLookupController(
        query: (_, _, token) {
          resetToken = token;
          return resetReply.future;
        },
      );
      final pendingReset = reset.query('example.com', 'A', available: true);
      reset.reset();
      expect(resetToken.isCancelled, isTrue);
      resetReply.complete(_result());
      await pendingReset;
      expect(reset.state.phase, DnsLookupPhase.idle);
      expect(reset.state.result, isNull);

      final staleReply = Completer<DnsQueryResult>();
      late CoreCancellationToken staleToken;
      final stale = DnsLookupController(
        query: (_, _, token) {
          staleToken = token;
          return staleReply.future;
        },
      );
      final pendingStale = stale.query('example.com', 'A', available: true);
      stale.invalidate();
      expect(staleToken.isCancelled, isTrue);
      expect(stale.state.phase, DnsLookupPhase.stale);
      staleReply.complete(_result());
      await pendingStale;
      expect(stale.state.phase, DnsLookupPhase.stale);
      expect(stale.state.result, isNull);
      reset.dispose();
      stale.dispose();
    },
  );

  test('dispose cancels the request and ignores its late response', () async {
    final reply = Completer<DnsQueryResult>();
    late CoreCancellationToken token;
    final controller = DnsLookupController(
      query: (_, _, cancellation) {
        token = cancellation;
        return reply.future;
      },
    );
    var notifications = 0;
    controller.addListener(() => notifications++);

    final pending = controller.query('example.com', 'A', available: true);
    final loadingNotifications = notifications;
    controller.dispose();
    expect(token.isCancelled, isTrue);
    reply.complete(_result());
    await pending;

    expect(notifications, loadingNotifications);
  });

  test('allows retry after an internal failure', () async {
    var calls = 0;
    final controller = DnsLookupController(
      query: (_, _, _) async {
        if (++calls == 1) {
          throw const CoreMethodException(
            code: 'internal',
            message: 'sensitive detail',
          );
        }
        return _result();
      },
    );
    addTearDown(controller.dispose);

    await controller.query('example.com', 'A', available: true);
    expect(controller.state.phase, DnsLookupPhase.failed);
    await controller.query('example.com', 'A', available: true);

    expect(controller.state.phase, DnsLookupPhase.complete);
    expect(calls, 2);
  });
}
