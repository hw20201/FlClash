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

import '../exit_map/camera.dart';
import '../exit_map/canvas.dart';
import '../exit_map/data.dart';
import '../exit_map/gestures.dart';
import 'card.dart';

class ExitMapCard extends ConsumerStatefulWidget {
  const ExitMapCard({super.key});

  @override
  ConsumerState<ExitMapCard> createState() => _ExitMapCardState();
}

class _ExitMapCardState extends ConsumerState<ExitMapCard>
    with
        WidgetsBindingObserver,
        SingleTickerProviderStateMixin,
        ActivePollingMixin<ExitMapCard>,
        RouteMotionHoldMixin<ExitMapCard>,
        ConnectionCountersMixin<ExitMapCard> {
  final _traffic = ExitMapTraffic();
  late final _camera = ExitMapCamera(this);
  final _mapKey = GlobalKey();
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
    _camera.dispose();
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

  void _takeCameraControl() {
    if (_camera.takeControl()) setState(() {});
  }

  void _resetCamera() => setState(_camera.reset);

  @override
  Widget build(BuildContext context) {
    final strings = context.appLocalizations;
    final originEntry = ref.watch(
      exitMapOriginProvider.select((state) => state.entryOf(directOutbound)),
    );
    final origin = originEntry.value;
    final colors = context.colorScheme;
    final surface = DashboardColors.of(context).tone;
    final scale = DashboardDensityScope.scaleOf(context);
    final animate =
        canPoll &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    final location = origin == null
        ? originEntry.isLoading
              ? strings.exitMapLocating
              : _camera.canReset
              ? strings.unknown
              : strings.exitMapNoOrigin
        : [
            strings.exitMapYou,
            [
              if (origin.approximate) '≈',
              origin.flag,
              if (origin.country == 'CN')
                strings.exitMapChina
              else if (!origin.approximate && origin.city.isNotEmpty)
                origin.city
              else
                origin.country,
            ].where((part) => part.isNotEmpty).join(' '),
          ].where((part) => part.isNotEmpty).join(' · ');
    final percent = NumberFormat.percentPattern(strings.localeName);
    final exitSummary = [
      if (origin != null)
        for (final route in _snapshot.routes.take(2))
          '${route.node} ${percent.format(route.share)}',
      if (origin != null && _snapshot.unlocated > 0)
        strings.exitMapUnlocated(_snapshot.unlocated),
    ].join(' · ');
    return LayoutBuilder(
      builder: (context, constraints) {
        _scheduleMeasure();
        return ExitMapGestureRegion(
          controller: _camera.view,
          mapKey: _mapKey,
          bounds: () => _camera.bounds,
          enabled: canPoll,
          onInteractionStart: _takeCameraControl,
          child: DashboardCard(
            child: SizedBox(
              height: constraints.hasBoundedHeight ? null : 270 * scale,
              child: Column(
                spacing: 10,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DashboardCardHeader(
                    glyph: AppGlyphs.proxies,
                    title: strings.exitMap,
                    trailing: [
                      IconButton(
                        tooltip: strings.reset,
                        onPressed: _camera.canReset ? _resetCamera : null,
                        icon: const GlyphIcon(AppGlyphs.reset),
                      ),
                    ],
                  ),
                  Row(
                    spacing: 7,
                    children: [
                      GlyphIcon(
                        AppGlyphs.target,
                        size: 16,
                        color: colors.tertiary,
                      ),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: animate
                              ? const Duration(milliseconds: 190)
                              : Duration.zero,
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          layoutBuilder: (current, previous) => Stack(
                            alignment: AlignmentDirectional.centerStart,
                            children: [
                              for (final child in previous)
                                ExcludeSemantics(child: child),
                              ?current,
                            ],
                          ),
                          child: EmojiText(
                            location,
                            key: ValueKey(location),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DashboardText.label(
                              context,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: SizedBox(
                      key: _mapKey,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final size = constraints.biggest;
                          if (size.isEmpty || !size.isFinite) {
                            return const SizedBox.shrink();
                          }
                          _camera.layout(
                            size,
                            origin,
                            _snapshot.routes,
                            animate: animate,
                          );
                          return ClipRSuperellipse(
                            key: const ValueKey('exit-map-viewport'),
                            borderRadius: AppRadius.all(DashboardCorner.block),
                            child: ColoredBox(
                              color: surface,
                              child: Semantics(
                                label: exitSummary.isEmpty ? null : exitSummary,
                                child: ExitMapCanvas(
                                  camera: _camera.view,
                                  origin: origin,
                                  routes: _snapshot.routes,
                                  landColor: colors.onSurfaceVariant.withValues(
                                    alpha: 0.22,
                                  ),
                                  routeColor: colors.primary,
                                  originColor: colors.tertiary,
                                  surfaceColor: surface,
                                  animate: animate,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
