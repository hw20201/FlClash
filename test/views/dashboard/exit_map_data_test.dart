import 'dart:convert';

import 'package:fl_clash/common/exit_map_geo.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/views/dashboard/exit_map/canvas.dart';
import 'package:fl_clash/views/dashboard/exit_map/data.dart';
import 'package:fl_clash/views/dashboard/exit_map/land.dart';
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
        final viewport = ExitMapViewport.fit(size, origin, exits);
        final start = viewport.project(origin, size);
        for (final exit in exits) {
          final end = viewport.project(exit, size);
          for (var i = 0; i <= 100; i++) {
            final point = exitMapAlong(
              start,
              exitMapControl(start, end),
              end,
              i / 100,
            );
            expect(point.dx, inInclusiveRange(0, size.width));
            expect(point.dy, inInclusiveRange(0, size.height));
          }
        }
      }
    }
    expect(unwrapLongitude(-179, 179), 181);
    expect(unwrapLongitude(179, -179), -181);
    final viewport = ExitMapViewport.fit(const Size(400, 200), null, []);
    for (final (lat, lon) in [(-4.0, 96.0), (46.0, 150.0)]) {
      final point = viewport.projectCoordinates(lat, lon, const Size(400, 200));
      expect(point.dx, inInclusiveRange(-1e-9, 400 + 1e-9));
      expect(point.dy, inInclusiveRange(-1e-9, 200 + 1e-9));
    }
    expect(ExitMapViewport.fit(Size.zero, null, []).bounds.isFinite, isTrue);
  });

  test('public-domain land bitmap contains the expected degree cells', () {
    final data = base64Decode(exitMapLandBase64);
    expect(data.length, 8100);
    var cells = 0;
    for (final byte in data) {
      for (var bit = 0; bit < 8; bit++) {
        if (byte & (1 << bit) != 0) cells++;
      }
    }
    expect(cells, 21519);
    const size = Size(720, 360);
    const viewport = ExitMapViewport(Rect.fromLTWH(0, 0, 1, 1), 0);
    final points = exitMapLandPoints(viewport, size);
    expect(points.length, cells * 2);
    expect(points, everyElement(inInclusiveRange(0, 720)));
  });
}
