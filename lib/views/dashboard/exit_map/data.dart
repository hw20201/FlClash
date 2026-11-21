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

const exitMapWorld = Rect.fromLTWH(0, 0, 360, 180);

Offset exitMapWorldPoint(ExitMapPlace place) =>
    Offset((place.longitude + 180) % 360, 90 - place.latitude);

Offset exitMapNearestCopy(Offset point, Offset reference) =>
    Offset(unwrapLongitude(point.dx, reference.dx), point.dy);

Rect exitMapFitBounds(
  Size size,
  ExitMapPlace? origin,
  Iterable<ExitMapPlace> exits,
) {
  var bounds = const Rect.fromLTRB(276, 44, 330, 94);
  if (origin != null) {
    final start = exitMapWorldPoint(origin);
    var extent = start & Size.zero;
    for (final place in exits) {
      final end = exitMapNearestCopy(exitMapWorldPoint(place), start);
      extent = extent.expandToInclude(
        Rect.fromPoints(end, exitMapControl(start, end)),
      );
    }
    bounds = Rect.fromCenter(
      center: extent.center,
      width: math.max(extent.width * 1.18, 60),
      height: math.max(extent.height * 1.25, 38),
    );
  }
  if (size.isEmpty || !size.isFinite) return bounds;
  return Rect.fromCenter(
    center: bounds.center,
    width: math.max(bounds.width, bounds.height * size.aspectRatio),
    height: math.max(bounds.height, bounds.width / size.aspectRatio),
  );
}

double unwrapLongitude(double longitude, double center) =>
    center + (longitude - center + 180) % 360 - 180;

Offset exitMapControl(Offset start, Offset end) {
  final delta = end - start;
  return (start + end) / 2 + Offset(delta.dy, -delta.dx) * 0.26;
}

Offset exitMapAlong(Offset start, Offset control, Offset end, double t) =>
    start * ((1 - t) * (1 - t)) + control * (2 * (1 - t) * t) + end * (t * t);
