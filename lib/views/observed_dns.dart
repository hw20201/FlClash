import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/common.dart' show DnsQueryExt;
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/network_diagnostics.dart'
    show diagnosticEndpoint;
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ObservedDnsView extends ConsumerStatefulWidget {
  const ObservedDnsView({super.key});

  @override
  ConsumerState<ObservedDnsView> createState() => _ObservedDnsViewState();
}

class _ObservedDnsViewState extends ConsumerState<ObservedDnsView> {
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
    title: context.appLocalizations.toolboxObservedDns,
    body: PrismListView(
      key: const ValueKey('observed-dns-list'),
      controller: _controller,
      padding: context.listInsets.page(
        top: context.sectionsTopPadding,
        bottom: 24 + context.bottomInset,
      ),
      itemCount: 1,
      itemBuilder: (_, _) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 928),
          child: const _ObservedDnsContent(),
        ),
      ),
    ),
  );
}

class _ObservedDnsContent extends ConsumerWidget {
  const _ObservedDnsContent();

  Future<void> _explain(BuildContext context) => showNestedSheet<void>(
    context,
    builder: (context) => Scaffold(
      title: context.appLocalizations.diagnosticsObservedDns,
      body: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          context.contentTopPadding + 24,
          24,
          24,
        ),
        child: Text(
          context.appLocalizations.diagnosticsDnsNote,
          style: AppTextStyle.body.of(context),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queries = ref.watch(dnsQueriesProvider.select((state) => state.list));
    final l10n = context.appLocalizations;
    final recent = queries.reversed.take(3).toList();
    return generateSection(
      atTop: true,
      title: l10n.diagnosticsObservedDns,
      actions: [
        IconButtonData(
          glyph: AppGlyphs.info,
          tooltip: l10n.diagnosticsDetails,
          onPressed: () => _explain(context),
        ),
      ],
      footer: l10n.diagnosticsDnsUnverified,
      items: recent.isEmpty
          ? [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.dns),
                title: Text(l10n.diagnosticsNoDns),
              ),
            ]
          : [
              for (final query in recent)
                ListItem(
                  title: Text(
                    query.domain,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${query.type} · ${query.cached ? l10n.cache : diagnosticEndpoint(query.upstream)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    query.isFailed ? l10n.error : '${query.delay} ms',
                    style: AppTextStyle.footnote
                        .of(context)
                        .copyWith(
                          color: query.isFailed
                              ? context.colorScheme.error
                              : context.colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
            ],
    );
  }
}
