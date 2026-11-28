import 'dart:async';
import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart' show TrafficShowExt;
import 'package:fl_clash/models/traffic_history.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/traffic_history.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/traffic_history_chart.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'traffic_history.dart';

class DiagnosticTrafficPane extends ConsumerStatefulWidget {
  const DiagnosticTrafficPane({super.key});

  @override
  ConsumerState<DiagnosticTrafficPane> createState() =>
      _DiagnosticTrafficPaneState();
}

class _DiagnosticTrafficPaneState extends ConsumerState<DiagnosticTrafficPane> {
  var _period = TrafficHistoryPeriod.day;
  var _category = 'application';
  var _busy = false;
  var _day = trafficDayKey(DateTime.now());
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (ref.read(appVisibleProvider)) _checkDate();
    });
  }

  void _checkDate() {
    final day = trafficDayKey(DateTime.now());
    if (day != _day && mounted) setState(() => _day = day);
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
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
    if (accepted == true && mounted) await _run(store.clear);
  }

  String _label(BuildContext context, TrafficHistoryPeriod period) {
    final l10n = context.appLocalizations;
    return switch (period) {
      TrafficHistoryPeriod.day => l10n.trafficHistoryDay,
      TrafficHistoryPeriod.week => l10n.trafficHistoryWeek,
      TrafficHistoryPeriod.month => l10n.trafficHistoryMonth,
    };
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(trafficHistoryProvider);
    ref.listen(appVisibleProvider, (_, visible) {
      if (visible) _checkDate();
    });
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final l10n = context.appLocalizations;
        if (!store.ready) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Center(
              child: RepaintBoundary(child: ActivityIndicator(size: 24)),
            ),
          );
        }
        final snapshot = store.snapshot(_period);
        final ranks = snapshot.ranks(_category, limit: 8);
        final attributed = snapshot.attributedTotal(_category);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              child: Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: SegmentedControl<TrafficHistoryPeriod>(
                      size: TonalButtonSize.section,
                      stretches: true,
                      segments: [
                        for (final period in TrafficHistoryPeriod.values)
                          (period, _label(context, period)),
                      ],
                      value: _period,
                      onChanged: (value) => setState(() => _period = value),
                    ),
                  ),
                  IconButton(
                    icon: const GlyphIcon(AppGlyphs.refresh),
                    tooltip: l10n.trafficHistoryRefresh,
                    onPressed: _busy ? null : () => _run(store.refresh),
                  ),
                  IconButton(
                    icon: const GlyphIcon(AppGlyphs.delete),
                    tooltip: l10n.trafficHistoryClear,
                    onPressed: _busy ? null : () => _clear(store),
                  ),
                ],
              ),
            ),
            if (store.error)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  l10n.trafficHistoryStorageError,
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: context.colorScheme.error),
                ),
              ),
            Card(
              radius: AppCorner.xxl,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  Text(
                    '${DateFormat.yMMMd().format(snapshot.start)}${_period == TrafficHistoryPeriod.day ? '' : ' – ${DateFormat.yMMMd().format(snapshot.end)}'}',
                    style: AppTextStyle.footnote
                        .of(context)
                        .copyWith(color: context.colorScheme.onSurfaceVariant),
                  ),
                  Text(
                    snapshot.total.traffic.show,
                    style: AppTextStyle.display.of(context, emphasized: true),
                  ),
                  Wrap(
                    spacing: 24,
                    runSpacing: 8,
                    children: [
                      _TrafficAmount(
                        glyph: AppGlyphs.arrowDown,
                        label: l10n.download,
                        value: snapshot.download.traffic.show,
                      ),
                      _TrafficAmount(
                        glyph: AppGlyphs.arrowUp,
                        label: l10n.upload,
                        value: snapshot.upload.traffic.show,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TrafficHistoryChart(snapshot: snapshot, period: _period),
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 12),
              child: SegmentedControl<String>(
                size: TonalButtonSize.section,
                stretches: true,
                segments: [
                  ('application', l10n.app),
                  ('domain', l10n.domain),
                  ('profile', l10n.profile),
                ],
                value: _category,
                onChanged: (value) => setState(() => _category = value),
              ),
            ),
            generateSection(
              atTop: true,
              footer: l10n.diagnosticsAttributionNote,
              items: ranks.isEmpty
                  ? [ListItem(title: Text(l10n.trafficHistoryDetailsEmpty))]
                  : [
                      for (final rank in ranks)
                        _TrafficRankRow(
                          key: ValueKey(
                            'diagnostics-rank-$_category-${rank.name}',
                          ),
                          rank: rank,
                          fraction: attributed == 0
                              ? 0
                              : rank.total / attributed,
                        ),
                    ],
            ),
            generateSection(
              footer: l10n.trafficHistoryRecordingNote,
              items: [
                ListItem.toggle(
                  title: Text(l10n.trafficHistoryRecording),
                  value: store.recording,
                  onChanged: _busy
                      ? null
                      : (value) => _run(() => store.setRecording(value)),
                ),
                ListItem(
                  title: Text(l10n.trafficHistoryOverview),
                  trailing: const GlyphIcon(AppGlyphs.chevronForward, size: 18),
                  onTap: () => openTrafficHistory(context),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _TrafficAmount extends StatelessWidget {
  const _TrafficAmount({
    required this.glyph,
    required this.label,
    required this.value,
  });

  final Glyph glyph;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 6,
    children: [
      GlyphIcon(glyph, size: 16, color: context.colorScheme.onSurfaceVariant),
      Text('$label $value', style: AppTextStyle.footnote.of(context)),
    ],
  );
}

class _TrafficRankRow extends StatelessWidget {
  const _TrafficRankRow({
    super.key,
    required this.rank,
    required this.fraction,
  });

  final TrafficRank rank;
  final double fraction;

  Future<void> _details(BuildContext context) => showNestedSheet<void>(
    context,
    builder: (context) {
      final l10n = context.appLocalizations;
      return Scaffold(
        title: rank.name,
        body: PrismListView(
          itemCount: 1,
          padding: context.listInsets.page(
            top: context.sectionsTopPadding,
            bottom: 24 + context.bottomInset,
          ),
          itemBuilder: (_, _) => generateSection(
            atTop: true,
            items: [
              for (final (label, value) in [
                (l10n.total, rank.total.traffic.show),
                (l10n.upload, rank.upload.traffic.show),
                (l10n.download, rank.download.traffic.show),
                (l10n.trafficHistoryRuleHits, '${rank.hits}'),
              ])
                ListItem(title: Text(label), trailing: Text(value)),
            ],
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) => ListItem(
    onTap: () => _details(context),
    title: Row(
      spacing: 12,
      children: [
        Expanded(
          child: Text(rank.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        Text(
          rank.total.traffic.show,
          style: AppTextStyle.subheadline.of(context, emphasized: true),
        ),
      ],
    ),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Text(
          '↑ ${rank.upload.traffic.show}   ↓ ${rank.download.traffic.show}',
          style: AppTextStyle.caption1
              .of(context)
              .copyWith(color: context.colorScheme.onSurfaceVariant),
        ),
        ClipPath(
          clipper: const ShapeBorderClipper(shape: AppShape.full),
          child: SizedBox(
            height: 4,
            child: ColoredBox(
              color: context.colorScheme.primary.withValues(alpha: .1),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: fraction.clamp(0, 1)),
                  duration: context.disableAnimations
                      ? Duration.zero
                      : const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  builder: (_, value, _) => FractionallySizedBox(
                    widthFactor: math.max(0, value),
                    heightFactor: 1,
                    child: ColoredBox(color: context.colorScheme.primary),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
