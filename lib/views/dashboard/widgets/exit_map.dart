import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/exit_map.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../exit_map/canvas.dart';
import '../exit_map/data.dart';
import 'card.dart';

class ExitMapCard extends ConsumerStatefulWidget {
  const ExitMapCard({super.key});

  @override
  ConsumerState<ExitMapCard> createState() => _ExitMapCardState();
}

class _ExitMapCardState extends ConsumerState<ExitMapCard>
    with
        WidgetsBindingObserver,
        ActivePollingMixin<ExitMapCard>,
        RouteMotionHoldMixin<ExitMapCard>,
        ConnectionCountersMixin<ExitMapCard> {
  final _traffic = ExitMapTraffic();
  var _snapshot = const ExitMapSnapshot();
  ExitMapOrigin? _originProbe;
  ScrollPosition? _scroll;
  var _onScreen = false;
  var _measurePending = false;
  var _attached = true;

  @override
  Duration get pollInterval => const Duration(seconds: 1);

  @override
  bool get canPoll => _attached && _onScreen && super.canPoll;

  @override
  bool get showsConnectionTraffic => canPoll;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (_scroll != position) {
      _scroll?.removeListener(_scheduleMeasure);
      _scroll = position?..addListener(_scheduleMeasure);
    }
    _scheduleMeasure();
  }

  void _scheduleMeasure() {
    if (_measurePending) return;
    _measurePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurePending = false;
      if (!mounted || !_attached) return;
      final box = context.findRenderObject();
      final viewport = box == null ? null : RenderAbstractViewport.maybeOf(box);
      final visible =
          viewport == null ||
          viewport.paintBounds.overlaps(
            MatrixUtils.transformRect(
              box!.getTransformTo(viewport),
              box.paintBounds,
            ),
          );
      if (visible != _onScreen) setState(() => _onScreen = visible);
      _syncActivity();
    });
  }

  void _syncActivity() {
    syncConnectionCounters();
    if (canPoll) {
      if (_originProbe == null) {
        final probe = ref.read<ExitMapOrigin>(exitMapOriginProvider.notifier);
        probe.watch(directOutbound);
        _originProbe = probe;
      }
      startPolling();
    } else {
      _originProbe?.unwatch(directOutbound);
      _originProbe = null;
      stopPolling();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _syncActivity();
    if (mounted) setState(() {});
  }

  @override
  void deactivate() {
    _attached = false;
    _syncActivity();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _attached = true;
    _scheduleMeasure();
  }

  @override
  void dispose() {
    _scroll?.removeListener(_scheduleMeasure);
    _originProbe?.unwatch(directOutbound);
    super.dispose();
  }

  @override
  Future<void> poll(PollGuard isCurrent) async {
    final next = _traffic.snapshot(
      ref.read(coreStatusProvider) == CoreStatus.connected
          ? ref.read(connectionBookProvider).list()
          : const [],
    );
    if (identical(next, _snapshot)) return;
    updateWhenRouteSettled(() {
      if (isCurrent()) setState(() => _snapshot = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.appLocalizations;
    final originEntry = ref.watch(
      exitMapOriginProvider.select((state) => state.entryOf(directOutbound)),
    );
    final origin = originEntry.value;
    final colors = context.colorScheme;
    final scale = DashboardDensityScope.scaleOf(context);
    final location = origin == null
        ? ''
        : [
            if (origin.approximate) '≈',
            origin.flag,
            origin.city,
          ].where((part) => part.isNotEmpty).join(' ');
    final you = location.isEmpty
        ? strings.exitMapYou
        : '${strings.exitMapYou} · $location';
    final status = origin == null
        ? originEntry.isLoading
              ? strings.exitMapLocating
              : strings.exitMapNoOrigin
        : _snapshot.routes.isEmpty
        ? strings.exitMapNoTraffic
        : strings.exitMapTrafficHint;
    final percent = NumberFormat.percentPattern(strings.localeName);
    final exits = _snapshot.routes
        .take(2)
        .map((route) => '${route.node} ${percent.format(route.share)}')
        .join(' · ');
    final summary = [
      if (origin != null && exits.isNotEmpty) exits,
      status,
      if (_snapshot.unlocated > 0)
        strings.exitMapUnlocated(_snapshot.unlocated),
    ].join(' · ');
    return LayoutBuilder(
      builder: (context, constraints) {
        _scheduleMeasure();
        return DashboardCard(
          child: SizedBox(
            height: constraints.hasBoundedHeight ? null : 250 * scale,
            child: Column(
              spacing: 10,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DashboardCardHeader(
                  glyph: AppGlyphs.proxies,
                  title: strings.exitMap,
                ),
                Text(
                  you,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.label(context),
                ),
                Expanded(
                  child: ExcludeSemantics(
                    child: ExitMapCanvas(
                      origin: origin,
                      routes: _snapshot.routes,
                      landColor: colors.onSurfaceVariant.withValues(
                        alpha: 0.28,
                      ),
                      routeColor: colors.primary,
                      originColor: colors.tertiary,
                      animate: canPoll,
                    ),
                  ),
                ),
                Text(
                  summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.label(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
