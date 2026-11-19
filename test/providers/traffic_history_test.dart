import 'dart:io';

import 'package:fl_clash/core/api/core_api.dart';
import 'package:fl_clash/core/api/dto.dart';
import 'package:fl_clash/models/traffic_history.dart';
import 'package:fl_clash/providers/traffic_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

TrafficSample _sample(int upload, int download) =>
    TrafficSample(up: 0, down: 0, totalUp: upload, totalDown: download);

ConnectionInfo _connection(int id, {int bytes = 0, int start = 1}) =>
    ConnectionInfo(
      id: id,
      start: start,
      network: 'tcp',
      sourceIp: '127.0.0.1',
      sourcePort: 1111,
      host: 'CDN.example.',
      destinationPort: 443,
      inboundType: 'mixed',
      chains: const ['Example node', 'Group'],
      rule: 'RuleSet',
      rulePayload: 'video',
      upload: 0,
      download: bytes,
    );

void main() {
  late Directory dir;
  late DateTime now;
  late TrafficHistoryStore store;

  TrafficHistoryStore open() =>
      TrafficHistoryStore(directory: () async => dir, now: () => now);

  TrafficHistorySnapshot day({int offset = 0}) =>
      store.snapshot(TrafficHistoryPeriod.day, offset: offset);

  void sample(int up, int down, {bool onlyProxy = false}) =>
      store.recordSample(_sample(up, down), onlyProxy: onlyProxy);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('flowcat-history-test-');
    now = DateTime(2026, 11, 19, 10);
    store = open();
    await store.refresh();
  });

  tearDown(() async {
    await store.flush();
    store.dispose();
    await dir.delete(recursive: true);
  });

  test('recording requires opt-in and starts from counter baselines', () async {
    sample(500, 2000);
    now = now.add(const Duration(seconds: 5));
    sample(700, 3000);
    expect(store.recording, isFalse);
    expect(day().total, 0);

    await store.setRecording(true);
    sample(700, 3000);
    sample(0, 1200, onlyProxy: true);
    now = now.add(const Duration(seconds: 5));
    sample(800, 3600);
    sample(60, 1600, onlyProxy: true);
    expect(day().upload, 100);
    expect(day().download, 600);
    expect(day().proxyTotal, 460);
    expect(day().directTotal, 240);
    expect(day().runtime, const Duration(seconds: 5));
    expect(day().points(hourly: true)[10].download, 600);

    now = now.add(const Duration(seconds: 5));
    sample(10, 20);
    now = now.add(const Duration(seconds: 5));
    sample(20, 50);
    expect(day().total, 740);

    store.endCapture();
    now = now.add(const Duration(hours: 2));
    sample(10000, 50000);
    expect(day().total, 740);
    expect(day().runtime, const Duration(seconds: 15));
    now = now.add(const Duration(minutes: 2));
    sample(20000, 60000);
    expect(day().total, 740);
    expect(day().runtime, const Duration(seconds: 15));
  });

  test(
    'baselines existing connections and attributes new bytes once',
    () async {
      await store.setRecording(true);
      store.recordConnections(
        ConnectionsReset(ConnectionSnapshot([_connection(1, bytes: 1000)])),
        profile: 'Profile A',
      );
      store.recordConnections(
        ConnectionsChanged(
          ConnectionDelta(
            opened: [_connection(2, bytes: 20)],
            counters: const [
              ConnectionCounter(id: 1, upload: 10, download: 1050),
              ConnectionCounter(id: 2, upload: 5, download: 25),
            ],
            closed: const [2],
          ),
        ),
        profile: 'Profile B',
      );
      store.recordConnections(
        ConnectionsReset(ConnectionSnapshot([_connection(1, bytes: 1050)])),
        profile: 'Profile C',
      );
      store.recordConnections(
        const ConnectionsChanged(
          ConnectionDelta(
            counters: [ConnectionCounter(id: 2, upload: 25, download: 75)],
          ),
        ),
      );
      final snapshot = day();
      expect(snapshot.ranks('domain').single.name, 'cdn.example');
      expect(snapshot.ranks('domain').single.total, 90);
      expect(snapshot.ranks('node').single.name, 'Example node');
      expect(snapshot.ranks('profile').map((item) => item.name), [
        'Profile A',
        'Profile B',
      ]);
      final rule = snapshot.ranks('rule', byHits: true).single;
      expect(rule.name, 'RuleSet(video)');
      expect(rule.ruleType, 'RuleSet');
      expect(rule.hits, 1);
      expect(snapshot.ruleHits, 1);
    },
  );

  test('persists daily totals and prunes expired local files', () async {
    final old = File(p.join(dir.path, '2026-08-01.json'));
    await old.writeAsString('{}');
    await store.setRecording(true);
    now = DateTime(2026, 11, 18, 23, 59, 58);
    sample(100, 100);
    now = now.add(const Duration(seconds: 5));
    sample(125, 150);
    expect(day(offset: 1).runtime, const Duration(seconds: 2));
    expect(day().runtime, const Duration(seconds: 3));
    expect(day().total, 75);
    expect(day().points(hourly: true).first.download, 50);
    await store.flush();
    expect(await old.exists(), isFalse);
    store.dispose();
    store = open();
    await store.refresh();
    expect(store.recording, isTrue);
    expect(store.runtime, const Duration(seconds: 5));
    expect(day().download, 50);
    final week = store.snapshot(TrafficHistoryPeriod.week);
    expect(week.start, DateTime.utc(2026, 11, 16));
    expect(week.end, DateTime.utc(2026, 11, 19));
    expect(week.points(hourly: false).map((point) => point.download), [
      0,
      0,
      0,
      50,
    ]);
    final month = store.snapshot(TrafficHistoryPeriod.month, offset: 1);
    expect(month.points(hourly: false).length, 31);
  });

  test('clear discards old samples and keeps the recording setting', () async {
    await store.setRecording(true);
    sample(100, 200);
    now = now.add(const Duration(seconds: 5));
    sample(300, 500);
    final pendingWrite = store.flush();
    await store.clear();
    await pendingWrite;
    expect(store.recording, isTrue);
    expect(store.earliest, isNull);
    expect(day().runtime, Duration.zero);
    now = now.add(const Duration(seconds: 5));
    sample(500, 900);
    expect(day().total, 0);
    now = now.add(const Duration(seconds: 5));
    sample(510, 915);
    expect(day().total, 25);
    await store.setRecording(false);
    store.dispose();
    store = open();
    await store.refresh();
    expect(store.recording, isFalse);
    expect(day().total, 25);
    await store.clear();
    expect(await dir.list().toList(), isEmpty);
  });
}
