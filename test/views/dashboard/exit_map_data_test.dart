import 'package:fl_clash/common/exit_map_geo.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/views/dashboard/exit_map/canvas.dart';
import 'package:fl_clash/views/dashboard/exit_map/data.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

TrackerInfo _connection(
  int id,
  List<String> chains,
  int bytes, {
  int upload = 0,
}) => TrackerInfo(
  id: id,
  start: DateTime.utc(2026),
  metadata: const Metadata(),
  chains: chains,
  upload: upload,
  download: bytes,
  rule: 'MATCH',
  rulePayload: '',
);

ExitMapRoute _route(String node, Set<String> groups) => ExitMapRoute(
  node: node,
  groups: groups,
  place: locateExit('Tokyo')!,
  share: 0.5,
);

void main() {
  test(
    'weights real proxy leaves, excludes direct and retains unknown shares',
    () {
      final traffic = ExitMapTraffic();
      final snapshot = traffic.snapshot([
        _connection(1, ['JP-Tokyo-02', 'Proxy'], 50, upload: 10),
        _connection(2, ['JP-Tokyo-02', 'Streaming'], 15),
        _connection(3, ['香港 03', 'Proxy'], 15),
        _connection(4, ['unknown', 'Proxy'], 10),
        _connection(5, ['DIRECT', 'Proxy'], 10000),
        _connection(6, ['REJECT'], 10000),
        _connection(7, [], 10000),
      ]);
      expect(snapshot.routes.length, 2);
      expect(snapshot.routes.first.node, 'JP-Tokyo-02');
      expect(snapshot.routes.first.groups, {'Proxy', 'Streaming'});
      expect(snapshot.routes.first.share, 0.75);
      expect(snapshot.routes.last.share, 0.15);
      expect(snapshot.unlocated, 1);
      expect(traffic.snapshot([]).routes, isEmpty);
    },
  );

  test('zero or negative traffic is finite and has no flowing share', () {
    final snapshot = ExitMapTraffic().snapshot([
      _connection(1, ['Tokyo'], -50),
      _connection(2, ['香港'], 0),
    ]);
    expect(snapshot.routes.map((route) => route.share), everyElement(0));
  });

  test(
    '20k connections look up each unique leaf once and reuse unchanged data',
    () {
      var lookups = 0;
      final traffic = ExitMapTraffic(
        locate: (name) {
          lookups++;
          return locateExit(name);
        },
      );
      final connections = [
        for (var id = 0; id < 20000; id++)
          _connection(id, [id.isEven ? 'Tokyo' : '香港', 'Proxy'], 20),
      ];
      final first = traffic.snapshot(connections);
      expect(lookups, 2);
      expect(first.routes.length, 2);
      expect(identical(traffic.snapshot(connections), first), isTrue);
      expect(lookups, 2);
    },
  );

  test('pairs only unique disappeared and appeared nodes within a policy', () {
    expect(
      exitMapReplacements(
        [
          _route('old', {'A'}),
        ],
        [
          _route('new', {'A'}),
        ],
      ),
      {'new': 'old'},
    );
    expect(
      exitMapReplacements(
        [
          _route('same', {'A'}),
        ],
        [
          _route('same', {'A'}),
        ],
      ),
      isEmpty,
    );
    expect(
      exitMapReplacements(
        [
          _route('old', {'A'}),
        ],
        [
          _route('one', {'A'}),
          _route('two', {'A'}),
        ],
      ),
      isEmpty,
    );
    expect(
      exitMapReplacements(
        [
          _route('old', {'A', 'B'}),
        ],
        [
          _route('one', {'A'}),
          _route('two', {'B'}),
        ],
      ),
      isEmpty,
    );
  });

  test('vertical and horizontal routes both bend between their endpoints', () {
    const start = Offset(20, 20);
    const south = Offset(20, 60);
    const east = Offset(60, 20);
    expect(
      exitMapAlong(start, exitMapControl(start, south), south, 0.5).dx,
      greaterThan(start.dx),
    );
    expect(
      exitMapAlong(start, exitMapControl(start, east), east, 0.5).dy,
      lessThan(start.dy),
    );
  });

  test('fits endpoints and full arcs on wide, tall and dateline viewports', () {
    for (final size in [
      const Size(1200, 150),
      const Size(180, 300),
      const Size(400, 180),
    ]) {
      for (final name in ['Tokyo', 'London', 'New York', 'Sydney']) {
        final origin = locateExit(name)!;
        final exits = [
          '香港',
          'Los Angeles',
          'London',
          'Auckland',
        ].map(locateExit).whereType<ExitMapPlace>().toList();
        final bounds = exitMapFitBounds(size, origin, exits).inflate(1e-9);
        final start = exitMapWorldPoint(origin);
        for (final exit in exits) {
          final end = exitMapNearestCopy(exitMapWorldPoint(exit), start);
          for (var i = 0; i <= 100; i++) {
            final point = exitMapAlong(
              start,
              exitMapControl(start, end),
              end,
              i / 100,
            );
            expect(bounds.contains(point), isTrue, reason: '$size $name $exit');
          }
        }
      }
    }
    expect(unwrapLongitude(-179, 179), 181);
    expect(unwrapLongitude(179, -179), -181);
    final bounds = exitMapFitBounds(
      const Size(400, 200),
      null,
      [],
    ).inflate(1e-9);
    for (final (lat, lon) in [(-4.0, 96.0), (46.0, 150.0)]) {
      expect(bounds.contains(Offset(lon + 180, 90 - lat)), isTrue);
    }
    expect(exitMapFitBounds(Size.zero, null, []).isFinite, isTrue);
  });

  test('offline coastline uses the same world coordinates as endpoints', () {
    final land = exitMapLandPath();
    expect(land.computeMetrics().length, greaterThan(100));
    expect(
      exitMapWorld.inflate(0.05).contains(land.getBounds().topLeft),
      isTrue,
    );
    expect(
      exitMapWorld.inflate(0.05).contains(land.getBounds().bottomRight),
      isTrue,
    );
    for (final (lat, lon) in [(40.0, -100.0), (52.0, 13.0), (-24.0, 134.0)]) {
      expect(land.contains(Offset(lon + 180, 90 - lat)), isTrue);
    }
    for (final (lat, lon) in [(0.0, -40.0), (0.0, -145.0), (-20.0, 85.0)]) {
      expect(land.contains(Offset(lon + 180, 90 - lat)), isFalse);
    }
  });
}
