import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/traffic_history_format.dart';
import 'package:fl_clash/models/common.dart' show TrafficShowExt;
import 'package:fl_clash/models/traffic_history.dart';
import 'package:fl_clash/providers/traffic_history.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/traffic_share_gauge.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

Future<void> openTrafficHistory(BuildContext context) {
  return showNestedSheet<void>(
    context,
    builder: (_) => const TrafficHistorySheet(),
  );
}

class TrafficHistorySheet extends ConsumerStatefulWidget {
  const TrafficHistorySheet({super.key});

  @override
  ConsumerState<TrafficHistorySheet> createState() =>
      _TrafficHistorySheetState();
}

class _TrafficHistorySheetState extends ConsumerState<TrafficHistorySheet> {
  TrafficHistoryPeriod _period = TrafficHistoryPeriod.day;
  var _offset = 0;
  var _busy = false;
  ScrollController? _scrollController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scrollController ??= sheetScrollController(context);
  }

  @override
  void dispose() {
    _scrollController?.dispose();
    super.dispose();
  }

  String _periodLabel(BuildContext context, TrafficHistoryPeriod period) {
    final l10n = context.appLocalizations;
    return switch (period) {
      TrafficHistoryPeriod.day => l10n.trafficHistoryDay,
      TrafficHistoryPeriod.week => l10n.trafficHistoryWeek,
      TrafficHistoryPeriod.month => l10n.trafficHistoryMonth,
    };
  }

  DateTime _periodStart(DateTime date, TrafficHistoryPeriod period) {
    final day = trafficDateOffset(date, 0);
    return switch (period) {
      TrafficHistoryPeriod.day => day,
      TrafficHistoryPeriod.week => trafficDateOffset(day, 1 - day.weekday),
      TrafficHistoryPeriod.month => DateTime.utc(day.year, day.month, 1),
    };
  }

  int _maxOffset(TrafficHistoryStore store) {
    final earliest = store.earliest;
    if (earliest == null) return 0;
    final today = trafficDateOffset(DateTime.now(), 0);
    final current = _periodStart(today, _period);
    final first = _periodStart(earliest, _period);
    return switch (_period) {
      TrafficHistoryPeriod.day => current.difference(first).inDays,
      TrafficHistoryPeriod.week => current.difference(first).inDays ~/ 7,
      TrafficHistoryPeriod.month =>
        (current.year - first.year) * 12 + current.month - first.month,
    }.clamp(0, 10000);
  }

  String _rangeLabel(TrafficHistorySnapshot snapshot) {
    final first = trafficDayKey(snapshot.start);
    if (_period == TrafficHistoryPeriod.day || snapshot.start == snapshot.end) {
      return first;
    }
    final last = trafficDayKey(snapshot.end);
    return '$first – $last';
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        dialogs.showBanner(context.appLocalizations.trafficHistoryStorageError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear(TrafficHistoryStore store) async {
    final l10n = context.appLocalizations;
    final accepted = await dialogs.showMessage(
      context: context,
      title: l10n.trafficHistoryClear,
      message: TextSpan(text: l10n.trafficHistoryClearConfirm),
      destructive: true,
    );
    if (accepted == true && mounted) {
      await _run(store.clear);
      if (mounted) setState(() => _offset = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(trafficHistoryProvider);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final l10n = context.appLocalizations;
        final snapshot = store.snapshot(_period, offset: _offset);
        final canPrevious = !_busy && _offset < _maxOffset(store);
        return Scaffold(
          title: l10n.trafficUsage,
          iconActions: [
            IconButtonData(
              glyph: AppGlyphs.delete,
              tooltip: l10n.trafficHistoryClear,
              onPressed: _busy ? null : () => _clear(store),
            ),
            IconButtonData(
              glyph: AppGlyphs.refresh,
              tooltip: l10n.trafficHistoryRefresh,
              isLoading: _busy,
              onPressed: _busy ? null : () => _run(store.refresh),
            ),
          ],
          body: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  context.contentTopPadding,
                  16,
                  12,
                ),
                child: Column(
                  spacing: 12,
                  children: [
                    SegmentedControl<TrafficHistoryPeriod>(
                      segments: [
                        for (final period in TrafficHistoryPeriod.values)
                          (period, _periodLabel(context, period)),
                      ],
                      value: _period,
                      onChanged: (value) => setState(() {
                        _period = value;
                        _offset = 0;
                      }),
                    ),
                    _PeriodNavigator(
                      label: _rangeLabel(snapshot),
                      canPrevious: canPrevious,
                      canNext: !_busy && _offset > 0,
                      previousLabel: l10n.trafficHistoryPrevious,
                      nextLabel: l10n.trafficHistoryNext,
                      onPrevious: () => setState(() => _offset++),
                      onNext: () => setState(() => _offset--),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: _scrollController,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    20 + context.bottomInset,
                  ),
                  children: [
                    const SizedBox(height: 4),
                    if (!store.ready)
                      const Padding(
                        padding: EdgeInsets.all(36),
                        child: Center(child: ActivityIndicator(size: 24)),
                      )
                    else ...[
                      if (store.error)
                        _StorageError(
                          message: l10n.trafficHistoryStorageError,
                          onRetry: () => _run(store.refresh),
                        ),
                      if (store.earliest == null)
                        _EmptyHistory(
                          recording: store.recording,
                          onRecordingChanged: (value) =>
                              _run(() => store.setRecording(value)),
                        )
                      else ...[
                        _RecordingControl(
                          recording: store.recording,
                          onChanged: (value) =>
                              _run(() => store.setRecording(value)),
                        ),
                        const SizedBox(height: 12),
                        _OverviewCard(snapshot: snapshot),
                        const SizedBox(height: 12),
                        _TrafficChart(snapshot: snapshot, period: _period),
                        const SizedBox(height: 20),
                        _RuleHitSection(snapshot: snapshot),
                        const SizedBox(height: 20),
                        _RankingsSection(snapshot: snapshot),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PeriodNavigator extends StatelessWidget {
  const _PeriodNavigator({
    required this.label,
    required this.canPrevious,
    required this.canNext,
    required this.previousLabel,
    required this.nextLabel,
    required this.onPrevious,
    required this.onNext,
  });

  final String label;
  final bool canPrevious;
  final bool canNext;
  final String previousLabel;
  final String nextLabel;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: ShapeDecoration(
        color: context.raisedSurfaceLevel.colorOf(context.colorScheme),
        shape: AppShape.xl,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: previousLabel,
            onPressed: canPrevious ? onPrevious : null,
            icon: const GlyphIcon(AppGlyphs.chevronBack),
          ),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.subheadline.of(context),
            ),
          ),
          IconButton(
            tooltip: nextLabel,
            onPressed: canNext ? onNext : null,
            icon: const GlyphIcon(AppGlyphs.chevronForward),
          ),
        ],
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.snapshot});

  final TrafficHistorySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final scheme = context.colorScheme;
    final total = snapshot.total.traffic;
    final proxyShare = snapshot.total == 0
        ? 0.0
        : snapshot.proxyTotal / snapshot.total;
    return Card(
      shape: AppShape.xl,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoHeader(
            info: Info(
              label: l10n.trafficHistoryOverview,
              glyph: AppGlyphs.dataUsage,
            ),
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 12),
          WidthBuilder(
            builder: (context, width) {
              final compact = width < 420;
              return Column(
                spacing: 10,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.totalTraffic,
                              style: AppTextStyle.subheadline
                                  .of(context)
                                  .copyWith(color: scheme.onSurfaceVariant),
                            ),
                            Text(
                              total.show,
                              style: AppTextStyle.title1.of(
                                context,
                                emphasized: true,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _MetricPill(
                                  label: '↓ ${snapshot.download.traffic.show}',
                                ),
                                _MetricPill(
                                  label: '↑ ${snapshot.upload.traffic.show}',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      TrafficShareGauge(
                        share: snapshot.total == 0 ? null : proxyShare,
                        size: compact ? 80 : 92,
                        label: l10n.trafficHistoryProxy,
                        showLabel: true,
                      ),
                    ],
                  ),
                  Table(
                    columnWidths: const {1: FixedColumnWidth(8)},
                    defaultVerticalAlignment:
                        TableCellVerticalAlignment.intrinsicHeight,
                    children: [
                      TableRow(
                        children: [
                          _RuntimeTile(
                            title: l10n.trafficHistoryRuntime,
                            value: trafficHistoryDuration(
                              context,
                              snapshot.runtime,
                            ),
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox.shrink(),
                          _TrafficSplitTile(
                            proxy: snapshot.proxyTotal,
                            direct: snapshot.directTotal,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: ShapeDecoration(
        color: context.raisedSurfaceLevel.colorOf(context.colorScheme),
        shape: AppShape.full,
      ),
      child: Text(
        label,
        style: AppTextStyle.footnote
            .of(context)
            .copyWith(color: context.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _OverviewTile extends StatelessWidget {
  const _OverviewTile({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: ShapeDecoration(
        color: context.raisedSurfaceLevel.colorOf(context.colorScheme),
        shape: AppShape.md,
      ),
      child: child,
    );
  }
}

class _RuntimeTile extends StatelessWidget {
  const _RuntimeTile({
    required this.title,
    required this.value,
    required this.color,
  });

  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _OverviewTile(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlyphIcon(AppGlyphs.clock, size: 16, color: color),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(color: context.colorScheme.onSurfaceVariant),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.subheadline.of(context, emphasized: true),
          ),
        ],
      ),
    );
  }
}

class _TrafficSplitTile extends StatelessWidget {
  const _TrafficSplitTile({required this.proxy, required this.direct});

  final int proxy;
  final int direct;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return _OverviewTile(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _SplitValue(
            color: context.colorScheme.primary,
            label: l10n.trafficHistoryProxy,
            value: proxy.traffic.show,
          ),
          const SizedBox(height: 8),
          _SplitValue(
            color: context.colorScheme.primary.withValues(alpha: 0.45),
            label: l10n.direct,
            value: direct.traffic.show,
          ),
        ],
      ),
    );
  }
}

class _SplitValue extends StatelessWidget {
  const _SplitValue({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 6,
      children: [
        DecoratedBox(
          decoration: ShapeDecoration(color: color, shape: AppShape.full),
          child: const SizedBox.square(dimension: 7),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyle.footnote
              .of(context)
              .copyWith(color: context.colorScheme.onSurfaceVariant),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: AppTextStyle.subheadline.of(context, emphasized: true),
          ),
        ),
      ],
    );
  }
}

class _TrafficChart extends StatelessWidget {
  const _TrafficChart({required this.snapshot, required this.period});

  final TrafficHistorySnapshot snapshot;
  final TrafficHistoryPeriod period;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final points = snapshot.points(hourly: period == TrafficHistoryPeriod.day);
    final maxValue = points.fold<int>(
      0,
      (value, point) => math.max(value, point.upload + point.download),
    );
    return Card(
      shape: AppShape.xl,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoHeader(
            info: Info(label: l10n.trafficHistoryTrend),
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          if (maxValue > 0) ...[
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                maxValue.traffic.show,
                style: AppTextStyle.caption2
                    .of(context)
                    .copyWith(color: context.colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 4),
          ],
          SizedBox(
            height: 142,
            child: _TrafficBars(
              points: points,
              hourly: period == TrafficHistoryPeriod.day,
              maxValue: maxValue,
            ),
          ),
        ],
      ),
    );
  }
}

const _trafficBarWidth = 12.0;
const _trafficBarZeroHeight = 2.0;

class _TrafficBars extends StatelessWidget {
  const _TrafficBars({
    required this.points,
    required this.hourly,
    required this.maxValue,
  });

  final List<TrafficPoint> points;
  final bool hourly;
  final int maxValue;

  @override
  Widget build(BuildContext context) {
    final labelIndexes = hourly
        ? const {0, 6, 12, 18}
        : points.length <= 7
        ? {for (var index = 0; index < points.length; index++) index}
        : {
            0,
            points.length ~/ 4,
            points.length ~/ 2,
            points.length * 3 ~/ 4,
            points.length - 1,
          };
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final barHeight = constraints.maxHeight;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final point in points)
                    Expanded(
                      child: _TrafficBar(
                        point: point,
                        maxValue: maxValue,
                        maxHeight: barHeight,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        SizedBox(
          height: 1,
          width: double.infinity,
          child: ColoredBox(
            color: context.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var index = 0; index < points.length; index++)
              Expanded(
                child: labelIndexes.contains(index)
                    ? Text(
                        points[index].label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        style: AppTextStyle.caption2
                            .of(context)
                            .copyWith(
                              color: context.colorScheme.onSurfaceVariant,
                            ),
                      )
                    : const SizedBox.shrink(),
              ),
          ],
        ),
      ],
    );
  }
}

class _TrafficBar extends StatelessWidget {
  const _TrafficBar({
    required this.point,
    required this.maxValue,
    required this.maxHeight,
  });

  final TrafficPoint point;
  final int maxValue;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final total = point.upload + point.download;
    final height = maxValue == 0 || maxHeight <= 0
        ? _trafficBarZeroHeight
        : (maxHeight * total / maxValue).clamp(
            _trafficBarZeroHeight,
            maxHeight,
          );
    final color = total == 0
        ? context.colorScheme.primary.withValues(alpha: 0.45)
        : context.colorScheme.primary;
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: _trafficBarWidth,
        child: Tooltip(
          message:
              '${point.label}: ${point.download.traffic.show} ↓ · ${point.upload.traffic.show} ↑',
          child: Semantics(
            label:
                '${point.label}, ${context.appLocalizations.download} ${point.download.traffic.show}, ${context.appLocalizations.upload} ${point.upload.traffic.show}',
            child: Container(
              height: height,
              decoration: ShapeDecoration(color: color, shape: AppShape.full),
            ),
          ),
        ),
      ),
    );
  }
}

class _RuleHitSection extends StatelessWidget {
  const _RuleHitSection({required this.snapshot});

  final TrafficHistorySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final rules = snapshot.ranks('rule', limit: 6, byHits: true);
    final maxHits = rules.fold<int>(0, (max, rule) => math.max(max, rule.hits));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListHeader(title: l10n.trafficHistoryRuleHits),
        if (rules.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(5, 4, 5, 8),
            child: Text(
              l10n.trafficHistoryDetailsEmpty,
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
          )
        else
          WidthBuilder(
            builder: (context, width) {
              final columns = width >= 620 ? 2 : 1;
              final rows = <Widget>[];
              for (var index = 0; index < rules.length; index += columns) {
                rows.add(
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 10,
                    children: [
                      for (final rule in rules.skip(index).take(columns))
                        Expanded(
                          child: _RuleHitCard(
                            rank: rule,
                            totalHits: snapshot.aggregatedRuleHits,
                            maxHits: maxHits,
                          ),
                        ),
                      if (columns == 2 && index + 1 >= rules.length)
                        const Expanded(child: SizedBox.shrink()),
                    ],
                  ),
                );
              }
              return Column(spacing: 10, children: rows);
            },
          ),
      ],
    );
  }
}

class _RuleHitCard extends StatelessWidget {
  const _RuleHitCard({
    required this.rank,
    required this.totalHits,
    required this.maxHits,
  });

  final TrafficRank rank;
  final int totalHits;
  final int maxHits;

  @override
  Widget build(BuildContext context) {
    final percentage = totalHits == 0 ? 0 : rank.hits * 100 / totalHits;
    final type = rank.ruleType;
    return Card(
      shape: AppShape.xl,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            spacing: 8,
            children: [
              TrafficShareGauge(
                share: percentage / 100,
                size: 40,
                label: rank.name,
              ),
              Expanded(
                child: Text(
                  rank.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.subheadline.of(context, emphasized: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _RatioBar(value: maxHits == 0 ? 0 : rank.hits / maxHits),
          const SizedBox(height: 8),
          Row(
            spacing: 8,
            children: [
              if (type != null && type.isNotEmpty) MetaChip(label: type),
              Expanded(
                child: Text(
                  '${rank.hits} · ${rank.total.traffic.show}',
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: context.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RatioBar extends StatelessWidget {
  const _RatioBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return ClipRSuperellipse(
      borderRadius: AppRadius.full,
      child: SizedBox(
        height: 5,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: context.colorScheme.onSurface.withValues(alpha: 0.12),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                widthFactor: value.clamp(0.0, 1.0),
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: context.colorScheme.primary,
                    shape: AppShape.full,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankingsSection extends StatefulWidget {
  const _RankingsSection({required this.snapshot});

  final TrafficHistorySnapshot snapshot;

  @override
  State<_RankingsSection> createState() => _RankingsSectionState();
}

class _RankingsSectionState extends State<_RankingsSection> {
  var _category = 'domain';

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final labels = <String, String>{
      'domain': l10n.domain,
      'rule': l10n.rule,
      'node': l10n.trafficHistoryNode,
      'profile': l10n.profiles,
    };
    final ranks = widget.snapshot.ranks(_category, limit: 10);
    final attributedTotal = widget.snapshot.attributedTotal(_category);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListHeader(title: l10n.trafficHistoryRankings),
        SegmentedControl<String>(
          segments: [
            for (final entry in labels.entries) (entry.key, entry.value),
          ],
          value: _category,
          onChanged: (value) => setState(() => _category = value),
        ),
        const SizedBox(height: 10),
        if (ranks.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(5, 4, 5, 8),
            child: Text(
              l10n.trafficHistoryDetailsEmpty,
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
          )
        else
          Card(
            shape: AppShape.xl,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              children: [
                for (final (index, rank) in ranks.indexed)
                  _RankRow(
                    rank: rank,
                    total: attributedTotal,
                    showDivider: index + 1 < ranks.length,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.rank,
    required this.total,
    required this.showDivider,
  });

  final TrafficRank rank;
  final int total;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final share = total == 0 ? 0.0 : rank.total / total;
    final item = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                rank.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.subheadline.of(context, emphasized: true),
              ),
              const SizedBox(height: 6),
              _RatioBar(value: share),
              const SizedBox(height: 6),
              Wrap(
                spacing: 10,
                runSpacing: 3,
                children:
                    [
                          Text('↓ ${rank.download.traffic.show}'),
                          Text('↑ ${rank.upload.traffic.show}'),
                          Text('${(share * 100).round()}%'),
                        ]
                        .map(
                          (child) => DefaultTextStyle.merge(
                            style: AppTextStyle.caption1
                                .of(context)
                                .copyWith(
                                  color: context.colorScheme.onSurfaceVariant,
                                ),
                            child: child,
                          ),
                        )
                        .toList(),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          rank.total.traffic.show,
          style: AppTextStyle.subheadline.of(context, emphasized: true),
        ),
      ],
    );
    return Column(
      children: [
        Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: item),
        if (showDivider)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Divider(),
          ),
      ],
    );
  }
}

class _RecordingControl extends StatelessWidget {
  const _RecordingControl({required this.recording, required this.onChanged});

  final bool recording;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return Card(
      shape: AppShape.xl,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.trafficHistoryRecording,
                  style: AppTextStyle.subheadline.of(context),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.trafficHistoryRecordingNote,
                  style: AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: context.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Switch(
            value: recording,
            semanticLabel: l10n.trafficHistoryRecording,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({
    required this.recording,
    required this.onRecordingChanged,
  });

  final bool recording;
  final ValueChanged<bool> onRecordingChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
          child: Column(
            children: [
              GlyphIcon(
                AppGlyphs.dataUsage,
                size: 36,
                color: context.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.trafficHistoryEmpty,
                textAlign: TextAlign.center,
                style: AppTextStyle.headline.of(context),
              ),
            ],
          ),
        ),
        _RecordingControl(recording: recording, onChanged: onRecordingChanged),
      ],
    );
  }
}

class _StorageError extends StatelessWidget {
  const _StorageError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: AppShape.xl,
      isError: true,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: AppTextStyle.body.of(context)),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onRetry,
            child: Text(context.appLocalizations.retry),
          ),
        ],
      ),
    );
  }
}
