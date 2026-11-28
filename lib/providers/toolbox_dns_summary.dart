import 'package:fl_clash/core/api/dto.dart';
import 'package:fl_clash/features/dns_lookup/controller.dart'
    show DnsLookupPhase;
import 'package:fl_clash/providers/route_state.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod/riverpod.dart';

final toolboxDnsSummaryProvider =
    NotifierProvider<ToolboxDnsSummaryStore, ToolboxDnsQuerySummary?>(
      ToolboxDnsSummaryStore.new,
    );

@immutable
class ToolboxDnsQuerySummary {
  const ToolboxDnsQuerySummary({
    required this.domain,
    required this.type,
    required this.phase,
    required this.result,
    required this.checkedAt,
    required this.elapsed,
    required this.stamp,
    required this.routeLive,
    required this.routeSynced,
  });

  final String domain;
  final String type;
  final DnsLookupPhase phase;
  final DnsQueryResult? result;
  final DateTime? checkedAt;
  final Duration? elapsed;
  final RouteStamp stamp;
  final bool routeLive;
  final bool routeSynced;

  bool isFresh(RouteState route) {
    if (phase == DnsLookupPhase.stale) return false;
    final sameStamp =
        route.coreEpoch == stamp.coreEpoch &&
        route.routeVersion == stamp.routeVersion &&
        route.hostEpoch == stamp.hostEpoch &&
        route.proxied == stamp.proxied &&
        route.picks == stamp.picks;
    if (!sameStamp) return false;
    if (phase == DnsLookupPhase.complete) {
      return route.live && route.synced && route.isFresh(stamp);
    }
    return route.live == routeLive && route.synced == routeSynced;
  }
}

class ToolboxDnsSummaryStore extends Notifier<ToolboxDnsQuerySummary?> {
  @override
  ToolboxDnsQuerySummary? build() => null;

  void publish(ToolboxDnsQuerySummary summary) {
    state = summary;
  }

  void clear() {
    state = null;
  }
}
