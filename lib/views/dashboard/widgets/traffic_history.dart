import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/traffic_history_format.dart';
import 'package:fl_clash/models/traffic_history.dart';
import 'package:fl_clash/providers/traffic_history.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:fl_clash/views/traffic_history.dart';
import 'package:fl_clash/widgets/traffic_share_gauge.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'card.dart';

class TrafficHistoryCard extends ConsumerWidget {
  const TrafficHistoryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(trafficHistoryProvider);
    final text = context.appLocalizations;
    final colors = DashboardColors.of(context);
    final primary = context.colorScheme.primary;
    return DashboardCard(
      onTap: () => openTrafficHistory(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.dataUsage,
            title: text.trafficUsage,
            chevron: true,
          ),
          ListenableBuilder(
            listenable: store,
            builder: (context, _) {
              if (!store.ready) return const SizedBox.shrink();
              if (!store.recording && store.earliest == null) {
                return Text(
                  store.error
                      ? text.trafficHistoryStorageError
                      : text.trafficHistoryRecording,
                  style: DashboardText.label(context),
                );
              }
              final stats = store.snapshot(TrafficHistoryPeriod.day);
              final share = stats.total == 0
                  ? 0.0
                  : stats.proxyTotal / stats.total;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  Row(
                    spacing: 12,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 6,
                          children: [
                            Text(
                              dashboardTraffic(stats.total),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DashboardText.figure(
                                context,
                                AppTextStyle.title1,
                              ),
                            ),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _Direction(
                                  AppGlyphs.arrowDown,
                                  stats.download,
                                  text.download,
                                ),
                                _Direction(
                                  AppGlyphs.arrowUp,
                                  stats.upload,
                                  text.upload,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      TrafficShareGauge(
                        share: stats.total == 0 ? null : share,
                        size: 62,
                        label: text.trafficHistoryProxy,
                        remainderColor: stats.total > 0
                            ? colors.series2
                            : colors.track,
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      _Detail(
                        primary,
                        text.trafficHistoryProxy,
                        stats.proxyTotal,
                      ),
                      _Detail(colors.series2, text.direct, stats.directTotal),
                    ],
                  ),
                  Row(
                    spacing: 6,
                    children: [
                      GlyphIcon(
                        AppGlyphs.clock,
                        size: 14,
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                      Flexible(
                        child: Text(
                          '${text.trafficHistoryRuntime} ${trafficHistoryDuration(context, store.runtime)}',
                          style: DashboardText.label(context),
                        ),
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

class _Direction extends StatelessWidget {
  const _Direction(this.icon, this.bytes, this.label);

  final Glyph icon;
  final int bytes;
  final String label;

  @override
  Widget build(BuildContext context) {
    final value = dashboardTraffic(bytes);
    return Semantics(
      label: label,
      value: value,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: AppShape.full,
            color: DashboardColors.of(context).tone,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 3,
              children: [
                GlyphIcon(
                  icon,
                  size: 12,
                  color: context.colorScheme.onSurfaceVariant,
                ),
                Text(value, style: DashboardText.label(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail(this.color, this.label, this.bytes);

  final Color color;
  final String label;
  final int bytes;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 5,
      children: [
        DecoratedBox(
          decoration: ShapeDecoration(shape: AppShape.circle, color: color),
          child: const SizedBox.square(dimension: 7),
        ),
        Text(
          '$label ${dashboardTraffic(bytes)}',
          style: DashboardText.label(context),
        ),
      ],
    );
  }
}
