import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/network_diagnostics/exit_card.dart';
import 'package:fl_clash/models/network_diagnostics.dart';
import 'package:fl_clash/providers/network_diagnostics.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/network_diagnostics.dart'
    show DiagnosticRuntimeHeading;
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ExitIpView extends ConsumerStatefulWidget {
  const ExitIpView({super.key});

  @override
  ConsumerState<ExitIpView> createState() => _ExitIpViewState();
}

class _ExitIpViewState extends ConsumerState<ExitIpView> {
  ScrollController? _controller;
  late RouteTracker _routes;
  late NetworkDiagnostics _probe;

  @override
  void initState() {
    super.initState();
    _routes = ref.read(routeTrackerProvider.notifier)..attach();
    _probe = ref.read(networkDiagnosticsProvider.notifier);
    for (final family in DiagnosticFamily.values) {
      _probe.watch(family);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= sheetScrollController(context);
  }

  @override
  void dispose() {
    for (final family in DiagnosticFamily.values) {
      _probe.unwatch(family);
    }
    _routes.detach();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final state = ref.watch(networkDiagnosticsProvider);
    final live = ref.watch(routeTrackerProvider.select((state) => state.live));
    final busy = DiagnosticFamily.values.any(state.isLoading);
    return Scaffold(
      title: l10n.toolboxExitIp,
      body: PrismListView(
        key: const ValueKey('network-diagnostics-list'),
        controller: _controller,
        padding: context.listInsets.page(
          top: context.sectionsTopPadding,
          bottom: 24 + context.bottomInset,
        ),
        itemCount: 1,
        itemBuilder: (_, _) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 928),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DiagnosticRuntimeHeading(
                  action: TonalButton(
                    key: const ValueKey('diagnostics-run'),
                    glyph: AppGlyphs.refresh,
                    label: busy
                        ? l10n.diagnosticsChecking
                        : l10n.diagnosticsRun,
                    onPressed: !live || busy
                        ? null
                        : () => _probe.refresh(DiagnosticFamily.values),
                  ),
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cards = [
                      for (final family in DiagnosticFamily.values)
                        DiagnosticExitCard(
                          family: family,
                          entry: state.entryOf(family),
                        ),
                    ];
                    return constraints.maxWidth >= 680
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 16,
                            children: [
                              for (final card in cards) Expanded(child: card),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: 12,
                            children: cards,
                          );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
