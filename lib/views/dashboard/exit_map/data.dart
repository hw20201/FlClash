import 'dart:math' as math;

import 'package:fl_clash/common/exit_map_geo.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

@immutable
class ExitMapRoute {
  const ExitMapRoute({
    required this.node,
    required this.groups,
    required this.place,
    required this.share,
  });

  final String node;
  final Set<String> groups;
  final ExitMapPlace place;
  final double share;

  @override
  bool operator ==(Object other) =>
      other is ExitMapRoute &&
      other.node == node &&
      setEquals(other.groups, groups) &&
      other.place == place &&
      other.share == share;

  @override
  int get hashCode =>
      Object.hash(node, Object.hashAllUnordered(groups), place, share);
}

@immutable
class ExitMapSnapshot {
  const ExitMapSnapshot({this.routes = const [], this.unlocated = 0});

  final List<ExitMapRoute> routes;
  final int unlocated;
}

class ExitMapTraffic {
  ExitMapTraffic({ExitMapPlace? Function(String) locate = locateExit})
    : _locate = locate;

  final ExitMapPlace? Function(String) _locate;
  final _locations = <String, ExitMapPlace?>{};
  var _last = const ExitMapSnapshot();

  ExitMapSnapshot snapshot(Iterable<TrackerInfo> connections) {
    final usage = <String, _NodeUsage>{};
    var total = 0;
    for (final connection in connections) {
      final chains = connection.chains;
      final node = chains.firstOrNull;
      if (node == null || _nonProxyNodes.contains(node.toUpperCase())) continue;
      final bytes =
          math.max<int>(0, connection.upload) +
          math.max<int>(0, connection.download);
      total += bytes;
      final entry = usage.putIfAbsent(node, _NodeUsage.new)..bytes += bytes;
      if (chains.length > 1) entry.groups.add(chains.last);
    }
    _locations.removeWhere((node, _) => !usage.containsKey(node));
    final routes = <ExitMapRoute>[];
    var unlocated = 0;
    for (final MapEntry(key: node, value: entry) in usage.entries) {
      final place = _locations.putIfAbsent(node, () => _locate(node));
      if (place == null) {
        unlocated++;
        continue;
      }
      routes.add(
        ExitMapRoute(
          node: node,
          groups: Set.unmodifiable(entry.groups),
          place: place,
          share: total == 0 ? 0 : entry.bytes / total,
        ),
      );
    }
    routes.sort((a, b) {
      final byShare = b.share.compareTo(a.share);
      return byShare != 0 ? byShare : a.node.compareTo(b.node);
    });
    if (unlocated == _last.unlocated && listEquals(routes, _last.routes)) {
      return _last;
    }
    return _last = ExitMapSnapshot(
      routes: List.unmodifiable(routes),
      unlocated: unlocated,
    );
  }
}

const _nonProxyNodes = {
  'DIRECT',
  'REJECT',
  'REJECT-DROP',
  'PASS',
  'COMPATIBLE',
};

class _NodeUsage {
  var bytes = 0;
  final groups = <String>{};
}

Map<String, String> exitMapReplacements(
  Iterable<ExitMapRoute> previous,
  Iterable<ExitMapRoute> next,
) {
  final oldNodes = previous.map((route) => route.node).toSet();
  final newNodes = next.map((route) => route.node).toSet();
  final removed = previous.where((route) => !newNodes.contains(route.node));
  final added = next.where((route) => !oldNodes.contains(route.node));
  Map<String, String?> uniqueByGroup(Iterable<ExitMapRoute> routes) {
    final groups = <String, String?>{};
    for (final route in routes) {
      for (final group in route.groups) {
        groups[group] = groups.containsKey(group) ? null : route.node;
      }
    }
    return groups;
  }

  final oldGroups = uniqueByGroup(removed);
  final newGroups = uniqueByGroup(added);
  final candidates = <String, Set<String>>{};
  final destinations = <String, Set<String>>{};
  for (final MapEntry(key: group, value: incoming) in newGroups.entries) {
    final outgoing = oldGroups[group];
    if (incoming == null || outgoing == null) continue;
    candidates.putIfAbsent(incoming, () => {}).add(outgoing);
    destinations.putIfAbsent(outgoing, () => {}).add(incoming);
  }
  return {
    for (final MapEntry(key: incoming, value: outgoing) in candidates.entries)
      if (outgoing.length == 1 && destinations[outgoing.single]!.length == 1)
        incoming: outgoing.single,
  };
}

@immutable
class ExitMapViewport {
  const ExitMapViewport(this.bounds, this.centerLongitude);

  factory ExitMapViewport.fit(
    Size size,
    ExitMapPlace? origin,
    Iterable<ExitMapPlace> exits,
  ) {
    final center = origin?.longitude ?? 123;
    var bounds = const Rect.fromLTRB(276 / 360, 44 / 180, 330 / 360, 94 / 180);
    if (origin != null) {
      Offset degrees(ExitMapPlace place) =>
          Offset(unwrapLongitude(place.longitude, center), -place.latitude);
      final start = degrees(origin);
      var left = start.dx;
      var right = start.dx;
      var top = start.dy;
      var bottom = start.dy;
      for (final place in exits) {
        final end = degrees(place);
        left = math.min(left, end.dx);
        right = math.max(right, end.dx);
        top = math.min(top, math.min(end.dy, exitMapControl(start, end).dy));
        bottom = math.max(bottom, end.dy);
      }
      bounds = Rect.fromCenter(
        center: Offset((left + right + 360) / 720, (top + bottom + 180) / 360),
        width: math.max((right - left) * 1.18, 30) / 360,
        height: math.max((bottom - top) * 1.25, 24) / 180,
      );
    }
    if (size.isEmpty || !size.isFinite) return ExitMapViewport(bounds, center);
    final aspect = size.aspectRatio;
    return ExitMapViewport(
      Rect.fromCenter(
        center: bounds.center,
        width: math.max(bounds.width, bounds.height * aspect / 2),
        height: math.max(bounds.height, bounds.width * 2 / aspect),
      ),
      center,
    );
  }

  final Rect bounds;
  final double centerLongitude;

  Offset project(ExitMapPlace place, Size size) => projectCoordinates(
    place.latitude,
    unwrapLongitude(place.longitude, centerLongitude),
    size,
  );

  Offset projectCoordinates(double lat, double lon, Size size) => Offset(
    ((lon + 180) / 360 - bounds.left) / bounds.width * size.width,
    ((90 - lat) / 180 - bounds.top) / bounds.height * size.height,
  );

  Rect worldRect(Size size) => Rect.fromPoints(
    projectCoordinates(90, centerLongitude - 180, size),
    projectCoordinates(-90, centerLongitude + 180, size),
  );

  @override
  bool operator ==(Object other) =>
      other is ExitMapViewport &&
      other.bounds == bounds &&
      other.centerLongitude == centerLongitude;

  @override
  int get hashCode => Object.hash(bounds, centerLongitude);
}

double unwrapLongitude(double longitude, double center) =>
    center + (longitude - center + 180) % 360 - 180;

Offset exitMapControl(Offset start, Offset end) =>
    (start + end) / 2 + Offset(0, -(end - start).distance * 0.26);

Offset exitMapAlong(Offset start, Offset control, Offset end, double t) =>
    start * ((1 - t) * (1 - t)) + control * (2 * (1 - t) * t) + end * (t * t);
