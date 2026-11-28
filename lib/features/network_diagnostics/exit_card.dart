import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/network_diagnostics.dart';
import 'package:fl_clash/providers/routed_probe.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

String diagnosticErrorLabel(BuildContext context, DiagnosticErrorKind error) {
  final l10n = context.appLocalizations;
  return switch (error) {
    DiagnosticErrorKind.dns => l10n.diagnosticsDnsError,
    DiagnosticErrorKind.connect => l10n.diagnosticsConnectError,
    DiagnosticErrorKind.tls => l10n.diagnosticsTlsError,
    DiagnosticErrorKind.timeout => l10n.timeout,
    DiagnosticErrorKind.http => l10n.diagnosticsHttpError,
    DiagnosticErrorKind.unavailable => l10n.diagnosticsUnavailable,
    DiagnosticErrorKind.invalidResponse => l10n.diagnosticsInvalidResponse,
    DiagnosticErrorKind.familyMismatch => l10n.diagnosticsFamilyMismatch,
    DiagnosticErrorKind.unknown => l10n.diagnosticsUnknownError,
  };
}

class DiagnosticStatus extends StatelessWidget {
  const DiagnosticStatus({
    super.key,
    required this.label,
    required this.color,
    this.loading = false,
  });

  final String label;
  final Color color;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: ShapeDecoration(
        color: color.withValues(alpha: .1),
        shape: AppShape.full,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          if (loading)
            const RepaintBoundary(child: ActivityIndicator(size: 12))
          else
            SizedBox(
              width: 6,
              height: 6,
              child: DecoratedBox(
                decoration: ShapeDecoration(color: color, shape: AppShape.full),
              ),
            ),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption1
                  .of(context, emphasized: true)
                  .copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class DiagnosticFact extends StatelessWidget {
  const DiagnosticFact({
    super.key,
    required this.label,
    required this.value,
    this.selectable = false,
  });

  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyle.subheadline.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: style.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: selectable
                ? SelectableText(value, textAlign: TextAlign.end, style: style)
                : Text(value, textAlign: TextAlign.end, style: style),
          ),
        ],
      ),
    );
  }
}

class DiagnosticExitCard extends StatelessWidget {
  const DiagnosticExitCard({
    super.key,
    required this.family,
    required this.entry,
  });

  final DiagnosticFamily family;
  final ProbeEntry<DiagnosticExit> entry;

  Future<void> _details(BuildContext context, DiagnosticExit result) {
    return showNestedSheet<void>(
      context,
      builder: (context) {
        final l10n = context.appLocalizations;
        final time = DateFormat.yMd().add_Hms().format(
          result.checkedAt.toLocal(),
        );
        return Scaffold(
          title:
              '${family == DiagnosticFamily.ipv4 ? 'IPv4' : 'IPv6'} · ${l10n.diagnosticsDetails}',
          body: PrismListView(
            itemCount: 1,
            padding: context.listInsets.page(
              top: context.sectionsTopPadding,
              bottom: 20 + context.bottomInset,
            ),
            itemBuilder: (_, _) => generateSection(
              atTop: true,
              items: [
                for (final (label, value) in [
                  (l10n.source, result.source),
                  (l10n.diagnosticsCheckedAt, time),
                  if (result.address case final address?) ('IP', address),
                  if (result.country != null || result.region != null)
                    (
                      l10n.country,
                      [
                        result.country,
                        result.region,
                      ].whereType<String>().join(' · '),
                    ),
                  if (result.asn case final asn?) (l10n.diagnosticsAsn, asn),
                  if (result.organization case final organization?)
                    (l10n.diagnosticsOrganization, organization),
                  if (result.geoSource case final source?)
                    (l10n.diagnosticsDetails, source),
                  if (result.errorKind case final error?)
                    (l10n.error, diagnosticErrorLabel(context, error)),
                  if (result.enrichmentErrorKind case final error?)
                    (
                      l10n.diagnosticsPartial,
                      diagnosticErrorLabel(context, error),
                    ),
                  if (result.chains.isNotEmpty)
                    (
                      l10n.diagnosticsCurrentRoute,
                      result.chains.reversed.join(' → '),
                    ),
                ])
                  ListItem(title: Text(label), subtitle: SelectableText(value)),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final result = entry.value;
    final loading = entry.isLoading;
    final success = result?.isSuccess ?? false;
    final partial = success && result?.enrichmentErrorKind != null;
    final color = loading || result == null
        ? context.colorScheme.onSurfaceVariant
        : success
        ? partial
              ? context.colorScheme.warning
              : context.colorScheme.success
        : context.colorScheme.error;
    final label = loading
        ? l10n.diagnosticsChecking
        : result == null
        ? l10n.diagnosticsNotRun
        : success
        ? partial
              ? l10n.diagnosticsPartial
              : l10n.diagnosticsAvailable
        : diagnosticErrorLabel(
            context,
            result.errorKind ?? DiagnosticErrorKind.unknown,
          );
    final location = [
      result?.country,
      result?.region,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    return Card(
      key: ValueKey('diagnostics-exit-${family.name}'),
      radius: AppCorner.xxl,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          Row(
            spacing: 12,
            children: [
              Expanded(
                child: Text(
                  family == DiagnosticFamily.ipv4 ? 'IPv4' : 'IPv6',
                  style: AppTextStyle.headline.of(context),
                ),
              ),
              Flexible(
                child: DiagnosticStatus(
                  label: label,
                  color: color,
                  loading: loading,
                ),
              ),
            ],
          ),
          SelectableText(
            result?.address ?? '—',
            style:
                (family == DiagnosticFamily.ipv4
                        ? AppTextStyle.title1
                        : AppTextStyle.title3)
                    .of(context, emphasized: true),
          ),
          if (location.isNotEmpty)
            Text(location, style: AppTextStyle.subheadline.of(context)),
          if (result?.organization case final organization?)
            Text(
              organization,
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
          if (result != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              spacing: 8,
              children: [
                Expanded(
                  child: Text(
                    [
                      ?result.asn,
                      DateFormat.Hm().format(result.checkedAt.toLocal()),
                    ].join(' · '),
                    style: AppTextStyle.caption1
                        .of(context)
                        .copyWith(color: context.colorScheme.onSurfaceVariant),
                  ),
                ),
                if (result.address case final address?)
                  IconButton(
                    icon: const GlyphIcon(AppGlyphs.copy),
                    tooltip: l10n.copy,
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: address)),
                  ),
                IconButton(
                  icon: const GlyphIcon(AppGlyphs.info),
                  tooltip: l10n.diagnosticsDetails,
                  onPressed: () => _details(context, result),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
