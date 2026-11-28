import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dns_lookup.dart';
import 'package:fl_clash/views/network_diagnostics.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';

class NetworkToolboxView extends StatefulWidget {
  const NetworkToolboxView({super.key});

  @override
  State<NetworkToolboxView> createState() => _NetworkToolboxViewState();
}

class _NetworkToolboxViewState extends State<NetworkToolboxView> {
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
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return Scaffold(
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const gap = 12.0;
                  final minWidth =
                      280 * MediaQuery.textScalerOf(context).scale(1);
                  final columns =
                      ((constraints.maxWidth + gap) / (minWidth + gap))
                          .floor()
                          .clamp(1, 3);
                  final width =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  final cards = [
                    _ToolboxCard(
                      key: const ValueKey('toolbox-network-diagnostics'),
                      glyph: AppGlyphs.connections,
                      title: l10n.networkDiagnostics,
                      description: l10n.networkDiagnosticsDesc,
                      page: const NetworkDiagnosticsView(),
                    ),
                    _ToolboxCard(
                      key: const ValueKey('toolbox-dns-lookup'),
                      glyph: AppGlyphs.dns,
                      title: l10n.dnsLookup,
                      description: l10n.dnsLookupDesc,
                      page: const DnsLookupView(),
                    ),
                    _ToolboxCard(
                      key: const ValueKey('toolbox-traffic'),
                      glyph: AppGlyphs.dataUsage,
                      title: l10n.trafficUsage,
                      description: l10n.toolboxTrafficDesc,
                      page: const NetworkDiagnosticsView(
                        initialTab: NetworkDiagnosticTab.traffic,
                      ),
                    ),
                  ];
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final card in cards)
                        SizedBox(width: width, child: card),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolboxCard extends StatelessWidget {
  const _ToolboxCard({
    super.key,
    required this.glyph,
    required this.title,
    required this.description,
    required this.page,
  });

  final Glyph glyph;
  final String title;
  final String description;
  final Widget page;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    Widget card(VoidCallback open) => Card(
      shape: AppShape.lg,
      padding: const EdgeInsets.all(20),
      onPressed: open,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GlyphIcon(glyph, size: 28),
                GlyphIcon(
                  AppGlyphs.chevronForward,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(title, style: AppTextStyle.headline.of(context)),
            const SizedBox(height: 6),
            Text(
              description,
              style: AppTextStyle.subheadline
                  .of(context)
                  .copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
    if (context.isMobileView) {
      return OpenContainer<void>(
        closedShape: AppShape.lg,
        closedBuilder: (_, open) => card(open),
        openBuilder: (_, _) => page,
      );
    }
    return card(() => showNestedExtend<void>(context, builder: (_) => page));
  }
}
