import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/file.dart';
import 'package:fl_clash/common/path.dart';
import 'package:fl_clash/core/api/core_api.dart';
import 'package:fl_clash/core/api/dto.dart';
import 'package:fl_clash/models/traffic_history.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

final trafficHistoryProvider = Provider<TrafficHistoryStore>((ref) {
  final store = TrafficHistoryStore(
    directory: () async =>
        Directory(p.join(await appPath.homeDirPath, 'traffic-history')),
  );
  ref.onDispose(store.dispose);
  return store;
});

class TrafficHistoryStore extends ChangeNotifier {
  TrafficHistoryStore({
    required Future<Directory> Function() directory,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _directory = Future.sync(directory);
    _loaded = _load();
  }

  static const sampleInterval = Duration(seconds: 5);
  static const _maxSampleGap = Duration(seconds: 15);
  static const _flushInterval = Duration(seconds: 30);
  static const _visibleInterval = Duration(seconds: 2);
  static final _dayFile = RegExp(r'^(\d{4}-\d{2}-\d{2})\.json$');
  static final _tempDayFile = RegExp(r'^\d{4}-\d{2}-\d{2}\.json\.\d+\.tmp$');

  final DateTime Function() _now;
  late final Future<Directory> _directory;
  late final Future<void> _loaded;
  final _days = <String, TrafficDay>{};
  final _dirty = <String>{};
  final _samples = <bool, (TrafficSample, DateTime)>{};
  final _connections = <int, _Connection>{};
  Future<void> _writes = Future.value();
  Timer? _flushTimer;
  Timer? _visibleTimer;
  String? _latestDay;
  bool _ready = false;
  bool _recording = false;
  bool _clearing = false;
  bool _error = false;
  bool _disposed = false;

  bool get ready => _ready;
  bool get recording => _recording;
  bool get canCapture => ready && recording && !_clearing && !_disposed;
  bool get error => _error;

  String get _cutoff =>
      trafficDayKey(trafficDateOffset(_now(), 1 - trafficHistoryRetentionDays));

  DateTime? get earliest {
    String? first;
    for (final day in _retained) {
      if (first == null || day.date.compareTo(first) < 0) first = day.date;
    }
    return first == null ? null : DateTime.tryParse('${first}T00:00:00Z');
  }

  Iterable<TrafficDay> get _retained {
    final cutoff = _cutoff;
    final today = trafficDayKey(_now());
    return _days.values.where(
      (day) =>
          day.date.compareTo(cutoff) >= 0 && day.date.compareTo(today) <= 0,
    );
  }

  Duration get runtime => Duration(
    milliseconds: _retained.fold(0, (sum, day) => sum + day.runtimeMs),
  );

  TrafficHistorySnapshot snapshot(
    TrafficHistoryPeriod period, {
    int offset = 0,
  }) {
    final retained = {for (final day in _retained) day.date: day};
    return trafficSnapshot(retained, period, offset: offset, now: _now());
  }

  File _flag(Directory dir) => File(p.join(dir.path, 'recording'));

  Stream<(File, String)> _dailyFiles(Directory dir) async* {
    if (!await dir.exists()) return;
    await for (final entry in dir.list(followLinks: false)) {
      if (entry is! File) continue;
      final match = _dayFile.firstMatch(p.basename(entry.path));
      if (match != null) yield (entry, match[1]!);
    }
  }

  Future<void> _load() async {
    try {
      final dir = await _directory;
      final cutoff = _cutoff;
      await for (final (file, date) in _dailyFiles(dir)) {
        if (date.compareTo(cutoff) < 0) {
          await file.safeDelete();
          continue;
        }
        try {
          _days[date] = decodeTrafficDay(date, await file.readAsString());
        } on FormatException {
          _error = true;
        }
      }
      _recording = await _flag(dir).exists();
    } catch (_) {
      _error = true;
    } finally {
      _ready = true;
      _publish();
    }
  }

  Future<void> _serialize(Future<void> Function() action) {
    final task = _writes.then((_) => action());
    _writes = task.then<void>((_) {}, onError: (Object _) {});
    return task;
  }

  Future<void> setRecording(bool enabled) async {
    await _loaded;
    await _serialize(() async {
      if (_disposed || _recording == enabled) return;
      final flag = _flag(await _directory);
      if (enabled) {
        await flag.writeAsStringAtomically('1');
      } else {
        await flag.safeDelete();
      }
      _recording = enabled;
      endCapture();
      _publish();
    });
    if (!enabled) await flush();
  }

  Future<void> refresh() async {
    await _loaded;
    await flush();
    _publish();
  }

  Future<void> clear() async {
    await _loaded;
    if (_clearing || _disposed) return;
    _clearing = true;
    endCapture();
    _publish();
    try {
      await _serialize(() async {
        _flushTimer?.cancel();
        _flushTimer = null;
        final dir = await _directory;
        await for (final (file, _) in _dailyFiles(dir)) {
          await file.safeDelete();
        }
        if (await dir.exists()) {
          await for (final entry in dir.list(followLinks: false)) {
            if (entry is File &&
                _tempDayFile.hasMatch(p.basename(entry.path))) {
              await entry.safeDelete();
            }
          }
        }
        _days.clear();
        _dirty.clear();
        _latestDay = null;
        _error = false;
      });
    } catch (_) {
      _error = true;
      rethrow;
    } finally {
      _clearing = false;
      _publish();
    }
  }

  void pauseCapture() {
    _connections.clear();
  }

  void endCapture() {
    pauseCapture();
    _samples.clear();
  }

  void recordSample(TrafficSample sample, {required bool onlyProxy}) {
    if (!canCapture) return;
    final now = _now();
    final previous = _samples[onlyProxy];
    _samples[onlyProxy] = (sample, now);
    if (previous == null) return;
    final (before, at) = previous;
    final elapsed = now.difference(at);
    if (elapsed <= Duration.zero) return;
    final up = sample.totalUp - before.totalUp;
    final down = sample.totalDown - before.totalDown;
    if (onlyProxy) {
      if (up < 0 || down < 0 || (up == 0 && down == 0)) return;
      final day = _day(now);
      day.proxyUpload += up;
      day.proxyDownload += down;
      _changed(day);
      return;
    }
    final gap = elapsed > _maxSampleGap;
    final day = _day(now);
    if (up >= 0 && down >= 0 && up + down > 0) {
      day.addTotals(now.hour, up, down);
    }
    if (!gap) {
      final dayStart = DateTime(now.year, now.month, now.day);
      if (at.isBefore(dayStart)) {
        final previousDay = _day(at);
        previousDay.runtimeMs += dayStart.difference(at).inMilliseconds;
        _changed(previousDay);
        day.runtimeMs += now.difference(dayStart).inMilliseconds;
      } else {
        day.runtimeMs += elapsed.inMilliseconds;
      }
    }
    _changed(day);
  }

  void recordConnections(ConnectionUpdate update, {String? profile}) {
    if (!canCapture) return;
    final now = _now();
    switch (update) {
      case ConnectionsReset(:final snapshot):
        final previous = Map.of(_connections);
        _connections.clear();
        for (final info in snapshot.connections) {
          final before = previous[info.id];
          if (before != null && before.start == info.start) {
            _connections[info.id] = before;
            _attribute(before, now, info.upload, info.download);
          } else {
            _connections[info.id] = _Connection(info, profile);
          }
        }
      case ConnectionsChanged(:final delta):
        for (final info in delta.opened) {
          if (_connections[info.id]?.start == info.start) continue;
          final connection = _Connection(info, profile);
          _connections[info.id] = connection;
          final day = _day(now);
          if (connection.rule.isNotEmpty) day.ruleHits++;
          _addDetails(day, connection, info.upload, info.download, hits: 1);
          _changed(day);
        }
        for (final counter in delta.counters) {
          final connection = _connections[counter.id];
          if (connection != null) {
            _attribute(connection, now, counter.upload, counter.download);
          }
        }
        for (final id in delta.closed) {
          _connections.remove(id);
        }
    }
  }

  void _attribute(_Connection entry, DateTime now, int upload, int download) {
    final up = upload - entry.upload;
    final down = download - entry.download;
    entry
      ..upload = upload
      ..download = download;
    if (up < 0 || down < 0 || up + down == 0) return;
    final day = _day(now);
    _addDetails(day, entry, up, down);
    _changed(day);
  }

  void _addDetails(
    TrafficDay day,
    _Connection entry,
    int up,
    int down, {
    int hits = 0,
  }) {
    void add(Map<String, TrafficRank> to, String name, {String? ruleType}) {
      addTrafficRank(
        to,
        TrafficRank(
          name: name,
          upload: up,
          download: down,
          hits: hits,
          ruleType: ruleType,
        ),
      );
    }

    add(day.domains, entry.domain);
    add(day.rules, entry.rule, ruleType: entry.ruleType);
    add(day.nodes, entry.node);
    add(day.profiles, entry.profile);
  }

  TrafficDay _day(DateTime now) {
    final date = trafficDayKey(now);
    if (_latestDay != date) {
      _latestDay = date;
      final cutoff = _cutoff;
      _days.removeWhere((date, _) => date.compareTo(cutoff) < 0);
      _dirty.removeWhere((date) => date.compareTo(cutoff) < 0);
    }
    return _days.putIfAbsent(date, () => TrafficDay(date));
  }

  void _changed(TrafficDay day) {
    _dirty.add(day.date);
    _visibleTimer ??= Timer(_visibleInterval, () {
      _visibleTimer = null;
      _publish();
    });
    _flushTimer ??= Timer(_flushInterval, flushQuietly);
  }

  void flushQuietly() {
    unawaited(flush().catchError((Object _) {}));
  }

  Future<void> flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_dirty.isEmpty || _clearing) return Future.value();
    return _serialize(() async {
      if (_clearing || _dirty.isEmpty) return;
      final keys = _dirty.toList();
      _dirty.clear();
      try {
        final dir = await _directory;
        for (final date in keys) {
          final day = _days[date];
          if (day != null) {
            await File(
              p.join(dir.path, '$date.json'),
            ).writeAsStringAtomically(jsonEncode(day));
          }
        }
        final cutoff = _cutoff;
        await for (final (file, date) in _dailyFiles(dir)) {
          if (date.compareTo(cutoff) < 0) await file.safeDelete();
        }
        if (_error) {
          _error = false;
          _publish();
        }
      } catch (_) {
        _dirty.addAll(keys);
        _error = true;
        _publish();
        rethrow;
      }
    });
  }

  void _publish() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _visibleTimer?.cancel();
    flushQuietly();
    super.dispose();
  }
}

class _Connection {
  _Connection(ConnectionInfo info, String? profile)
    : start = info.start,
      domain = _domain(info),
      node = _label(info.chains.firstOrNull),
      profile = _label(profile),
      ruleType = _label(info.rule),
      rule = info.rule.isEmpty
          ? ''
          : _label(
              info.rulePayload.isEmpty
                  ? info.rule
                  : '${info.rule}(${info.rulePayload})',
            ),
      upload = info.upload,
      download = info.download;

  final int start;
  final String domain, node, profile, rule, ruleType;
  int upload, download;

  static String _domain(ConnectionInfo info) {
    for (final value in [info.host, info.sniffHost, info.destinationIp]) {
      final label = _label(value);
      if (label.isNotEmpty) {
        final normalized = label.toLowerCase();
        return normalized.endsWith('.')
            ? normalized.substring(0, normalized.length - 1)
            : normalized;
      }
    }
    return '';
  }

  static String _label(String? value) {
    final label = value?.trim() ?? '';
    return label.length > 256 ? label.substring(0, 256) : label;
  }
}
