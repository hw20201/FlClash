/// Query, settings and result shapes for the Core's traffic history.
/// Field names mirror `core/toolbox/traffic_stats.go`, which answers them.
class TrafficStatsQuery {
  const TrafficStatsQuery({
    required this.start,
    required this.end,
    this.top = 20,
    this.host = '',
  });

  /// Inclusive start day as `2006-01-02`.
  final String start;

  /// Inclusive end day as `2006-01-02`.
  final String end;
  final int top;
  final String host;

  Map<String, Object?> toJson() {
    return {'start': start, 'end': end, 'top': top, 'host': host};
  }
}

class TrafficStatsConfigure {
  const TrafficStatsConfigure({
    required this.enable,
    required this.detail,
    required this.retentionDays,
    required this.tzOffset,
    required this.profile,
  });

  final bool enable;
  final bool detail;
  final int retentionDays;

  /// Local zone offset in minutes, as the collector stores it.
  final int tzOffset;
  final String profile;

  Map<String, Object?> toJson() {
    return {
      'enable': enable,
      'detail': detail,
      'retention-days': retentionDays,
      'tz-offset': tzOffset,
      'profile': profile,
    };
  }
}

class TrafficStatsItem {
  const TrafficStatsItem({
    required this.name,
    required this.up,
    required this.down,
    this.hits = 0,
    this.path = '',
    this.subs = const [],
  });

  factory TrafficStatsItem.fromJson(Map<String, dynamic> json) {
    return TrafficStatsItem(
      name: json['name'] as String? ?? '',
      up: (json['up'] as num?)?.toInt() ?? 0,
      down: (json['down'] as num?)?.toInt() ?? 0,
      hits: (json['hits'] as num?)?.toInt() ?? 0,
      path: json['path'] as String? ?? '',
      subs: _items(json['subs']),
    );
  }

  final String name;
  final int up;
  final int down;
  final int hits;
  final String path;
  final List<TrafficStatsItem> subs;

  int get total => up + down;
}

class TrafficStatsPoint {
  const TrafficStatsPoint({
    required this.label,
    required this.up,
    required this.down,
  });

  factory TrafficStatsPoint.fromJson(Map<String, dynamic> json) {
    return TrafficStatsPoint(
      label: json['label'] as String? ?? '',
      up: (json['up'] as num?)?.toInt() ?? 0,
      down: (json['down'] as num?)?.toInt() ?? 0,
    );
  }

  final String label;
  final int up;
  final int down;

  int get total => up + down;
}

class TrafficStatsResult {
  const TrafficStatsResult({
    this.up = 0,
    this.down = 0,
    this.proxyUp = 0,
    this.proxyDown = 0,
    this.series = const [],
    this.hosts = const [],
    this.processes = const [],
    this.nodes = const [],
    this.profiles = const [],
    this.rules = const [],
    this.ruleHits = 0,
    this.since = '',
  });

  factory TrafficStatsResult.fromJson(Map<String, dynamic> json) {
    return TrafficStatsResult(
      up: (json['up'] as num?)?.toInt() ?? 0,
      down: (json['down'] as num?)?.toInt() ?? 0,
      proxyUp: (json['proxy-up'] as num?)?.toInt() ?? 0,
      proxyDown: (json['proxy-down'] as num?)?.toInt() ?? 0,
      series: _points(json['series']),
      hosts: _items(json['hosts']),
      processes: _items(json['processes']),
      nodes: _items(json['nodes']),
      profiles: _items(json['profiles']),
      rules: _items(json['rules']),
      ruleHits: (json['rule-hits'] as num?)?.toInt() ?? 0,
      since: json['since'] as String? ?? '',
    );
  }

  final int up;
  final int down;
  final int proxyUp;
  final int proxyDown;
  final List<TrafficStatsPoint> series;
  final List<TrafficStatsItem> hosts;
  final List<TrafficStatsItem> processes;
  final List<TrafficStatsItem> nodes;
  final List<TrafficStatsItem> profiles;
  final List<TrafficStatsItem> rules;
  final int ruleHits;

  /// First recorded day as `2006-01-02`, empty when nothing is recorded.
  final String since;

  int get total => up + down;
  int get proxyTotal => proxyUp + proxyDown;

  int get directTotal {
    final direct = total - proxyTotal;
    return direct < 0 ? 0 : direct;
  }
}

List<TrafficStatsItem> _items(Object? value) {
  return [
    for (final item in value as List? ?? const <Object?>[])
      TrafficStatsItem.fromJson(Map<String, dynamic>.from(item as Map)),
  ];
}

List<TrafficStatsPoint> _points(Object? value) {
  return [
    for (final item in value as List? ?? const <Object?>[])
      TrafficStatsPoint.fromJson(Map<String, dynamic>.from(item as Map)),
  ];
}
