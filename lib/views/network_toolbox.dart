import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/network_toolbox/module_card.dart';
import 'package:fl_clash/features/network_toolbox/summaries.dart';
import 'package:fl_clash/models/toolbox_layout.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/network_diagnostics.dart';
import 'package:fl_clash/providers/providers.dart' show appVisibleProvider;
import 'package:fl_clash/providers/route_state.dart';
import 'package:fl_clash/providers/traffic_history.dart';
import 'package:fl_clash/providers/toolbox_dns_summary.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dns_lookup.dart';
import 'package:fl_clash/views/exit_ip.dart';
import 'package:fl_clash/views/network_diagnostics.dart';
import 'package:fl_clash/views/observed_dns.dart';
import 'package:fl_clash/views/traffic_statistics.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NetworkToolboxView extends ConsumerStatefulWidget {
  const NetworkToolboxView({super.key});

  @override
  ConsumerState<NetworkToolboxView> createState() => _NetworkToolboxViewState();
}

class _NetworkToolboxViewState extends ConsumerState<NetworkToolboxView> {
  ScrollController? _controller;
  late final RouteTracker _routes;
  ToolboxLayout? _draftLayout;
  var _pageActive = true;

  bool get _editing => _draftLayout != null;

  @override
  void initState() {
    super.initState();
    _routes = ref.read(routeTrackerProvider.notifier)..attach();
    ref.listenManual(appVisibleProvider, (_, visible) {
      if (!visible) _cancelEditing();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= sheetScrollController(context);
    final active =
        PageActivityScope.isActiveOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (_pageActive && !active) _draftLayout = null;
    _pageActive = active;
  }

  @override
  void dispose() {
    _routes.detach();
    _controller?.dispose();
    super.dispose();
  }

  void _beginEditing(ToolboxLayout layout) {
    if (_editing) return;
    setState(() => _draftLayout = layout);
  }

  void _cancelEditing() {
    if (!_editing || !mounted) return;
    setState(() => _draftLayout = null);
  }

  void _commitEditing() {
    final layout = _draftLayout;
    if (layout == null) return;
    final previous = ToolboxLayout.decode(
      ref.read(appSettingProvider).toolboxLayoutJson,
    );
    setState(() => _draftLayout = null);
    if (layout != previous) {
      ref
          .read(appSettingProvider.notifier)
          .update(
            (state) => state.copyWith(toolboxLayoutJson: layout.encode()),
          );
    }
  }

  void _resetEditing() {
    if (!_editing) return;
    setState(() => _draftLayout = ToolboxLayout.defaults());
  }

  void _setSize(ToolboxModuleId module, ToolboxCardSize size) {
    final layout = _draftLayout;
    if (layout == null || layout.sizeOf(module) == size) return;
    setState(() => _draftLayout = layout.withSize(module, size));
  }

  ToolboxCardSize _dragSize(
    ToolboxModuleId module,
    ToolboxCardSize start,
    Offset delta,
    double threshold,
  ) {
    final columnChange = delta.dx.abs() < threshold
        ? 0
        : delta.dx.isNegative
        ? -1
        : 1;
    final rowChange = delta.dy.abs() < threshold
        ? 0
        : delta.dy.isNegative
        ? -1
        : 1;
    if (columnChange == 0 && rowChange == 0) return start;

    ToolboxCardSize? find(int columns, int rows) {
      for (final size in ToolboxCardSize.values) {
        if (module.allows(size) &&
            size.columns == columns &&
            size.rows == rows) {
          return size;
        }
      }
      return null;
    }

    final columns = (start.columns + columnChange).clamp(1, 2).toInt();
    final rows = (start.rows + rowChange).clamp(1, 2).toInt();
    final direct = find(columns, rows);
    if (direct != null) return direct;
    if (columnChange != 0 && rowChange != 0) {
      final horizontalFirst = delta.dx.abs() >= delta.dy.abs();
      final preferred = horizontalFirst
          ? find(columns, start.rows)
          : find(start.columns, rows);
      if (preferred != null) return preferred;
      final alternate = horizontalFirst
          ? find(start.columns, rows)
          : find(columns, start.rows);
      if (alternate != null) return alternate;
    }
    return start;
  }

  Widget _pageFor(ToolboxModuleId module) => switch (module) {
    ToolboxModuleId.exitIp => const ExitIpView(),
    ToolboxModuleId.dnsLookup => const DnsLookupView(),
    ToolboxModuleId.trafficStatistics => const TrafficStatisticsView(),
  };

  Widget _additionalChecks(BuildContext context) {
    final l10n = context.appLocalizations;
    return generateSection(
      title: l10n.toolboxAdditionalChecks,
      items: [
        ListItem.open(
          key: const ValueKey('toolbox-node-delay'),
          leading: const GlyphIcon(AppGlyphs.proxies),
          title: Text(l10n.toolboxNodeDelay),
          widget: const NodeDelayTestView(),
        ),
        ListItem.open(
          key: const ValueKey('toolbox-observed-dns'),
          leading: const GlyphIcon(AppGlyphs.dns),
          title: Text(l10n.toolboxObservedDns),
          widget: const ObservedDnsView(),
        ),
      ],
    );
  }

  Widget _toolbar(BuildContext context) {
    final l10n = context.appLocalizations;
    if (!_editing) {
      return Align(
        alignment: AlignmentDirectional.centerEnd,
        child: TonalButton(
          key: const ValueKey('toolbox-edit-layout'),
          glyph: AppGlyphs.edit,
          label: l10n.toolboxEditLayout,
          onPressed: () => _beginEditing(
            ToolboxLayout.decode(
              ref.read(appSettingProvider).toolboxLayoutJson,
            ),
          ),
        ),
      );
    }
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [
        IconButton(
          key: const ValueKey('toolbox-reset-layout'),
          icon: const GlyphIcon(AppGlyphs.reset),
          tooltip: l10n.toolboxResetLayout,
          onPressed: _resetEditing,
        ),
        TonalButton(
          key: const ValueKey('toolbox-cancel-layout'),
          glyph: AppGlyphs.close,
          label: l10n.cancel,
          onPressed: _cancelEditing,
        ),
        TonalButton(
          key: const ValueKey('toolbox-finish-layout'),
          glyph: AppGlyphs.check,
          label: l10n.toolboxFinishLayout,
          onPressed: _commitEditing,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final savedJson = ref.watch(
      appSettingProvider.select((settings) => settings.toolboxLayoutJson),
    );
    final savedLayout = ToolboxLayout.decode(savedJson);
    final layout = _draftLayout ?? savedLayout;
    final route = ref.watch(routeTrackerProvider);
    final hideIp = ref.watch(
      appSettingProvider.select((settings) => settings.hideIp),
    );
    final exitState = ref.watch(networkDiagnosticsProvider);
    final dnsSummary = ref.watch(toolboxDnsSummaryProvider);
    final trafficStore = ref.watch(trafficHistoryProvider);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _cancelEditing,
      },
      child: Focus(
        autofocus: true,
        onFocusChange: (hasFocus) {
          if (!hasFocus && ModalRoute.of(context)?.isCurrent != false) {
            _cancelEditing();
          }
        },
        child: PopScope(
          canPop: !_editing,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _cancelEditing();
          },
          child: Scaffold(
            title: l10n.networkToolbox,
            body: Builder(
              builder: (context) => PrismListView(
                controller: _controller,
                padding: context.listInsets.page(
                  top: context.contentTopPadding,
                  bottom: 24 + context.bottomInset,
                ),
                itemCount: 1,
                itemBuilder: (context, _) => Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1040),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _toolbar(context),
                        const SizedBox(height: 16),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            const gap = 12.0;
                            final scale = math
                                .max(
                                  1.0,
                                  MediaQuery.textScalerOf(context).scale(1),
                                )
                                .toDouble();
                            final minCellWidth = 154 * scale;
                            final columns =
                                ((constraints.maxWidth + gap) /
                                        (minCellWidth + gap))
                                    .floor()
                                    .clamp(2, 4)
                                    .toInt();
                            final cell = math
                                .max(
                                  1.0,
                                  (constraints.maxWidth - gap * (columns - 1)) /
                                      columns,
                                )
                                .toDouble();
                            final cellHeight = cell * scale;
                            final placements = layout.pack(
                              columnCount: columns,
                            );
                            final rows = placements.fold<int>(
                              0,
                              (count, placement) => math
                                  .max(count, placement.row + placement.rowSpan)
                                  .toInt(),
                            );
                            return SizedBox(
                              width: constraints.maxWidth,
                              height: rows == 0
                                  ? 0
                                  : rows * cellHeight + (rows - 1) * gap,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  for (final placement in placements)
                                    AnimatedPositioned(
                                      key: ValueKey(
                                        'toolbox-placement-${placement.moduleId.id}',
                                      ),
                                      duration: const Duration(
                                        milliseconds: 220,
                                      ),
                                      curve: Curves.easeInOut,
                                      left: placement.column * (cell + gap),
                                      top: placement.row * (cellHeight + gap),
                                      width:
                                          placement.columnSpan * cell +
                                          (placement.columnSpan - 1) * gap,
                                      height:
                                          placement.rowSpan * cellHeight +
                                          (placement.rowSpan - 1) * gap,
                                      child: ToolboxModuleCard(
                                        module: placement.moduleId,
                                        size: placement.size,
                                        editing: _editing,
                                        onSizeChanged: (size) =>
                                            _setSize(placement.moduleId, size),
                                        onDragResize:
                                            (start, delta, threshold) =>
                                                _setSize(
                                                  placement.moduleId,
                                                  _dragSize(
                                                    placement.moduleId,
                                                    start,
                                                    delta,
                                                    threshold,
                                                  ),
                                                ),
                                        summary: switch (placement.moduleId) {
                                          ToolboxModuleId.exitIp =>
                                            ToolboxExitSummary(
                                              size: placement.size,
                                              route: route,
                                              state: exitState,
                                              hideIp: hideIp,
                                            ),
                                          ToolboxModuleId.dnsLookup =>
                                            ToolboxDnsSummaryCard(
                                              size: placement.size,
                                              route: route,
                                              summary: dnsSummary,
                                            ),
                                          ToolboxModuleId.trafficStatistics =>
                                            ListenableBuilder(
                                              listenable: trafficStore,
                                              builder: (context, _) =>
                                                  ToolboxTrafficSummary(
                                                    size: placement.size,
                                                    store: trafficStore,
                                                  ),
                                            ),
                                        },
                                        page: _pageFor(placement.moduleId),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        _additionalChecks(context),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
