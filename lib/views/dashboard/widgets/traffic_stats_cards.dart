import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/speed_test.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:fl_clash/views/toolbox_utilities.dart';
import 'package:fl_clash/views/traffic_stats.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'card.dart';

String _t(BuildContext context, String zh, String en) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

String _todayKey() {
  final now = DateTime.now();
  final two = (int value) => value.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}';
}

void _open(BuildContext context, Widget page) => Navigator.of(context).push(
  PageRouteBuilder<void>(
    pageBuilder: (_, animation, secondaryAnimation) => page,
    transitionsBuilder: (_, animation, secondaryAnimation, child) =>
        FadeTransition(opacity: animation, child: child),
  ),
);

class _DirectionRow extends StatelessWidget {
  const _DirectionRow({
    required this.glyph,
    required this.label,
    required this.value,
  });

  final Glyph glyph;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 8,
      children: [
        GlyphIcon(glyph, size: 16, color: context.colorScheme.onSurfaceVariant),
        Text(label, style: DashboardText.label(context)),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: DashboardText.figure(context, AppTextStyle.title1),
          ),
        ),
      ],
    );
  }
}

class TrafficStatsCard extends ConsumerStatefulWidget {
  const TrafficStatsCard({super.key});

  @override
  ConsumerState<TrafficStatsCard> createState() => _TrafficStatsCardState();
}

class _TrafficStatsCardState extends ConsumerState<TrafficStatsCard> {
  TrafficStatsResult? _result;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final today = _todayKey();
    TrafficStatsResult result;
    try {
      result = await ref
          .read(coreHandlerProvider)
          .getTrafficStats(TrafficStatsQuery(start: today, end: today));
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return DashboardCard(
      semanticLabel: _t(context, '流量统计', 'Traffic stats'),
      onTap: () => _open(context, const TrafficStatsPage()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.dataUsage,
            title: _t(context, '流量统计', 'Traffic stats'),
          ),
          const SizedBox(height: 12),
          _DirectionRow(
            glyph: AppGlyphs.arrowUp,
            label: context.appLocalizations.upload,
            value: result == null ? '—' : dashboardTraffic(result.up),
          ),
          const SizedBox(height: 8),
          _DirectionRow(
            glyph: AppGlyphs.arrowDown,
            label: context.appLocalizations.download,
            value: result == null ? '—' : dashboardTraffic(result.down),
          ),
        ],
      ),
    );
  }
}

class SpeedTestCard extends ConsumerWidget {
  const SpeedTestCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DashboardCard(
      semanticLabel: _t(context, '速度测试', 'Speed test'),
      onTap: () => _open(
        context,
        const ToolboxUtilityView(tool: ToolboxUtility.speedTest),
      ),
      child: ValueListenableBuilder<SpeedtestResult?>(
        valueListenable: lastSpeedtestResult,
        builder: (context, result, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DashboardCardHeader(
                glyph: AppGlyphs.speed,
                title: _t(context, '速度测试', 'Speed test'),
              ),
              const SizedBox(height: 12),
              if (result == null)
                Text(
                  _t(context, '点我测速', 'Tap to test'),
                  style: DashboardText.figure(context, AppTextStyle.title1),
                )
              else ...[
                _DirectionRow(
                  glyph: AppGlyphs.arrowDown,
                  label: context.appLocalizations.download,
                  value: '${result.downloadMbps.toStringAsFixed(1)} Mbps',
                ),
                const SizedBox(height: 8),
                _DirectionRow(
                  glyph: AppGlyphs.arrowUp,
                  label: context.appLocalizations.upload,
                  value: '${result.uploadMbps.toStringAsFixed(1)} Mbps',
                ),
                const SizedBox(height: 8),
                _DirectionRow(
                  glyph: AppGlyphs.clock,
                  label: _t(context, '延迟', 'Latency'),
                  value: '${result.latency.inMilliseconds} ms',
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
