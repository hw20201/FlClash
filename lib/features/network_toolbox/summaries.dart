import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:intl/intl.dart';
import 'package:fl_clash/features/dns_lookup/controller.dart'
    show DnsLookupPhase, dnsRecordTypeLabel, dnsResponseCodeLabel;
import 'package:fl_clash/features/network_diagnostics/exit_card.dart'
    show diagnosticErrorLabel;
import 'package:fl_clash/models/common.dart' show TrafficShowExt;
import 'package:fl_clash/models/network_diagnostics.dart';
import 'package:fl_clash/models/traffic_history.dart';
import 'package:fl_clash/models/toolbox_layout.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:fl_clash/providers/route_state.dart';
import 'package:fl_clash/providers/traffic_history.dart';
import 'package:fl_clash/providers/toolbox_dns_summary.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';

class ToolboxExitSummary extends StatelessWidget {
  const ToolboxExitSummary({
    super.key,
    required this.size,
    required this.route,
    required this.state,
    required this.hideIp,
  });

  final ToolboxCardSize size;
  final RouteState route;
  final RoutedProbeState<DiagnosticFamily, DiagnosticExit> state;
  final bool hideIp;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final entries = <DiagnosticFamily, ProbeEntry<DiagnosticExit>>{
      for (final family in DiagnosticFamily.values)
        family: state.entryOf(family),
    };
    final stale = entries.values.any(
      (entry) =>
          entry.value != null &&
          (!route.live ||
              entry.stamp == null ||
              route.picks != entry.stamp!.picks ||
              !route.isFresh(entry.stamp!)),
    );
    final fresh = <DiagnosticFamily, ProbeEntry<DiagnosticExit>>{
      for (final family in DiagnosticFamily.values)
        if (route.live &&
            entries[family]!.stamp != null &&
            route.picks == entries[family]!.stamp!.picks &&
            route.isFresh(entries[family]!.stamp!))
          family: entries[family]!,
    };
    if (fresh.isEmpty && !route.live && !stale) {
      return _SummaryMessage(text: l10n.diagnosticsOffline);
    }
    if (fresh.isEmpty &&
        !stale &&
        entries.values.every((entry) => !entry.isLoading)) {
      return _SummaryMessage(text: l10n.diagnosticsNotRun);
    }
    if (size == ToolboxCardSize.small) {
      return _ExitCompactSummary(
        entries: entries,
        fresh: fresh,
        hideIp: hideIp,
      );
    }
    if (size == ToolboxCardSize.wide) {
      return LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 280) {
            return _ExitCompactSummary(
              entries: entries,
              fresh: fresh,
              hideIp: hideIp,
            );
          }
          return Row(
            spacing: 12,
            children: [
              for (final family in DiagnosticFamily.values)
                Expanded(
                  child: _ExitFamilySummary(
                    family: family,
                    entry: fresh[family] ?? entries[family]!,
                    route: route,
                    hideIp: hideIp,
                    inline: true,
                  ),
                ),
            ],
          );
        },
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: size == ToolboxCardSize.tall ? 12 : 6,
      children: [
        for (final family in DiagnosticFamily.values)
          _ExitFamilySummary(
            family: family,
            entry: fresh[family] ?? entries[family]!,
            route: route,
            hideIp: hideIp,
          ),
        if (size == ToolboxCardSize.tall)
          for (final result in fresh.values.map((entry) => entry.value))
            if (result?.isSuccess ?? false) ...[
              if ([
                result?.country,
                result?.region,
              ].whereType<String>().isNotEmpty)
                Text(
                  [
                    result?.country,
                    result?.region,
                  ].whereType<String>().join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.footnote.of(context),
                ),
              if (result?.asn case final asn?)
                Text(
                  '${l10n.diagnosticsAsn}: $asn',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: context.colorScheme.onSurfaceVariant),
                ),
            ],
      ],
    );
  }
}

class _ExitCompactSummary extends StatelessWidget {
  const _ExitCompactSummary({
    required this.entries,
    required this.fresh,
    required this.hideIp,
  });

  final Map<DiagnosticFamily, ProbeEntry<DiagnosticExit>> entries;
  final Map<DiagnosticFamily, ProbeEntry<DiagnosticExit>> fresh;
  final bool hideIp;

  @override
  Widget build(BuildContext context) {
    final checkedAt = entries.values
        .map((entry) => entry.value?.checkedAt)
        .whereType<DateTime>()
        .fold<DateTime?>(
          null,
          (latest, value) =>
              latest == null || value.isAfter(latest) ? value : latest,
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 0,
      children: [
        Row(
          spacing: 5,
          children: [
            for (final family in DiagnosticFamily.values)
              Expanded(
                child: Row(
                  spacing: 3,
                  children: [
                    Text(
                      family == DiagnosticFamily.ipv4 ? '4' : '6',
                      style: AppTextStyle.caption1
                          .of(context)
                          .copyWith(
                            color: context.colorScheme.onSurfaceVariant,
                          ),
                    ),
                    Expanded(
                      child: _CompactExitValue(
                        family: family,
                        entry: entries[family]!,
                        freshEntry: fresh[family],
                        hideIp: hideIp,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (checkedAt != null)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: _CheckedTime(checkedAt: checkedAt, compact: true),
          ),
      ],
    );
  }
}

class _CompactExitValue extends StatelessWidget {
  const _CompactExitValue({
    required this.family,
    required this.entry,
    required this.freshEntry,
    required this.hideIp,
  });

  final DiagnosticFamily family;
  final ProbeEntry<DiagnosticExit> entry;
  final ProbeEntry<DiagnosticExit>? freshEntry;
  final bool hideIp;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final result = freshEntry?.value;
    final detail = result == null
        ? entry.isLoading
              ? l10n.diagnosticsChecking
              : entry.value != null
              ? l10n.toolboxSummaryStale
              : l10n.diagnosticsNotRun
        : result.isSuccess
        ? hideIp && result.address != null
              ? '*****'
              : result.address ?? '—'
        : diagnosticErrorLabel(
            context,
            result.errorKind ?? DiagnosticErrorKind.unknown,
          );
    final checkedAt = entry.value?.checkedAt;
    final fullDate = checkedAt == null
        ? ''
        : DateFormat.yMd().add_Hm().format(checkedAt.toLocal());
    return Tooltip(
      message:
          '${family.name}: $detail'
          '${fullDate.isEmpty ? '' : ' · ${l10n.diagnosticsCheckedAt}: $fullDate'}',
      child: Text(
        detail,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyle.footnote.of(context),
      ),
    );
  }
}

class _ExitFamilySummary extends StatelessWidget {
  const _ExitFamilySummary({
    required this.family,
    required this.entry,
    required this.route,
    required this.hideIp,
    this.inline = false,
  });

  final DiagnosticFamily family;
  final ProbeEntry<DiagnosticExit> entry;
  final RouteState route;
  final bool hideIp;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final label = family == DiagnosticFamily.ipv4 ? 'IPv4' : 'IPv6';
    final stamp = entry.stamp;
    final result =
        stamp != null &&
            route.live &&
            route.picks == stamp.picks &&
            route.isFresh(stamp)
        ? entry.value
        : null;
    final detail = result == null
        ? entry.isLoading
              ? l10n.diagnosticsChecking
              : entry.value != null
              ? l10n.toolboxSummaryStale
              : l10n.diagnosticsNotRun
        : result.isSuccess
        ? hideIp && result.address != null
              ? '*****'
              : result.address ?? '—'
        : diagnosticErrorLabel(
            context,
            result.errorKind ?? DiagnosticErrorKind.unknown,
          );
    if (inline) {
      return Row(
        spacing: 4,
        children: [
          Text(
            label,
            style: AppTextStyle.caption1
                .of(context)
                .copyWith(color: context.colorScheme.onSurfaceVariant),
          ),
          Expanded(
            child: Tooltip(
              message: '$label: $detail',
              child: Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.footnote.of(context),
              ),
            ),
          ),
          if (entry.value?.checkedAt case final checkedAt?)
            _CheckedTime(checkedAt: checkedAt, compact: true),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: AppTextStyle.caption1
                  .of(context)
                  .copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
            if (entry.value?.checkedAt case final checkedAt?)
              _CheckedTime(checkedAt: checkedAt),
          ],
        ),
        Text(
          detail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyle.subheadline.of(context, emphasized: true),
        ),
      ],
    );
  }
}

class _CheckedTime extends StatelessWidget {
  const _CheckedTime({required this.checkedAt, this.compact = false});

  final DateTime checkedAt;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final time = DateFormat.Hm().format(checkedAt.toLocal());
    final dateTime = DateFormat.yMd().add_Hm().format(checkedAt.toLocal());
    return Tooltip(
      message: '${l10n.diagnosticsCheckedAt}: $dateTime',
      child: Text(
        time,
        style: (compact ? AppTextStyle.caption2 : AppTextStyle.caption1)
            .of(context)
            .copyWith(color: context.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class ToolboxDnsSummaryCard extends StatelessWidget {
  const ToolboxDnsSummaryCard({
    super.key,
    required this.size,
    required this.route,
    required this.summary,
  });

  final ToolboxCardSize size;
  final RouteState route;
  final ToolboxDnsQuerySummary? summary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final current = summary?.isFresh(route) == true ? summary : null;
    if (current == null) {
      final stale = summary;
      if (stale == null) {
        return _SummaryMessage(text: l10n.dnsLookupEmptyTitle);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 5,
        children: [
          if (stale.domain.isNotEmpty)
            Text(
              stale.domain,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.subheadline.of(context, emphasized: true),
            ),
          Text(
            l10n.toolboxSummaryStale,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(color: context.colorScheme.warning),
          ),
          if (stale.checkedAt case final checkedAt?)
            _CheckedTime(checkedAt: checkedAt),
        ],
      );
    }
    final result = current.result;
    final checkedAt = current.checkedAt;
    if (current.phase != DnsLookupPhase.complete ||
        result == null ||
        checkedAt == null) {
      final status = switch (current.phase) {
        DnsLookupPhase.invalid => l10n.dnsLookupInvalidName,
        DnsLookupPhase.unavailable => l10n.dnsLookupUnavailable,
        DnsLookupPhase.timedOut => l10n.dnsLookupTimedOut,
        DnsLookupPhase.failed => l10n.dnsLookupFailed,
        DnsLookupPhase.cancelled => l10n.dnsLookupCancelled,
        DnsLookupPhase.stale => l10n.dnsLookupStale,
        DnsLookupPhase.idle => l10n.dnsLookupEmptyTitle,
        DnsLookupPhase.loading => l10n.dnsLookupQuerying,
        DnsLookupPhase.complete => l10n.dnsLookupFailed,
      };
      if (size == ToolboxCardSize.small) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 3,
          children: [
            if (current.domain.isNotEmpty)
              Text(
                current.domain,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.subheadline.of(context, emphasized: true),
              ),
            Text(
              '$status${checkedAt == null ? '' : ' · ${DateFormat.Hm().format(checkedAt.toLocal())}'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: context.colorScheme.warning),
            ),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 5,
        children: [
          if (current.domain.isNotEmpty)
            Text(
              current.domain,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.subheadline.of(context, emphasized: true),
            ),
          Text(
            status,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(color: context.colorScheme.warning),
          ),
          if (current.elapsed case final elapsed?)
            Text(
              '${l10n.elapsed}: ${elapsed.inMilliseconds} ms',
              style: AppTextStyle.caption1
                  .of(context)
                  .copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
          if (current.checkedAt case final checkedAt?)
            _CheckedTime(checkedAt: checkedAt),
        ],
      );
    }
    final response = result;
    final code = '${dnsResponseCodeLabel(response.rcode)} (${response.rcode})';
    final codeColor = response.rcode == 0
        ? context.colorScheme.success
        : context.colorScheme.warning;
    final answers = response.answers;
    if (size == ToolboxCardSize.small) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 3,
        children: [
          Text(
            current.domain,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.subheadline.of(context, emphasized: true),
          ),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text:
                      '${current.type} · ${answers.length} ${l10n.answers} · ',
                ),
                TextSpan(
                  text: code,
                  style: TextStyle(color: codeColor),
                ),
                TextSpan(
                  text: ' · ${DateFormat.Hm().format(checkedAt.toLocal())}',
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(color: context.colorScheme.onSurfaceVariant),
          ),
        ],
      );
    }
    final records = size == ToolboxCardSize.wide
        ? answers.take(1)
        : answers.take(4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: size == ToolboxCardSize.tall ? 8 : 5,
      children: [
        Text(
          current.domain,
          maxLines: size == ToolboxCardSize.tall ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyle.subheadline.of(context, emphasized: true),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(current.type, style: AppTextStyle.footnote.of(context)),
            Text(
              code,
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: codeColor),
            ),
            if (current.elapsed case final elapsed?)
              Text(
                '${l10n.elapsed}: ${elapsed.inMilliseconds} ms',
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: context.colorScheme.onSurfaceVariant),
              ),
            if (current.checkedAt case final checkedAt?)
              _CheckedTime(checkedAt: checkedAt),
          ],
        ),
        if (answers.isEmpty)
          Text(
            l10n.dnsLookupNoRecords,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(color: context.colorScheme.onSurfaceVariant),
          )
        else
          for (final record in records)
            Text(
              '${dnsRecordTypeLabel(record.rtype)} · ${record.data} · ${l10n.dnsLookupTtl}: ${record.ttl}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.footnote.of(context),
            ),
      ],
    );
  }
}

class ToolboxTrafficSummary extends StatelessWidget {
  const ToolboxTrafficSummary({
    super.key,
    required this.size,
    required this.store,
  });

  final ToolboxCardSize size;
  final TrafficHistoryStore store;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    if (!store.ready) {
      return const Center(child: ActivityIndicator(size: 20));
    }
    if (store.error) {
      return _SummaryMessage(text: l10n.trafficHistoryStorageError);
    }
    final snapshot = store.snapshot(TrafficHistoryPeriod.day);
    if (store.earliest == null && snapshot.total == 0) {
      return _SummaryMessage(
        text: store.recording
            ? l10n.trafficHistoryEmpty
            : l10n.trafficHistoryRecording,
      );
    }
    final ranks = snapshot.ranks('application', limit: 3);
    final showTrend = size != ToolboxCardSize.small;
    final chartHeight = switch (size) {
      ToolboxCardSize.small => 0.0,
      ToolboxCardSize.wide => 38.0,
      ToolboxCardSize.tall => 132.0,
      ToolboxCardSize.large => 78.0,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: size == ToolboxCardSize.large ? 5 : 7,
      children: [
        Text(
          snapshot.total.traffic.show,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyle.title2.of(context, emphasized: true),
        ),
        if (size != ToolboxCardSize.small)
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              _TrafficDirection(
                glyph: AppGlyphs.arrowDown,
                label: l10n.download,
                bytes: snapshot.download,
              ),
              _TrafficDirection(
                glyph: AppGlyphs.arrowUp,
                label: l10n.upload,
                bytes: snapshot.upload,
              ),
            ],
          ),
        if (showTrend) _TrafficBars(snapshot: snapshot, height: chartHeight),
        if (size == ToolboxCardSize.large) ...[
          Text(l10n.toolboxTopApps, style: AppTextStyle.footnote.of(context)),
          if (ranks.isEmpty)
            Text(
              l10n.trafficHistoryEmpty,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption1
                  .of(context)
                  .copyWith(color: context.colorScheme.onSurfaceVariant),
            )
          else
            for (final rank in ranks)
              Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: Text(
                      rank.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.caption1.of(context),
                    ),
                  ),
                  Text(
                    rank.total.traffic.show,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.caption1
                        .of(context)
                        .copyWith(color: context.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
        ],
      ],
    );
  }
}

class _TrafficDirection extends StatelessWidget {
  const _TrafficDirection({
    required this.glyph,
    required this.label,
    required this.bytes,
  });

  final Glyph glyph;
  final String label;
  final int bytes;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 3,
    children: [
      GlyphIcon(glyph, size: 14, color: context.colorScheme.onSurfaceVariant),
      Text(
        '$label: ${bytes.traffic.show}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyle.footnote.of(context),
      ),
    ],
  );
}

class _TrafficBars extends StatelessWidget {
  const _TrafficBars({required this.snapshot, required this.height});

  final TrafficHistorySnapshot snapshot;
  final double height;

  @override
  Widget build(BuildContext context) {
    final points = snapshot.points(hourly: true);
    final maxValue = points.fold<int>(
      0,
      (value, point) => math.max(value, point.upload + point.download).toInt(),
    );
    if (maxValue == 0) return SizedBox(height: height);
    final colors = context.colorScheme;
    return Semantics(
      label: context.appLocalizations.trafficHistoryTrend,
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final point in points)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: .6),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: _TrafficBar(
                        point: point,
                        maxValue: maxValue,
                        maxHeight: height,
                        downloadColor: colors.primary,
                        uploadColor: colors.tertiary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrafficBar extends StatelessWidget {
  const _TrafficBar({
    required this.point,
    required this.maxValue,
    required this.maxHeight,
    required this.downloadColor,
    required this.uploadColor,
  });

  final TrafficPoint point;
  final int maxValue;
  final double maxHeight;
  final Color downloadColor;
  final Color uploadColor;

  @override
  Widget build(BuildContext context) {
    final total = point.upload + point.download;
    if (total == 0) return const SizedBox.shrink();
    final barHeight = (maxHeight * total / maxValue)
        .clamp(2.0, maxHeight)
        .toDouble();
    final downloadHeight = barHeight * point.download / total;
    final uploadHeight = barHeight - downloadHeight;
    return SizedBox(
      width: double.infinity,
      height: barHeight,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (downloadHeight > 0)
            SizedBox(
              width: double.infinity,
              height: downloadHeight,
              child: ColoredBox(color: downloadColor),
            ),
          if (uploadHeight > 0)
            SizedBox(
              width: double.infinity,
              height: uploadHeight,
              child: ColoredBox(color: uploadColor),
            ),
        ],
      ),
    );
  }
}

class _SummaryMessage extends StatelessWidget {
  const _SummaryMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: Text(
      text,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyle.footnote
          .of(context)
          .copyWith(color: context.colorScheme.onSurfaceVariant),
    ),
  );
}
