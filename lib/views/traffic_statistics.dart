import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/views/network_diagnostics_traffic.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';

class TrafficStatisticsView extends StatefulWidget {
  const TrafficStatisticsView({super.key});

  @override
  State<TrafficStatisticsView> createState() => _TrafficStatisticsViewState();
}

class _TrafficStatisticsViewState extends State<TrafficStatisticsView> {
  ScrollController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= sheetScrollController(context);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    title: context.appLocalizations.toolboxTrafficStatistics,
    body: PrismListView(
      key: const ValueKey('traffic-statistics-list'),
      controller: _controller,
      padding: context.listInsets.page(
        top: context.sectionsTopPadding,
        bottom: 24 + context.bottomInset,
      ),
      itemCount: 1,
      itemBuilder: (_, _) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 928),
          child: const DiagnosticTrafficPane(),
        ),
      ),
    ),
  );
}
