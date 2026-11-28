import 'dart:async';

import 'package:fl_clash/core/api/core_api.dart';
import 'package:fl_clash/core/api/dto.dart';
import 'package:fl_clash/core/api/errors.dart';
import 'package:flutter/foundation.dart';

const dnsLookupTypes = [
  'A',
  'AAAA',
  'CNAME',
  'MX',
  'TXT',
  'NS',
  'SOA',
  'PTR',
  'SRV',
  'CAA',
  'HTTPS',
  'SVCB',
];

String dnsRecordTypeLabel(int type) => switch (type) {
  1 => 'A',
  2 => 'NS',
  5 => 'CNAME',
  6 => 'SOA',
  12 => 'PTR',
  15 => 'MX',
  16 => 'TXT',
  28 => 'AAAA',
  33 => 'SRV',
  64 => 'SVCB',
  65 => 'HTTPS',
  257 => 'CAA',
  _ => 'TYPE$type',
};

String dnsResponseCodeLabel(int code) => switch (code) {
  0 => 'NOERROR',
  1 => 'FORMERR',
  2 => 'SERVFAIL',
  3 => 'NXDOMAIN',
  4 => 'NOTIMP',
  5 => 'REFUSED',
  _ => 'RCODE$code',
};

String? normalizeDnsLookupName(String input) {
  final name = input.trim().toLowerCase();
  if (name == '.') return name;
  final bare = name.endsWith('.') ? name.substring(0, name.length - 1) : name;
  if (bare.isEmpty || bare.length > 253) return null;
  final labelPattern = RegExp(r'^[a-z0-9_](?:[a-z0-9_-]*[a-z0-9_])?$');
  for (final label in bare.split('.')) {
    if (label.length > 63 || !labelPattern.hasMatch(label)) return null;
  }
  return name;
}

enum DnsLookupPhase {
  idle,
  loading,
  complete,
  invalid,
  unavailable,
  timedOut,
  failed,
  cancelled,
  stale,
}

@immutable
class DnsLookupState {
  const DnsLookupState({
    this.phase = DnsLookupPhase.idle,
    this.name = '',
    this.type = 'A',
    this.result,
    this.elapsed,
    this.checkedAt,
  });

  final DnsLookupPhase phase;
  final String name;
  final String type;
  final DnsQueryResult? result;
  final Duration? elapsed;
  final DateTime? checkedAt;

  bool get isLoading => phase == DnsLookupPhase.loading;
  bool get canCopy => phase == DnsLookupPhase.complete && result != null;
}

typedef DnsLookupRunner =
    Future<DnsQueryResult> Function(
      String name,
      String type,
      CoreCancellationToken cancellation,
    );

class DnsLookupController extends ChangeNotifier {
  DnsLookupController({required DnsLookupRunner query}) : _query = query;

  final DnsLookupRunner _query;
  var _state = const DnsLookupState();
  var _generation = 0;
  var _disposed = false;
  CoreCancellationToken? _cancellation;
  Stopwatch? _watch;

  DnsLookupState get state => _state;

  Future<void> query(
    String input,
    String type, {
    required bool available,
  }) async {
    if (_disposed || _state.isLoading) return;
    final name = normalizeDnsLookupName(input);
    if (name == null || !dnsLookupTypes.contains(type)) {
      _set(const DnsLookupState(phase: DnsLookupPhase.invalid));
      return;
    }
    if (!available) {
      _set(
        DnsLookupState(
          phase: DnsLookupPhase.unavailable,
          name: name,
          type: type,
        ),
      );
      return;
    }
    final generation = ++_generation;
    final cancellation = CoreCancellationToken();
    final watch = Stopwatch()..start();
    _cancellation = cancellation;
    _watch = watch;
    _set(DnsLookupState(phase: DnsLookupPhase.loading, name: name, type: type));
    try {
      final result = await _query(name, type, cancellation);
      if (!_isCurrent(generation)) return;
      _set(
        DnsLookupState(
          phase: DnsLookupPhase.complete,
          name: name,
          type: type,
          result: result,
          elapsed: watch.elapsed,
          checkedAt: DateTime.now(),
        ),
      );
    } catch (error) {
      if (!_isCurrent(generation)) return;
      final phase = switch (error) {
        TimeoutException() => DnsLookupPhase.timedOut,
        CoreMethodException(code: 'cancelled') => DnsLookupPhase.cancelled,
        CoreMethodException(isCoreUnavailable: true) =>
          DnsLookupPhase.unavailable,
        CoreMethodException(code: 'not_configured' || 'not_initialized') =>
          DnsLookupPhase.unavailable,
        CoreMethodException(code: 'invalid_params' || 'invalid_field') =>
          DnsLookupPhase.invalid,
        CoreMethodException(code: 'conflict') => DnsLookupPhase.unavailable,
        _ => DnsLookupPhase.failed,
      };
      _set(
        DnsLookupState(
          phase: phase,
          name: name,
          type: type,
          elapsed: watch.elapsed,
          checkedAt: DateTime.now(),
        ),
      );
    } finally {
      watch.stop();
      if (_isCurrent(generation)) {
        _cancellation = null;
        _watch = null;
      }
    }
  }

  void cancel() {
    if (_disposed || !_state.isLoading) return;
    _stop(DnsLookupPhase.cancelled);
  }

  void reset() {
    if (_disposed) return;
    _stop(DnsLookupPhase.idle);
  }

  void invalidate() {
    if (_disposed || _state.phase == DnsLookupPhase.idle) return;
    _stop(DnsLookupPhase.stale);
  }

  void _stop(DnsLookupPhase phase) {
    _generation++;
    _cancellation?.cancel();
    _cancellation = null;
    _watch?.stop();
    final elapsed = _watch?.elapsed;
    _watch = null;
    _set(
      DnsLookupState(
        phase: phase,
        name: _state.name,
        type: _state.type,
        elapsed: elapsed,
      ),
    );
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _set(DnsLookupState state) {
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _cancellation?.cancel();
    _watch?.stop();
    super.dispose();
  }
}
