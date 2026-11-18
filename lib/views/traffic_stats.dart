import 'dart:async';
import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String _t(BuildContext context, String zh, String en) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

enum _TrafficPeriod { day, week, month }

enum _TrafficRank { hosts, processes, nodes, profiles }

typedef _Range = ({DateTime start, DateTime end});

const _rankLimit = 20;

String _two(int value) => value.toString().padLeft(2, '0');

String _dayKey(DateTime date) =>
    '${date.year}-${_two(date.month)}-${_two(date.day)}';

_Range _rangeOf(_TrafficPeriod period, int offset) {
  final now = DateTime.now();
  switch (period) {
    case _TrafficPeriod.day:
      final day = DateTime(now.year, now.month, now.day - offset);
      return (start: day, end: day);
    case _TrafficPeriod.week:
      final start = DateTime(
        now.year,
        now.month,
        now.day - (now.weekday - 1) - offset * 7,
      );
      return (
        start: start,
        end: DateTime(start.year, start.month, start.day + 6),
      );
    case _TrafficPeriod.month:
      final start = DateTime(now.year, now.month - offset, 1);
      return (start: start, end: DateTime(start.year, start.month + 1, 0));
  }
}

String _rangeLabel(_TrafficPeriod period, _Range range) => switch (period) {
  _TrafficPeriod.day => _dayKey(range.start),
  _TrafficPeriod.week =>
    '${_dayKey(range.start).substring(5)} ~ ${_dayKey(range.end).substring(5)}',
  _TrafficPeriod.month => _dayKey(range.start).substring(0, 7),
};

class TrafficStatsPage extends ConsumerStatefulWidget {
  const TrafficStatsPage({super.key});

  @override
  ConsumerState<TrafficStatsPage> createState() => _TrafficStatsPageState();
}

class _TrafficStatsPageState extends ConsumerState<TrafficStatsPage> {
  _TrafficPeriod _period = _TrafficPeriod.day;
  int _offset = 0;
  _TrafficRank _rank = _TrafficRank.hosts;
  TrafficStatsResult? _result;
  Timer? _timer;
  int _serial = 0;
  bool _enabled = true;

  _Range get _range => _rangeOf(_period, _offset);

  bool get _isLive => _period == _TrafficPeriod.day && _offset == 0;

  @override
  void initState() {
    super.initState();
    _configure(enable: true);
    _load();
    _syncTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _configure({required bool enable}) async {
    final profile = ref.read(currentProfileProvider)?.label ?? '';
    try {
      await ref
          .read(coreHandlerProvider)
          .configureTrafficStats(
            TrafficStatsConfigure(
              enable: enable,
              detail: true,
              retentionDays: 30,
              tzOffset: DateTime.now().timeZoneOffset.inMinutes,
              profile: profile,
            ),
          );
    } catch (_) {
      // The collector keeps its defaults when the Core is out of reach.
    }
  }

  Future<void> _load() async {
    final serial = ++_serial;
    final range = _range;
    TrafficStatsResult result;
    try {
      result = await ref
          .read(coreHandlerProvider)
          .getTrafficStats(
            TrafficStatsQuery(
              start: _dayKey(range.start),
              end: _dayKey(range.end),
            ),
          );
    } catch (_) {
      result = const TrafficStatsResult();
    }
    if (!mounted || serial != _serial) return;
    setState(() => _result = result);
  }

  void _syncTimer() {
    if (!_isLive || !_enabled) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  void _select(_TrafficPeriod period, int offset) {
    setState(() {
      _period = period;
      _offset = offset;
      _result = null;
    });
    _load();
    _syncTimer();
  }

  Future<void> _setEnabled(bool value) async {
    setState(() => _enabled = value);
    await _configure(enable: value);
    _syncTimer();
    if (value) _load();
  }

  Future<void> _clearRecords() async {
    try {
      await ref.read(coreHandlerProvider).clearTrafficStats();
    } catch (_) {
      return;
    }
    _load();
  }

  void _openSettings() {
    showSheet(
      context: context,
      builder: (_) => _TrafficStatsSettingsSheet(
        enabled: _enabled,
        onEnabledChanged: _setEnabled,
        onClear: _clearRecords,
      ),
    );
  }

  void _showHostDetail(String host) {
    showSheet(
      context: context,
      builder: (_) => _HostDetailSheet(
        host: host,
        range: _range,
        hourly: _period == _TrafficPeriod.day,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final range = _range;
    final since = result?.since ?? '';
    final canBack =
        since.isNotEmpty && _dayKey(range.start).compareTo(since) > 0;
    return Scaffold(
      title: _t(context, '流量统计', 'Traffic stats'),
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.settings,
          tooltip: _t(context, '设置', 'Settings'),
          onPressed: _openSettings,
        ),
      ],
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, context.contentTopPadding, 20, 32),
        children: [
          if (!_enabled) ...[
            _Surface(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _t(
                        context,
                        '流量记录已停用，重新打开后继续记录。',
                        'Traffic recording is off. Turn it back on to resume.',
                      ),
                      style: AppTextStyle.subheadline.of(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TonalButton(
                    label: _t(context, '启用', 'Enable'),
                    onPressed: () => _setEnabled(true),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          SegmentedControl<_TrafficPeriod>(
            segments: [
              (_TrafficPeriod.day, _t(context, '今天', 'Today')),
              (_TrafficPeriod.week, _t(context, '本周', 'This week')),
              (_TrafficPeriod.month, _t(context, '本月', 'This month')),
            ],
            value: _period,
            onChanged: (period) => _select(period, 0),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              IconButton(
                tooltip: _t(context, '上一区间', 'Previous period'),
                onPressed: canBack ? () => _select(_period, _offset + 1) : null,
                icon: const GlyphIcon(AppGlyphs.chevronBack, size: 18),
              ),
              Expanded(
                child: Text(
                  _rangeLabel(_period, range),
                  textAlign: TextAlign.center,
                  style: AppTextStyle.subheadline
                      .of(context, emphasized: true)
                      .toTabular,
                ),
              ),
              IconButton(
                tooltip: _t(context, '下一区间', 'Next period'),
                onPressed: _offset > 0
                    ? () => _select(_period, _offset - 1)
                    : null,
                icon: const GlyphIcon(AppGlyphs.chevronForward, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (result == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: LinearProgressIndicator(),
            )
          else
            _TrafficStatsContent(
              result: result,
              rank: _rank,
              onRankChanged: (rank) => setState(() => _rank = rank),
              onHostTap: _showHostDetail,
            ),
        ],
      ),
    );
  }
}

class _TrafficStatsContent extends StatelessWidget {
  const _TrafficStatsContent({
    required this.result,
    required this.rank,
    required this.onRankChanged,
    required this.onHostTap,
  });

  final TrafficStatsResult result;
  final _TrafficRank rank;
  final ValueChanged<_TrafficRank> onRankChanged;
  final ValueChanged<String> onHostTap;

  @override
  Widget build(BuildContext context) {
    final ranks = [
      _TrafficRank.hosts,
      if (result.processes.isNotEmpty) _TrafficRank.processes,
      _TrafficRank.nodes,
      if (result.profiles.isNotEmpty) _TrafficRank.profiles,
    ];
    final current = ranks.contains(rank) ? rank : _TrafficRank.hosts;
    final items = switch (current) {
      _TrafficRank.hosts => result.hosts,
      _TrafficRank.processes => result.processes,
      _TrafficRank.nodes => result.nodes,
      _TrafficRank.profiles => result.profiles,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Surface(child: _Overview(result: result)),
        _SectionHeader(_t(context, '规则命中', 'Rule hits')),
        _RuleHits(
          rules: result.rules.take(_rankLimit).toList(),
          total: result.ruleHits,
        ),
        _SectionHeader(_t(context, '流量排行', 'Traffic ranking')),
        if (ranks.length > 1) ...[
          SegmentedControl<_TrafficRank>(
            segments: [
              for (final item in ranks)
                (
                  item,
                  switch (item) {
                    _TrafficRank.hosts => _t(context, '域名', 'Domain'),
                    _TrafficRank.processes => _t(context, '进程', 'Process'),
                    _TrafficRank.nodes => _t(context, '节点', 'Node'),
                    _TrafficRank.profiles => _t(context, '配置', 'Profile'),
                  },
                ),
            ],
            value: current,
            onChanged: onRankChanged,
          ),
          const SizedBox(height: 10),
        ],
        _Surface(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: items.isEmpty
              ? const _NoData()
              : Column(
                  children: [
                    for (final item in items.take(_rankLimit))
                      _RankRow(
                        key: ValueKey('${current.name}:${item.name}'),
                        leading: _rankLeading(context, current, item),
                        name: item.name,
                        total: item.total,
                        ratio: item.total / math.max(items.first.total, 1),
                        onTap: current == _TrafficRank.hosts
                            ? () => onHostTap(item.name)
                            : null,
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _rankLeading(
    BuildContext context,
    _TrafficRank rank,
    TrafficStatsItem item,
  ) {
    return switch (rank) {
      _TrafficRank.hosts => _LetterTile(item.name),
      _TrafficRank.processes => _GlyphTile(AppGlyphs.appsList),
      _TrafficRank.nodes => _GlyphTile(AppGlyphs.layers),
      _TrafficRank.profiles => _GlyphTile(AppGlyphs.profiles),
    };
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        label,
        style: AppTextStyle.subheadline
            .of(context, emphasized: true)
            .copyWith(color: context.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _Surface extends StatelessWidget {
  const _Surface({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      decoration: ShapeDecoration(
        color: colors.surface,
        shape: AppShape.all(20).copyWith(
          side: BorderSide(color: colors.onSurface.withValues(alpha: 0.09)),
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.result});

  final TrafficStatsResult result;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final total = result.total.traffic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${total.value} ${total.unit}',
          style: AppTextStyle.largeTitle
              .of(context, emphasized: true)
              .toTabular,
        ),
        const SizedBox(height: 12),
        _LegendRow(
          color: colors.primary,
          label: _t(context, '上传', 'Upload'),
          value: dashboardTraffic(result.up),
        ),
        const SizedBox(height: 8),
        _LegendRow(
          color: colors.tertiary,
          label: _t(context, '下载', 'Download'),
          value: dashboardTraffic(result.down),
        ),
        const SizedBox(height: 12),
        Text(
          '${_t(context, '代理', 'Proxy')} ${dashboardTraffic(result.proxyTotal)}  ·  '
          '${_t(context, '直连', 'Direct')} ${dashboardTraffic(result.directTotal)}',
          maxLines: 2,
          style: AppTextStyle.footnote
              .of(context)
              .copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
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
      children: [
        DecoratedBox(
          decoration: ShapeDecoration(color: color, shape: AppShape.circle),
          child: const SizedBox.square(dimension: 8),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: AppTextStyle.footnote
              .of(context)
              .copyWith(color: context.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: AppTextStyle.footnote
                .of(context, emphasized: true)
                .toTabular,
          ),
        ),
      ],
    );
  }
}

class _NoData extends StatelessWidget {
  const _NoData();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          _t(context, '暂无数据', 'No data yet'),
          style: AppTextStyle.footnote
              .of(context)
              .copyWith(color: context.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _RuleHits extends StatelessWidget {
  const _RuleHits({required this.rules, required this.total});

  final List<TrafficStatsItem> rules;
  final int total;

  @override
  Widget build(BuildContext context) {
    if (rules.isEmpty) {
      return const _Surface(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: _NoData(),
      );
    }
    return SizedBox(
      height: 132,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < rules.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              _RuleCard(rule: rules[i], total: total),
            ],
          ],
        ),
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({required this.rule, required this.total});

  final TrafficStatsItem rule;
  final int total;

  String _percent(double ratio) {
    final value = ratio * 100;
    if (value > 0 && value < 1) return '<1%';
    return '${value >= 10 ? value.round() : value.toStringAsFixed(1)}%';
  }

  @override
  Widget build(BuildContext context) {
    final ratio = rule.hits / math.max(total, 1);
    final separator = rule.name.indexOf(',');
    final type = separator < 0 ? rule.name : rule.name.substring(0, separator);
    final payload = separator < 0 ? '' : rule.name.substring(separator + 1);
    return SizedBox(
      width: 136,
      child: _Surface(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _percent(ratio),
              style: AppTextStyle.title1
                  .of(context, emphasized: true)
                  .toTabular,
            ),
            const SizedBox(height: 8),
            Text(
              payload.isEmpty ? type : payload,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.footnote.of(context, emphasized: true),
            ),
            Text(
              payload.isEmpty ? ' ' : type,
              maxLines: 1,
              style: AppTextStyle.caption1
                  .of(context)
                  .copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              '${rule.hits} ${_t(context, '次', 'hits')} · ${dashboardTraffic(rule.total)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption1
                  .of(context)
                  .copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _LetterTile extends StatelessWidget {
  const _LetterTile(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final letter = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: colors.primary.withValues(alpha: 0.1),
        shape: AppShape.all(9),
      ),
      child: Text(
        letter,
        style: AppTextStyle.subheadline
            .of(context, emphasized: true)
            .copyWith(color: colors.primary),
      ),
    );
  }
}

class _GlyphTile extends StatelessWidget {
  const _GlyphTile(this.glyph);

  final Glyph glyph;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: colors.primary.withValues(alpha: 0.1),
        shape: AppShape.all(9),
      ),
      child: GlyphIcon(glyph, size: 18, color: colors.primary),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    super.key,
    required this.leading,
    required this.name,
    required this.total,
    required this.ratio,
    this.onTap,
  });

  final Widget leading;
  final String name;
  final int total;
  final double ratio;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          SizedBox.square(dimension: 38, child: Center(child: leading)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.subheadline.of(
                          context,
                          emphasized: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      dashboardTraffic(total),
                      style: AppTextStyle.footnote
                          .of(context)
                          .toTabular
                          .copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  height: 4,
                  alignment: Alignment.centerLeft,
                  decoration: ShapeDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    shape: AppShape.all(2),
                  ),
                  child: FractionallySizedBox(
                    widthFactor: ratio.clamp(0.0, 1.0),
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: colors.primary,
                        shape: AppShape.all(2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final onTap = this.onTap;
    if (onTap == null) return row;
    return PressSurface(
      fill: Colors.transparent,
      shape: AppShape.all(12),
      onPressed: onTap,
      childFills: true,
      child: row,
    );
  }
}

class _HostDetailSheet extends ConsumerStatefulWidget {
  const _HostDetailSheet({
    required this.host,
    required this.range,
    required this.hourly,
  });

  final String host;
  final _Range range;
  final bool hourly;

  @override
  ConsumerState<_HostDetailSheet> createState() => _HostDetailSheetState();
}

class _HostDetailSheetState extends ConsumerState<_HostDetailSheet> {
  TrafficStatsResult? _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    TrafficStatsResult result;
    try {
      result = await ref
          .read(coreHandlerProvider)
          .getTrafficStats(
            TrafficStatsQuery(
              start: _dayKey(widget.range.start),
              end: _dayKey(widget.range.end),
              host: widget.host,
            ),
          );
    } catch (_) {
      result = const TrafficStatsResult();
    }
    if (!mounted) return;
    setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final subs = result?.hosts.firstOrNull?.subs ?? const <TrafficStatsItem>[];
    final maxSub = subs.isEmpty ? 1 : math.max(subs.first.total, 1);
    return Scaffold(
      title: widget.host,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          context.contentTopPadding,
          16,
          16 + context.bottomInset,
        ),
        children: [
          Row(
            children: [
              _LetterTile(widget.host),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dashboardTraffic(result?.total ?? 0),
                      style: AppTextStyle.title1
                          .of(context, emphasized: true)
                          .toTabular,
                    ),
                    Text(
                      '↑ ${dashboardTraffic(result?.up ?? 0)}   ↓ ${dashboardTraffic(result?.down ?? 0)}',
                      style: AppTextStyle.caption1
                          .of(context)
                          .copyWith(
                            color: context.colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!widget.hourly && (result?.series.isNotEmpty ?? false)) ...[
            _SectionHeader(_t(context, '趋势', 'Trend')),
            _Surface(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: _TrendChart(
                series: result?.series ?? const [],
                hourly: false,
              ),
            ),
          ],
          if (subs.isNotEmpty) ...[
            _SectionHeader(_t(context, '子域名', 'Subdomains')),
            _Surface(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                children: [
                  for (final sub in subs)
                    _RankRow(
                      key: ValueKey(sub.name),
                      leading: _LetterTile(widget.host),
                      name: sub.name,
                      total: sub.total,
                      ratio: sub.total / maxSub,
                    ),
                ],
              ),
            ),
          ],
          if (result == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }
}

class _TrendChart extends StatefulWidget {
  const _TrendChart({required this.series, required this.hourly});

  final List<TrafficStatsPoint> series;
  final bool hourly;

  @override
  State<_TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<_TrendChart> {
  int? _selected;

  @override
  void didUpdateWidget(_TrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.series.length != widget.series.length) _selected = null;
  }

  String _axisLabel(TrafficStatsPoint point) {
    if (widget.hourly) return point.label;
    return int.tryParse(point.label.split('-').last)?.toString() ?? point.label;
  }

  String _title(TrafficStatsPoint point) => widget.hourly
      ? '${_two(int.tryParse(point.label) ?? 0)}:00'
      : point.label.substring(5);

  bool _showLabel(int index) {
    final length = widget.series.length;
    if (length <= 7) return true;
    if (widget.hourly) return index % 6 == 0 || index == length - 1;
    return index == 0 || (index + 1) % 5 == 0 || index == length - 1;
  }

  void _pick(Offset position, double width) {
    final length = widget.series.length;
    if (length == 0 || width <= 0) return;
    final index = (position.dx / width * length).floor().clamp(0, length - 1);
    setState(() => _selected = index);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final series = widget.series;
    final selected = _selected;
    final point = selected != null && selected < series.length
        ? series[selected]
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 18,
          child: point == null
              ? null
              : Text(
                  '${_title(point)}   ↑ ${dashboardTraffic(point.up)}   ↓ ${dashboardTraffic(point.down)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: colors.onSurfaceVariant),
                ),
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (_, constraints) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) =>
                _pick(details.localPosition, constraints.maxWidth),
            onHorizontalDragUpdate: (details) =>
                _pick(details.localPosition, constraints.maxWidth),
            child: SizedBox(
              height: 128,
              width: constraints.maxWidth,
              child: CustomPaint(
                painter: _TrendPainter(
                  series: series,
                  selected: selected,
                  upColor: colors.primary,
                  downColor: colors.tertiary,
                  trackColor: colors.onSurface.withValues(alpha: 0.05),
                  labelStyle: AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: colors.onSurfaceVariant),
                  labels: [
                    for (final (index, point) in series.indexed)
                      _showLabel(index) ? _axisLabel(point) : '',
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({
    required this.series,
    required this.selected,
    required this.upColor,
    required this.downColor,
    required this.trackColor,
    required this.labelStyle,
    required this.labels,
  });

  final List<TrafficStatsPoint> series;
  final int? selected;
  final Color upColor;
  final Color downColor;
  final Color trackColor;
  final TextStyle labelStyle;
  final List<String> labels;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;
    const labelHeight = 18.0;
    final chartHeight = size.height - labelHeight;
    final slot = size.width / series.length;
    final barWidth = math.min(math.max(slot * 0.56, 2.0), 18.0);
    final peak = series.fold<int>(
      0,
      (value, point) => math.max(value, point.up + point.down),
    );
    final radius = Radius.circular(math.min(barWidth / 2, 4));
    for (final (index, point) in series.indexed) {
      final left = slot * index + (slot - barWidth) / 2;
      final dim = selected != null && selected != index;
      final bar = RSuperellipse.fromRectAndRadius(
        Rect.fromLTWH(left, 0, barWidth, chartHeight),
        radius,
      );
      canvas.drawRSuperellipse(bar, Paint()..color = trackColor);
      final total = point.up + point.down;
      if (peak > 0 && total > 0) {
        final height = math.max(chartHeight * total / peak, 2.0);
        final downHeight = height * point.down / total;
        final top = chartHeight - height;
        canvas.save();
        canvas.clipRSuperellipse(bar);
        canvas.drawRect(
          Rect.fromLTRB(left, top, left + barWidth, chartHeight - downHeight),
          Paint()..color = upColor.withValues(alpha: dim ? 0.35 : 1),
        );
        canvas.drawRect(
          Rect.fromLTRB(
            left,
            chartHeight - downHeight,
            left + barWidth,
            chartHeight,
          ),
          Paint()..color = downColor.withValues(alpha: dim ? 0.35 : 1),
        );
        canvas.restore();
      }
      final label = index < labels.length ? labels[index] : '';
      if (label.isEmpty) continue;
      final painter = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final x = (slot * index + slot / 2 - painter.width / 2)
          .clamp(0.0, math.max(size.width - painter.width, 0.0))
          .toDouble();
      painter.paint(canvas, Offset(x, chartHeight + 4));
    }
  }

  @override
  bool shouldRepaint(_TrendPainter oldDelegate) =>
      oldDelegate.series != series ||
      oldDelegate.selected != selected ||
      oldDelegate.upColor != upColor ||
      oldDelegate.downColor != downColor ||
      oldDelegate.trackColor != trackColor;
}

class _TrafficStatsSettingsSheet extends StatefulWidget {
  const _TrafficStatsSettingsSheet({
    required this.enabled,
    required this.onEnabledChanged,
    required this.onClear,
  });

  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
  final Future<void> Function() onClear;

  @override
  State<_TrafficStatsSettingsSheet> createState() =>
      _TrafficStatsSettingsSheetState();
}

class _TrafficStatsSettingsSheetState
    extends State<_TrafficStatsSettingsSheet> {
  late bool _enabled = widget.enabled;
  bool _clearing = false;

  Future<void> _clear() async {
    final confirmed = await dialogs.showMessage(
      message: TextSpan(
        text: _t(
          context,
          '清空全部流量记录，此操作无法恢复。',
          'Clear all recorded traffic. This cannot be undone.',
        ),
      ),
      title: _t(context, '清除记录', 'Clear records'),
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    await widget.onClear();
    if (!mounted) return;
    setState(() => _clearing = false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      title: _t(context, '设置', 'Settings'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          context.contentTopPadding,
          16,
          16 + context.bottomInset,
        ),
        children: [
          generateSection(
            items: [
              ListItem.toggle(
                title: Text(_t(context, '记录流量', 'Record traffic')),
                subtitle: Text(
                  _t(
                    context,
                    '关闭后不再记录新的流量，旧记录保留。',
                    'Stops recording new traffic. Existing records stay.',
                  ),
                ),
                value: _enabled,
                onChanged: (value) {
                  setState(() => _enabled = value);
                  widget.onEnabledChanged(value);
                },
              ),
              ListItem(
                title: Text(
                  _t(context, '清除记录', 'Clear records'),
                  style: AppTextStyle.subheadline
                      .of(context)
                      .copyWith(
                        color: _clearing
                            ? context.colorScheme.onSurfaceVariant
                            : context.colorScheme.error,
                      ),
                ),
                onTap: _clearing ? null : _clear,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
