import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/api/dto.dart';
import 'package:fl_clash/features/dns_lookup/controller.dart';
import 'package:fl_clash/features/form/form_row.dart';
import 'package:fl_clash/features/network_diagnostics/exit_card.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/toolbox_dns_summary.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DnsLookupView extends ConsumerStatefulWidget {
  const DnsLookupView({super.key});

  @override
  ConsumerState<DnsLookupView> createState() => _DnsLookupViewState();
}

class _DnsLookupViewState extends ConsumerState<DnsLookupView> {
  final _name = TextEditingController();
  late final DnsLookupController _lookup;
  late final RouteTracker _routes;
  ScrollController? _scroll;
  var _type = 'A';
  var _pageActive = true;

  @override
  void initState() {
    super.initState();
    _lookup = DnsLookupController(
      query: (name, type, cancellation) => ref
          .read(coreHandlerProvider)
          .api
          .queryDns(
            name,
            type: type,
            timeout: const Duration(seconds: 8),
            cancellation: cancellation,
          ),
    );
    _routes = ref.read(routeTrackerProvider.notifier)..attach();
    ref.listenManual(routeTrackerProvider, (previous, next) {
      if (previous == null) return;
      if (previous.coreEpoch != next.coreEpoch ||
          previous.routeVersion != next.routeVersion ||
          previous.hostEpoch != next.hostEpoch ||
          previous.proxied != next.proxied ||
          previous.picks != next.picks ||
          previous.synced != next.synced ||
          previous.live != next.live) {
        _lookup.invalidate();
      }
    });
    ref.listenManual(appVisibleProvider, (_, visible) {
      if (!visible) _lookup.cancel();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scroll ??= sheetScrollController(context);
    final active =
        PageActivityScope.isActiveOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (_pageActive && !active) _lookup.cancel();
    _pageActive = active;
  }

  @override
  void dispose() {
    _lookup.dispose();
    _routes.detach();
    _scroll?.dispose();
    _name.dispose();
    super.dispose();
  }

  bool get _connected {
    final route = ref.read(routeTrackerProvider);
    return _pageActive &&
        ref.read(appVisibleProvider) &&
        route.live &&
        route.synced;
  }

  bool get _available =>
      _connected && !ref.read(coreStateSyncProvider).applying;

  Future<void> _run() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final route = ref.read(routeTrackerProvider);
    final stamp = RouteStamp(
      coreEpoch: route.coreEpoch,
      routeVersion: route.routeVersion,
      hostEpoch: route.hostEpoch,
      proxied: route.proxied,
      picks: route.picks,
    );
    ref.read(toolboxDnsSummaryProvider.notifier).clear();
    await _lookup.query(_name.text, _type, available: _available);
    if (!mounted) return;
    final state = _lookup.state;
    final currentRoute = ref.read(routeTrackerProvider);
    if (state.phase == DnsLookupPhase.idle ||
        state.phase == DnsLookupPhase.loading ||
        (state.phase == DnsLookupPhase.cancelled && !_available) ||
        (state.phase == DnsLookupPhase.complete && state.result == null)) {
      return;
    }
    final sameRoute =
        currentRoute.coreEpoch == stamp.coreEpoch &&
        currentRoute.routeVersion == stamp.routeVersion &&
        currentRoute.hostEpoch == stamp.hostEpoch &&
        currentRoute.proxied == stamp.proxied &&
        currentRoute.picks == stamp.picks &&
        currentRoute.live == route.live &&
        currentRoute.synced == route.synced;
    final phase = state.phase == DnsLookupPhase.stale || !sameRoute
        ? DnsLookupPhase.stale
        : state.phase;
    final summary = ToolboxDnsQuerySummary(
      domain: state.name,
      type: state.type,
      phase: phase,
      result: state.result,
      checkedAt:
          state.checkedAt ??
          (phase == DnsLookupPhase.stale ? null : DateTime.now()),
      elapsed: state.elapsed,
      stamp: stamp,
      routeLive: route.live,
      routeSynced: route.synced,
    );
    ref.read(toolboxDnsSummaryProvider.notifier).publish(summary);
  }

  Future<void> _copy() async {
    final state = _lookup.state;
    final result = state.result;
    if (!state.canCopy || result == null) return;
    final l10n = context.appLocalizations;
    final report = StringBuffer()
      ..writeln(l10n.dnsLookup)
      ..writeln('${l10n.domain}: ${state.name}')
      ..writeln('${l10n.dnsLookupRecordType}: ${state.type}')
      ..writeln('${l10n.dnsLookupResolver}: ${l10n.dnsLookupResolverDesc}')
      ..writeln(l10n.dnsLookupMetadataUnavailable)
      ..writeln(
        '${l10n.diagnosticsCheckedAt}: ${state.checkedAt?.toIso8601String()}',
      )
      ..writeln('${l10n.elapsed}: ${state.elapsed!.inMilliseconds} ms')
      ..writeln(
        '${l10n.responseCode}: ${dnsResponseCodeLabel(result.rcode)} (${result.rcode})',
      )
      ..writeln('${l10n.dnsLookupFlags}: ${_flags(result)}');
    for (final (label, records) in [
      (l10n.answers, result.answers),
      (l10n.dnsLookupAuthorities, result.authorities),
      (l10n.dnsLookupAdditionals, result.additionals),
    ]) {
      report.writeln('\n$label (${records.length})');
      for (final record in records) {
        report.writeln(
          '${record.name}\t${record.ttl}\t${dnsRecordTypeLabel(record.rtype)}\t${record.data}',
        );
      }
    }
    try {
      await Clipboard.setData(ClipboardData(text: report.toString()));
      if (mounted) {
        dialogs.showBanner(l10n.copySuccess, level: BannerLevel.success);
      }
    } catch (_) {
      if (mounted) {
        dialogs.showBanner(l10n.clipboardWriteFailed, level: BannerLevel.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    ref.watch(routeTrackerProvider);
    ref.watch(appVisibleProvider);
    return ListenableBuilder(
      listenable: _lookup,
      builder: (context, _) {
        final state = _lookup.state;
        return Scaffold(
          title: l10n.dnsLookup,
          iconActions: [
            IconButtonData(
              glyph: AppGlyphs.copy,
              tooltip: l10n.dnsLookupCopy,
              onPressed: state.canCopy ? _copy : null,
            ),
          ],
          body: Builder(
            builder: (context) => PrismListView(
              key: const ValueKey('dns-lookup-list'),
              controller: _scroll,
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
                      generateSection(
                        title: l10n.dnsLookupResolver,
                        items: [
                          FormRow(
                            title: l10n.dnsLookupName,
                            invalid: state.phase == DnsLookupPhase.invalid,
                            trailing: FormRowTextField(
                              key: const ValueKey('dns-lookup-name'),
                              controller: _name,
                              hintText: l10n.dnsLookupNameHint,
                              keyboardType: TextInputType.url,
                              textInputAction: TextInputAction.search,
                              autocorrect: false,
                              onChanged: (_) => _lookup.reset(),
                              onFieldSubmitted: (_) => unawaited(_run()),
                            ),
                          ),
                          ListItem<String>.options(
                            key: const ValueKey('dns-lookup-type'),
                            title: Text(l10n.dnsLookupRecordType),
                            value: _type,
                            options: dnsLookupTypes,
                            textBuilder: (type) => type,
                            onChanged: (value) {
                              if (!mounted) return;
                              _lookup.reset();
                              setState(() => _type = value);
                            },
                          ),
                        ],
                        footer: l10n.dnsLookupResolverDesc,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TonalButton(
                              key: ValueKey(
                                state.isLoading
                                    ? 'dns-lookup-cancel'
                                    : 'dns-lookup-run',
                              ),
                              glyph: state.isLoading
                                  ? AppGlyphs.close
                                  : AppGlyphs.search,
                              label: state.isLoading
                                  ? l10n.cancel
                                  : l10n.dnsLookupRun,
                              onPressed: state.isLoading
                                  ? _lookup.cancel
                                  : () => unawaited(_run()),
                            ),
                          ],
                        ),
                      ),
                      if (!_connected && !state.isLoading)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            l10n.dnsLookupUnavailable,
                            style: AppTextStyle.footnote
                                .of(context)
                                .copyWith(
                                  color: context.colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      if (state.result case final result?)
                        _DnsResponseCard(state: state, result: result)
                      else
                        _DnsLookupMessage(state: state),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

String _flags(DnsQueryResult result) => [
  'TC=${result.truncated ? 1 : 0}',
  'RD=${result.recursionDesired ? 1 : 0}',
  'RA=${result.recursionAvailable ? 1 : 0}',
  'AD=${result.authenticData ? 1 : 0}',
  'CD=${result.checkingDisabled ? 1 : 0}',
].join('  ');

class _DnsLookupMessage extends StatelessWidget {
  const _DnsLookupMessage({required this.state});

  final DnsLookupState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final label = switch (state.phase) {
      DnsLookupPhase.idle => l10n.dnsLookupEmptyTitle,
      DnsLookupPhase.loading => l10n.dnsLookupQuerying,
      DnsLookupPhase.invalid => l10n.dnsLookupInvalidName,
      DnsLookupPhase.unavailable => l10n.dnsLookupUnavailable,
      DnsLookupPhase.timedOut => l10n.dnsLookupTimedOut,
      DnsLookupPhase.failed => l10n.dnsLookupFailed,
      DnsLookupPhase.cancelled => l10n.dnsLookupCancelled,
      DnsLookupPhase.stale => l10n.dnsLookupStale,
      DnsLookupPhase.complete => l10n.dnsLookupNoRecords,
    };
    final error = switch (state.phase) {
      DnsLookupPhase.invalid ||
      DnsLookupPhase.timedOut ||
      DnsLookupPhase.failed => true,
      _ => false,
    };
    return Card(
      key: ValueKey('dns-lookup-${state.phase.name}'),
      radius: AppCorner.xxl,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          if (state.isLoading)
            const RepaintBoundary(child: ActivityIndicator(size: 24))
          else
            GlyphIcon(
              AppGlyphs.dns,
              size: 28,
              color: error
                  ? context.colorScheme.error
                  : context.colorScheme.primary,
            ),
          Text(label, style: AppTextStyle.headline.of(context)),
          Text(
            state.isLoading
                ? l10n.dnsLookupCancelNote
                : l10n.dnsLookupEmptyDesc,
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(color: context.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _DnsResponseCard extends StatelessWidget {
  const _DnsResponseCard({required this.state, required this.result});

  final DnsLookupState state;
  final DnsQueryResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final error = result.rcode != 0;
    final color = error
        ? context.colorScheme.error
        : result.truncated || result.answers.isEmpty
        ? context.colorScheme.warning
        : context.colorScheme.success;
    return Card(
      key: const ValueKey('dns-lookup-result'),
      radius: AppCorner.xxl,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              Text(l10n.result, style: AppTextStyle.headline.of(context)),
              DiagnosticStatus(
                label: dnsResponseCodeLabel(result.rcode),
                color: color,
              ),
            ],
          ),
          SelectableText(
            state.name,
            style: AppTextStyle.title3.of(context, emphasized: true),
          ),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              Text(state.type, style: AppTextStyle.subheadline.of(context)),
              Text(
                '${l10n.elapsed}: ${state.elapsed!.inMilliseconds} ms',
                style: AppTextStyle.subheadline.of(context),
              ),
            ],
          ),
          if (result.rcode == 3 ||
              error ||
              result.answers.isEmpty ||
              result.truncated)
            Text(
              result.rcode == 3
                  ? l10n.dnsLookupNameNotFound
                  : error
                  ? l10n.dnsLookupResponseError
                  : result.truncated
                  ? l10n.diagnosticsPartial
                  : l10n.dnsLookupNoRecords,
              style: AppTextStyle.subheadline
                  .of(context)
                  .copyWith(color: color),
            ),
          for (final (label, records) in [
            (l10n.answers, result.answers),
            (l10n.dnsLookupAuthorities, result.authorities),
            (l10n.dnsLookupAdditionals, result.additionals),
          ])
            if (records.isNotEmpty) _DnsRecords(label: label, records: records),
          Text(
            '${l10n.dnsLookupFlags}\n${_flags(result)}',
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(color: context.colorScheme.onSurfaceVariant),
          ),
          Text(
            '${l10n.diagnosticsCheckedAt}: ${state.checkedAt!.toLocal().toString().split('.').first}',
            style: AppTextStyle.caption1
                .of(context)
                .copyWith(color: context.colorScheme.onSurfaceVariant),
          ),
          Text(
            l10n.dnsLookupMetadataUnavailable,
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(color: context.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _DnsRecords extends StatelessWidget {
  const _DnsRecords({required this.label, required this.records});

  final String label;
  final List<DnsRecordDto> records;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        Text(
          '$label (${records.length})',
          style: AppTextStyle.headline.of(context),
        ),
        for (final record in records)
          SurfaceScope(
            level: context.raisedSurfaceLevel,
            child: Builder(
              builder: (context) => Container(
                padding: const EdgeInsets.all(14),
                decoration: ShapeDecoration(
                  color: context.surfaceLevel.colorOf(context.colorScheme),
                  shape: AppShape.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 8,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        Text(
                          dnsRecordTypeLabel(record.rtype),
                          style: AppTextStyle.subheadline.of(
                            context,
                            emphasized: true,
                          ),
                        ),
                        Text(
                          '${context.appLocalizations.dnsLookupTtl}: ${record.ttl}',
                          style: AppTextStyle.caption1.of(context),
                        ),
                      ],
                    ),
                    SelectableText(
                      record.name,
                      style: AppTextStyle.footnote.of(context),
                    ),
                    SelectableText(
                      record.data,
                      style: AppTextStyle.body.of(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
