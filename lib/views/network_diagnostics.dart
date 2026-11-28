import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/api/dto.dart' show DelayResult;
import 'package:fl_clash/features/network_diagnostics/exit_card.dart'
    show DiagnosticFact, DiagnosticStatus;
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/models/network_diagnostics.dart';
import 'package:fl_clash/providers/network_diagnostics.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

typedef _DelayTarget = ({String group, String proxy, String url});

String diagnosticEndpoint(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null) return '—';
  if (!uri.hasAuthority) {
    return value.split(RegExp('[?#]')).first.split('@').last;
  }
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  ).toString();
}

class NodeDelayTestView extends ConsumerStatefulWidget {
  const NodeDelayTestView({super.key});

  @override
  ConsumerState<NodeDelayTestView> createState() => _NodeDelayTestViewState();
}

class _NodeDelayTestViewState extends ConsumerState<NodeDelayTestView> {
  ScrollController? _controller;
  late RouteTracker _routes;

  @override
  void initState() {
    super.initState();
    _routes = ref.read(routeTrackerProvider.notifier)..attach();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= sheetScrollController(context);
  }

  @override
  void dispose() {
    _routes.detach();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    title: context.appLocalizations.toolboxNodeDelay,
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
          child: const _PolicyPane(),
        ),
      ),
    ),
  );
}

class DiagnosticRuntimeHeading extends ConsumerWidget {
  const DiagnosticRuntimeHeading({super.key, this.action});

  final Widget? action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(routeTrackerProvider);
    final sync = ref.watch(coreStateSyncProvider);
    final profileId = route.live && route.synced && !sync.applying
        ? sync.profileId
        : null;
    final name = ref.watch(
      profilesProvider.select(
        (profiles) => profiles.getProfile(profileId)?.label,
      ),
    );
    final l10n = context.appLocalizations;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: 12,
        children: [
          GlyphIcon(
            AppGlyphs.proxies,
            size: 28,
            color: context.colorScheme.primary,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 3,
              children: [
                Text(
                  name ??
                      (route.live ? l10n.unknown : l10n.diagnosticsNoProfile),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.headline.of(context),
                ),
                Text(
                  route.live
                      ? l10n.diagnosticsCurrentRoute
                      : l10n.diagnosticsOffline,
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: context.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (action != null) Flexible(child: action!),
        ],
      ),
    );
  }
}

class _PolicyPane extends ConsumerStatefulWidget {
  const _PolicyPane();

  @override
  ConsumerState<_PolicyPane> createState() => _PolicyPaneState();
}

class _PolicyPaneState extends ConsumerState<_PolicyPane> {
  String? _group;
  String? _target;
  DelayResult? _result;
  DateTime? _checkedAt;
  var _failed = false;
  var _busy = false;
  var _run = 0;

  @override
  void dispose() {
    _run++;
    super.dispose();
  }

  void _reset() {
    _run++;
    _result = null;
    _checkedAt = null;
    _busy = false;
    _failed = false;
  }

  Group? _effectiveGroup(List<Group> groups) =>
      groups.where((group) => group.name == _group).firstOrNull ??
      groups.firstOrNull;

  List<String> _targets(Group? group) => group == null
      ? const []
      : {group.name, ...group.all.map((proxy) => proxy.name)}.toList();

  _DelayTarget? _effectiveTest(List<Group> groups, String defaultUrl) {
    final group = _effectiveGroup(groups);
    final targets = _targets(group);
    final target = targets.contains(_target) ? _target : targets.firstOrNull;
    return group == null || target == null
        ? null
        : (group: group.name, proxy: target, url: group.testUrl ?? defaultUrl);
  }

  bool _isCurrent(int run, RouteState route, _DelayTarget target) =>
      mounted &&
      run == _run &&
      ref.read(routeTrackerProvider) == route &&
      _effectiveTest(
            ref.read(groupsProvider),
            ref.read(realTestUrlProvider()),
          ) ==
          target;

  Future<void> _test(_DelayTarget target) async {
    final run = ++_run;
    final route = ref.read(routeTrackerProvider);
    setState(() {
      _busy = true;
      _result = null;
      _failed = false;
      _checkedAt = null;
    });
    try {
      final result = await ref
          .read(coreHandlerProvider)
          .api
          .testDelay(target.proxy, url: target.url, timeout: 5000);
      if (!_isCurrent(run, route, target)) {
        return;
      }
      setState(() {
        _result = result;
        _checkedAt = DateTime.now();
      });
    } catch (_) {
      if (_isCurrent(run, route, target)) {
        setState(() {
          _failed = true;
          _checkedAt = DateTime.now();
        });
      }
    } finally {
      if (mounted && run == _run) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final route = ref.watch(routeTrackerProvider);
    final groups = ref.watch(groupsProvider);
    final group = _effectiveGroup(groups);
    final targets = _targets(group);
    final target = targets.contains(_target) ? _target : targets.firstOrNull;
    final defaultUrl = ref.watch(realTestUrlProvider());
    final test = _effectiveTest(groups, defaultUrl);
    ref.listen(groupsProvider, (previous, next) {
      if (_effectiveTest(previous ?? const [], defaultUrl) !=
          _effectiveTest(next, defaultUrl)) {
        setState(_reset);
      }
    });
    ref.listen(realTestUrlProvider(), (previous, next) {
      if (_effectiveTest(groups, previous ?? next) !=
          _effectiveTest(groups, next)) {
        setState(_reset);
      }
    });
    ref.listen(routeTrackerProvider, (_, _) {
      if (mounted) setState(_reset);
    });
    ref.listen(appVisibleProvider, (_, visible) {
      if (!visible && mounted) setState(_reset);
    });
    final exits = ref.watch(networkDiagnosticsProvider);
    final currentExits = <(DiagnosticFamily, DiagnosticExit)>[];
    for (final family in DiagnosticFamily.values) {
      final entry = exits.entryOf(family);
      final stamp = entry.stamp;
      final exit = entry.value;
      if (route.live &&
          stamp != null &&
          route.isFresh(stamp) &&
          exit != null &&
          exit.isSuccess &&
          exit.chains.isNotEmpty) {
        currentExits.add((family, exit));
      }
    }
    final value = _result?.value;
    final failed = _failed || value != null && value < 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DiagnosticRuntimeHeading(),
        generateSection(
          atTop: true,
          title: l10n.diagnosticsTestObject,
          footer: l10n.diagnosticsDelayNote,
          items: [
            if (group != null)
              ListItem<String>.options(
                key: const ValueKey('diagnostics-group'),
                leading: const GlyphIcon(AppGlyphs.proxies),
                title: Text(l10n.proxyGroup),
                options: groups.map((group) => group.name).toList(),
                value: group.name,
                textBuilder: (value) => value,
                onChanged: (value) => setState(() {
                  _group = value;
                  _target = null;
                  _reset();
                }),
              ),
            if (target != null)
              ListItem<String>.options(
                key: const ValueKey('diagnostics-target'),
                leading: const GlyphIcon(AppGlyphs.bolt),
                title: Text(l10n.diagnosticsTestObject),
                options: targets,
                value: target,
                textBuilder: (value) => value,
                onChanged: (value) => setState(() {
                  _target = value;
                  _reset();
                }),
              )
            else
              ListItem(
                title: Text(l10n.diagnosticsChooseGroup),
                subtitle: Text(l10n.diagnosticsOffline),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          radius: AppCorner.xxl,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                spacing: 12,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 4,
                      children: [
                        Text(
                          l10n.delay,
                          style: AppTextStyle.footnote
                              .of(context)
                              .copyWith(
                                color: context.colorScheme.onSurfaceVariant,
                              ),
                        ),
                        Text(
                          value != null && value >= 0 ? '$value ms' : '—',
                          style: AppTextStyle.largeTitle.of(
                            context,
                            emphasized: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: DiagnosticStatus(
                      label: _busy
                          ? l10n.diagnosticsChecking
                          : failed
                          ? value == -1
                                ? l10n.timeout
                                : l10n.diagnosticsUnknownError
                          : value != null
                          ? l10n.diagnosticsAvailable
                          : l10n.diagnosticsNotRun,
                      color: failed
                          ? context.colorScheme.error
                          : value != null
                          ? context.colorScheme.success
                          : context.colorScheme.onSurfaceVariant,
                      loading: _busy,
                    ),
                  ),
                ],
              ),
              if (_result case final result?) ...[
                DiagnosticFact(
                  label: l10n.diagnosticsTestObject,
                  value: result.name,
                ),
                DiagnosticFact(
                  label: l10n.source,
                  value: diagnosticEndpoint(result.url),
                ),
              ],
              if (_checkedAt case final time?)
                DiagnosticFact(
                  label: l10n.diagnosticsCheckedAt,
                  value: DateFormat.Hms().format(time),
                ),
              TonalButton(
                key: const ValueKey('diagnostics-delay-run'),
                size: TonalButtonSize.bar,
                glyph: AppGlyphs.bolt,
                label: l10n.diagnosticsTestDelay,
                onPressed: !route.live || _busy || test == null
                    ? null
                    : () => _test(test),
              ),
            ],
          ),
        ),
        generateSection(
          title: l10n.diagnosticsCurrentRoute,
          footer: l10n.diagnosticsRouteNote,
          items: [
            for (final (family, exit) in currentExits)
              ListItem(
                leading: const GlyphIcon(AppGlyphs.connections),
                title: Text(family == DiagnosticFamily.ipv4 ? 'IPv4' : 'IPv6'),
                subtitle: Text(exit.chains.reversed.join(' → ')),
              ),
            if (currentExits.isEmpty)
              ListItem(title: Text(l10n.diagnosticsNotRun)),
          ],
        ),
      ],
    );
  }
}
