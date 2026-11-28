import 'dart:convert';

class TrafficRank {
  const TrafficRank({
    required this.name,
    required this.upload,
    required this.download,
    required this.hits,
    this.ruleType,
  });

  factory TrafficRank.fromJson(String name, Map<String, dynamic> json) =>
      TrafficRank(
        name: name,
        upload: _integer(json['up']),
        download: _integer(json['down']),
        hits: _integer(json['hits']),
        ruleType: json['ruleType'] is String
            ? json['ruleType'] as String
            : null,
      );

  final String name;
  final int upload;
  final int download;
  final int hits;
  final String? ruleType;

  int get total => upload + download;

  TrafficRank operator +(TrafficRank other) => TrafficRank(
    name: name,
    upload: upload + other.upload,
    download: download + other.download,
    hits: hits + other.hits,
    ruleType: ruleType ?? other.ruleType,
  );

  Map<String, Object> toJson() => {
    'up': upload,
    'down': download,
    'hits': hits,
    'ruleType': ?ruleType,
  };
}

const trafficHistoryRetentionDays = 90;

class TrafficDay {
  TrafficDay(this.date);

  factory TrafficDay.fromJson(String date, Map<String, dynamic> json) =>
      TrafficDay(date)
        ..upload = _integer(json['up'])
        ..download = _integer(json['down'])
        ..proxyUpload = _integer(json['proxyUp'])
        ..proxyDownload = _integer(json['proxyDown'])
        ..runtimeMs = _integer(json['runtimeMs'])
        ..ruleHits = _integer(json['ruleHits'])
        ..hours.addAll(_readSeries(json['hours']))
        ..applications.addAll(_readRanks(json['applications']))
        ..domains.addAll(_readRanks(json['domains']))
        ..nodes.addAll(_readRanks(json['nodes']))
        ..rules.addAll(_readRanks(json['rules']))
        ..profiles.addAll(_readRanks(json['profiles']));

  final String date;
  int upload = 0;
  int download = 0;
  int proxyUpload = 0;
  int proxyDownload = 0;
  int runtimeMs = 0;
  int ruleHits = 0;
  final hours = <int, ({int upload, int download})>{};
  final applications = <String, TrafficRank>{};
  final domains = <String, TrafficRank>{};
  final nodes = <String, TrafficRank>{};
  final rules = <String, TrafficRank>{};
  final profiles = <String, TrafficRank>{};

  void addTotals(int hour, int up, int down) {
    upload += up;
    download += down;
    final before = hours[hour];
    hours[hour] = (
      upload: (before?.upload ?? 0) + up,
      download: (before?.download ?? 0) + down,
    );
  }

  Map<String, Object?> toJson() => {
    'up': upload,
    'down': download,
    'proxyUp': proxyUpload,
    'proxyDown': proxyDownload,
    'runtimeMs': runtimeMs,
    'ruleHits': ruleHits,
    'hours': {
      for (final entry in hours.entries)
        '${entry.key}': [entry.value.upload, entry.value.download],
    },
    'applications': applications,
    'domains': domains,
    'nodes': nodes,
    'rules': rules,
    'profiles': profiles,
  };
}

class TrafficPoint {
  const TrafficPoint({
    required this.date,
    required this.label,
    required this.upload,
    required this.download,
  });

  final DateTime date;
  final String label;
  final int upload;
  final int download;
}

class TrafficHistorySnapshot {
  const TrafficHistorySnapshot({
    required this.start,
    required this.end,
    required this.days,
  });

  final DateTime start;
  final DateTime end;
  final List<TrafficDay> days;

  int get upload => days.fold(0, (sum, day) => sum + day.upload);
  int get download => days.fold(0, (sum, day) => sum + day.download);
  int get proxyUpload =>
      days.fold(0, (sum, day) => sum + day.proxyUpload.clamp(0, day.upload));
  int get proxyDownload => days.fold(
    0,
    (sum, day) => sum + day.proxyDownload.clamp(0, day.download),
  );
  int get total => upload + download;
  int get proxyTotal => proxyUpload + proxyDownload;
  int get directTotal => total - proxyTotal;
  int get ruleHits => days.fold(0, (sum, day) => sum + day.ruleHits);
  int get aggregatedRuleHits {
    var total = 0;
    for (final day in days) {
      for (final rule in day.rules.values) {
        total += rule.hits;
      }
    }
    return total;
  }

  int attributedTotal(String category) {
    var total = 0;
    for (final day in days) {
      final items = switch (category) {
        'application' => day.applications,
        'node' => day.nodes,
        'rule' => day.rules,
        'profile' => day.profiles,
        _ => day.domains,
      };
      for (final item in items.values) {
        total += item.total;
      }
    }
    return total;
  }

  Duration get runtime =>
      Duration(milliseconds: days.fold(0, (sum, day) => sum + day.runtimeMs));

  List<TrafficPoint> points({required bool hourly}) {
    if (hourly) {
      final values = days.firstOrNull?.hours;
      return [
        for (var hour = 0; hour < 24; hour++)
          TrafficPoint(
            date: start,
            label: '$hour',
            upload: values?[hour]?.upload ?? 0,
            download: values?[hour]?.download ?? 0,
          ),
      ];
    }
    final byDate = {for (final day in days) day.date: day};
    return [
      for (
        var date = start;
        !date.isAfter(end);
        date = trafficDateOffset(date, 1)
      )
        TrafficPoint(
          date: date,
          label: '${date.month}/${date.day}',
          upload: byDate[trafficDayKey(date)]?.upload ?? 0,
          download: byDate[trafficDayKey(date)]?.download ?? 0,
        ),
    ];
  }

  List<TrafficRank> ranks(
    String category, {
    int limit = 10,
    bool byHits = false,
  }) {
    final totals = <String, TrafficRank>{};
    for (final day in days) {
      final items = switch (category) {
        'application' => day.applications,
        'node' => day.nodes,
        'rule' => day.rules,
        'profile' => day.profiles,
        _ => day.domains,
      };
      for (final item in items.values) {
        totals.update(
          item.name,
          (current) => current + item,
          ifAbsent: () => item,
        );
      }
    }
    int score(TrafficRank item) => byHits ? item.hits : item.total;
    final ranked = totals.values.where((item) => score(item) > 0).toList()
      ..sort((a, b) {
        final order = score(b).compareTo(score(a));
        return order == 0 ? a.name.compareTo(b.name) : order;
      });
    return ranked.take(limit).toList(growable: false);
  }
}

enum TrafficHistoryPeriod { day, week, month }

TrafficHistorySnapshot trafficSnapshot(
  Map<String, TrafficDay> source,
  TrafficHistoryPeriod period, {
  DateTime? now,
  int offset = 0,
}) {
  final today = trafficDateOffset(now ?? DateTime.now(), 0);
  final DateTime start;
  DateTime end;
  switch (period) {
    case TrafficHistoryPeriod.day:
      start = trafficDateOffset(today, -offset);
      end = start;
    case TrafficHistoryPeriod.week:
      start = trafficDateOffset(today, 1 - today.weekday - offset * 7);
      end = trafficDateOffset(start, 6);
    case TrafficHistoryPeriod.month:
      final month = DateTime.utc(today.year, today.month - offset, 1);
      start = month;
      end = DateTime.utc(month.year, month.month + 1, 0);
  }
  if (end.isAfter(today)) end = today;
  final days = [
    for (
      var date = start;
      !date.isAfter(end);
      date = trafficDateOffset(date, 1)
    )
      ?source[trafficDayKey(date)],
  ];
  return TrafficHistorySnapshot(start: start, end: end, days: days);
}

// UTC is a calendar label here, not a timestamp; calendar math must survive DST.
DateTime trafficDateOffset(DateTime value, int days) =>
    DateTime.utc(value.year, value.month, value.day + days);

String trafficDayKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

int _integer(Object? value) => value is int && value >= 0 ? value : 0;

Map<int, ({int upload, int download})> _readSeries(Object? value) {
  final json = value is Map<String, dynamic>
      ? value
      : const <String, Object?>{};
  return {
    for (var hour = 0; hour < 24; hour++)
      if (json['$hour'] case [final up, final down])
        hour: (upload: _integer(up), download: _integer(down)),
  };
}

Map<String, TrafficRank> _readRanks(Object? value) {
  if (value is! Map<String, dynamic>) return {};
  return {
    for (final entry in value.entries.take(trafficRankLimit))
      if (entry.value case final Map<String, dynamic> rank)
        entry.key: TrafficRank.fromJson(entry.key, rank),
  };
}

const trafficRankLimit = 128;

void addTrafficRank(Map<String, TrafficRank> ranks, TrafficRank sample) {
  if (sample.name.isEmpty) return;
  final previous = ranks[sample.name];
  if (previous != null) {
    ranks[sample.name] = previous + sample;
  } else if (ranks.length < trafficRankLimit) {
    ranks[sample.name] = sample;
  } else {
    final lowest = ranks.values.reduce((a, b) => a.total <= b.total ? a : b);
    if (sample.total > lowest.total) {
      ranks
        ..remove(lowest.name)
        ..[sample.name] = sample;
    }
  }
}

TrafficDay decodeTrafficDay(String date, String source) {
  final data = jsonDecode(source);
  if (data is! Map<String, dynamic>) throw const FormatException();
  return TrafficDay.fromJson(date, data);
}
