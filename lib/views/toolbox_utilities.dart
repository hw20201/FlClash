import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fl_clash/common/ip_lookup.dart';
import 'package:fl_clash/common/network_toolbox.dart';
import 'package:fl_clash/common/speed_test.dart';
import 'package:fl_clash/common/toolbox_utilities.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ToolboxUtility { headers, interfaces, subnet, speedTest, ipLookup }

const _gaugeMarks = [0.0, 5.0, 10.0, 50.0, 100.0, 250.0, 500.0, 750.0, 1000.0];

/// Log-scale position of an Mbps value on the gauge, 0 to 1.
double speedGaugeFraction(double mbps) {
  if (mbps <= 0) return 0;
  final segments = _gaugeMarks.length - 1;
  for (var i = 0; i < segments; i++) {
    final low = _gaugeMarks[i];
    final high = _gaugeMarks[i + 1];
    if (mbps <= high) return (i + (mbps - low) / (high - low)) / segments;
  }
  return 1;
}

String _formatMbps(double value) =>
    '${value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1)} Mbps';

class ToolboxUtilityView extends ConsumerStatefulWidget {
  const ToolboxUtilityView({super.key, required this.tool});
  final ToolboxUtility tool;
  @override
  ConsumerState<ToolboxUtilityView> createState() => _ToolboxUtilityViewState();
}

class _ToolboxUtilityViewState extends ConsumerState<ToolboxUtilityView> {
  final _input = TextEditingController();
  final _port = TextEditingController(text: '443');
  String? _result;
  bool _running = false;
  SpeedTestPhase? _phase;
  double _liveMbps = 0;
  List<double> _latencySamples = const [];
  SpeedtestServer? _server;
  SpeedtestResult? _testResult;
  String? _testError;
  bool _testing = false;
  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';
  String t(String zh, String en) => _zh ? zh : en;
  String get _title => switch (widget.tool) {
    ToolboxUtility.headers => t('HTTP 响应头', 'HTTP headers'),
    ToolboxUtility.interfaces => t('本机 IP', 'Local IP addresses'),
    ToolboxUtility.subnet => t('子网计算', 'Subnet calculator'),
    ToolboxUtility.speedTest => t('网速测试', 'Speed test'),
    ToolboxUtility.ipLookup => t('IP 全能查', 'IP lookup'),
  };
  @override
  void dispose() {
    _input.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (widget.tool == ToolboxUtility.speedTest) return _runSpeedTest();
    setState(() {
      _running = true;
      _result = null;
    });
    String result;
    try {
      switch (widget.tool) {
        case ToolboxUtility.headers:
          final port = int.tryParse(_port.text.trim());
          final host = _input.text.trim();
          if (!validDiagnosticHost(host) ||
              port == null ||
              port < 1 ||
              port > 65535) {
            throw FormatException(
              t('请输入域名或 IP 和有效端口。', 'Enter a hostname/IP and a valid port.'),
            );
          }
          result = await inspectHttpHeaders(
            Uri(scheme: 'https', host: host, port: port),
            const Duration(seconds: 8),
          );
        case ToolboxUtility.interfaces:
          final addresses = await localInterfaceAddresses().timeout(
            const Duration(seconds: 8),
          );
          result = addresses.isEmpty
              ? t(
                  '系统没有返回网卡地址。',
                  'No interface addresses returned by the system.',
                )
              : addresses.join('\n\n');
        case ToolboxUtility.subnet:
          final values = ipv4Subnet(_input.text);
          result =
              '${t('网络', 'Network')}: ${values['network']}\n'
              '${t('子网掩码', 'Netmask')}: ${values['mask']}\n'
              '${t('范围末地址', 'Last address')}: ${values['lastAddress']}\n'
              '${t('主机范围', 'Host range')}: ${values['firstHost']} – ${values['lastHost']}\n'
              '${t('主机数', 'Host count')}: ${values['hosts']}\n\n'
              '${t('/31 按点对点链路计算，/32 为单主机。', '/31 uses point-to-point semantics; /32 is a host route.')}';
        case ToolboxUtility.speedTest:
          // The gauge page runs its own flow; unreachable from this path.
          return;
        case ToolboxUtility.ipLookup:
          final info = await lookupIp(_input.text, const Duration(seconds: 10));
          final place = [
            info.country,
            info.region,
            info.city,
          ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
          result =
              'IP: ${info.ip}\n'
              '${t('归属', 'Location')}: ${place.isEmpty ? '—' : place}\n'
              '${t('运营商', 'ISP')}: ${info.isp ?? '—'}\n'
              '${t('组织', 'Organization')}: ${info.org ?? '—'}\n'
              'ASN: ${info.asn ?? '—'}';
      }
    } catch (error) {
      result = '${t('未完成', 'Could not complete')}: $error';
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _result = result;
    });
  }

  Future<void> _runSpeedTest() async {
    setState(() {
      _testing = true;
      _phase = SpeedTestPhase.latency;
      _liveMbps = 0;
      _latencySamples = const [];
      _server = null;
      _testResult = null;
      _testError = null;
    });
    try {
      final result = await runSpeedtest(
        onProgress: (phase, value) {
          if (!mounted) return;
          setState(() {
            _phase = phase;
            if (phase == SpeedTestPhase.latency) {
              _latencySamples = [..._latencySamples, value];
            } else {
              _liveMbps = value;
            }
          });
        },
        onServerSelected: (server) {
          if (!mounted) return;
          setState(() => _server = server);
        },
      );
      if (!mounted) return;
      setState(() {
        _testing = false;
        _phase = null;
        _testResult = result;
        _server = result.server;
        lastSpeedtestResult.value = result;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _phase = null;
        _testError = '$error';
      });
    }
  }

  double get _bestLatency {
    if (_latencySamples.isEmpty) return 0;
    return _latencySamples.reduce(math.min);
  }

  double get _jitter {
    if (_latencySamples.length < 2) return 0;
    return _latencySamples.reduce(math.max) - _bestLatency;
  }

  double get _gaugeValue {
    final result = _testResult;
    if (_phase == SpeedTestPhase.download || _phase == SpeedTestPhase.upload) {
      return _liveMbps;
    }
    return result?.downloadMbps ?? 0;
  }

  String get _gaugeLabel {
    final result = _testResult;
    if (_testError != null) return t('测速失败', 'Test failed');
    return switch (_phase) {
      SpeedTestPhase.latency => t('正在测延迟…', 'Measuring latency…'),
      SpeedTestPhase.download => t('下载中', 'Downloading'),
      SpeedTestPhase.upload => t('上传中', 'Uploading'),
      null => result == null ? t('就绪', 'Ready') : t('完成', 'Done'),
    };
  }

  String _latencyText() {
    final result = _testResult;
    if (result != null) return '${result.latency.inMilliseconds} ms';
    if (_latencySamples.isNotEmpty) return '${_bestLatency.round()} ms';
    return '—';
  }

  String _jitterText() {
    if (_latencySamples.length < 2) return '—';
    return '${_jitter.round()} ms';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tool == ToolboxUtility.speedTest) return _buildSpeedTest();
    return Scaffold(
      title: _title,
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, context.contentTopPadding, 20, 32),
        children: [
          Text(switch (widget.tool) {
            ToolboxUtility.headers => t(
              '使用设备网络发起 HTTPS HEAD 请求，不跟随重定向、不下载正文。系统 VPN 可能影响路由。',
              'Send an HTTPS HEAD request over the device network. No redirects or body download. System VPN routing may apply.',
            ),
            ToolboxUtility.interfaces => t(
              '仅列出系统允许访问的本机网卡地址，不查询公网出口，不上传设备信息。',
              'List local interfaces exposed by the system. No public-IP lookup or upload.',
            ),
            ToolboxUtility.subnet => t(
              '离线计算 IPv4 子网，无需网络。',
              'Calculate IPv4 subnets offline.',
            ),
            ToolboxUtility.speedTest => t(
              '使用 Speedtest.net 就近节点测下载、上传与延迟。',
              'Measure download, upload and latency against a nearby Speedtest.net server.',
            ),
            ToolboxUtility.ipLookup => t(
              '查公网 IP、归属地与运营商；留空查本机出口 IP。',
              'Look up a public IP, location and ISP. Leave empty to check this device.',
            ),
          }),
          const SizedBox(height: 20),
          if (widget.tool != ToolboxUtility.interfaces)
            TextField(
              controller: _input,
              decoration: InputDecoration(
                hintText: switch (widget.tool) {
                  ToolboxUtility.subnet => '192.168.1.10/24',
                  ToolboxUtility.ipLookup => t(
                    'IP 或域名（留空查本机）',
                    'IP or hostname (empty for this device)',
                  ),
                  _ => t('域名或 IP', 'Hostname or IP'),
                },
              ),
            ),
          if (widget.tool == ToolboxUtility.headers) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _port,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: t('HTTPS 端口', 'HTTPS port'),
              ),
            ),
          ],
          const SizedBox(height: 16),
          TonalButton(
            onPressed: _running ? null : _run,
            label: _running
                ? t('处理中…', 'Working…')
                : switch (widget.tool) {
                    ToolboxUtility.subnet => t('计算', 'Calculate'),
                    ToolboxUtility.speedTest => t('开始测速', 'Run speed test'),
                    ToolboxUtility.ipLookup => t('查询', 'Look up'),
                    _ => t('开始检测', 'Run check'),
                  },
          ),
          if (_result != null) ...[
            const SizedBox(height: 24),
            SelectableText(_result!),
            const SizedBox(height: 16),
            TonalButton(
              label: t('复制结果', 'Copy result'),
              onPressed: () => Clipboard.setData(ClipboardData(text: _result!)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSpeedTest() {
    final colors = context.colorScheme;
    final mode = ref.watch(
      patchClashConfigProvider.select((state) => state.mode),
    );
    final groups = ref.watch(groupsProvider);
    final firstGroup = groups.firstOrNull;
    final selected = ref.watch(
      selectedProxyNameProvider(firstGroup?.name ?? ''),
    );
    final node = mode == Mode.direct
        ? t('直连', 'Direct')
        : (selected == null || selected.isEmpty ? '—' : selected);
    final modeText = switch (mode) {
      Mode.rule => t('规则模式', 'Rule mode'),
      Mode.global => t('全局模式', 'Global mode'),
      Mode.direct => t('直连模式', 'Direct mode'),
    };
    final server = _server;
    final serverText = server == null
        ? '—'
        : '${server.name} · ${server.sponsor} (${server.country})';
    final result = _testResult;
    final gaugeValue = _gaugeValue;
    final hasValue =
        _phase == SpeedTestPhase.download ||
        _phase == SpeedTestPhase.upload ||
        result != null;
    final gaugeColor = _phase == SpeedTestPhase.upload
        ? colors.tertiary
        : colors.primary;
    final gaugeStartColor =
        Color.lerp(
          gaugeColor,
          _phase == SpeedTestPhase.upload ? colors.primary : colors.tertiary,
          0.55,
        ) ??
        gaugeColor;
    return Scaffold(
      title: _title,
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, context.contentTopPadding, 20, 32),
        children: [
          _Surface(
            child: Column(
              children: [
                _InfoRow(label: t('出站节点', 'Outbound'), value: node),
                _InfoRow(label: t('路由', 'Routing'), value: modeText),
                _InfoRow(label: t('测速服务器', 'Test server'), value: serverText),
              ],
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final size = math.min(constraints.maxWidth, 300.0);
              return Center(
                child: _SpeedGauge(
                  size: size,
                  value: gaugeValue,
                  color: gaugeColor,
                  startColor: gaugeStartColor,
                  label: _gaugeLabel,
                  showValue: hasValue,
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _PhaseSteps(phase: _phase, finished: result != null),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              width: 200,
              child: TonalButton(
                onPressed: _testing ? null : _runSpeedTest,
                label: _testing
                    ? t('测速中…', 'Testing…')
                    : result != null || _testError != null
                    ? t('再测一次', 'Test again')
                    : t('开始测速', 'Start test'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: _SpeedTile(
                  glyph: AppGlyphs.arrowDown,
                  label: t('下载', 'Download'),
                  value: result != null
                      ? _formatMbps(result.downloadMbps)
                      : _phase == SpeedTestPhase.download
                      ? _formatMbps(_liveMbps)
                      : '—',
                  active: _phase == SpeedTestPhase.download,
                  color: colors.primary,
                ),
              ),
              Expanded(
                child: _SpeedTile(
                  glyph: AppGlyphs.arrowUp,
                  label: t('上传', 'Upload'),
                  value: result != null
                      ? _formatMbps(result.uploadMbps)
                      : _phase == SpeedTestPhase.upload
                      ? _formatMbps(_liveMbps)
                      : '—',
                  active: _phase == SpeedTestPhase.upload,
                  color: colors.tertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: _SpeedTile(
                  glyph: AppGlyphs.clock,
                  label: t('延迟', 'Latency'),
                  value: _latencyText(),
                  active: _phase == SpeedTestPhase.latency,
                  color: colors.primary,
                ),
              ),
              Expanded(
                child: _SpeedTile(
                  glyph: AppGlyphs.shuffle,
                  label: t('抖动', 'Jitter'),
                  value: _jitterText(),
                  active: false,
                  color: colors.primary,
                ),
              ),
            ],
          ),
          if (_testError != null) ...[
            const SizedBox(height: 16),
            Text(
              '${t('未完成', 'Could not complete')}: $_testError',
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: colors.error),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            t(
              '测速走设备网络，不经过代理；出站节点与路由显示的是当前应用状态。',
              'The test runs on the device network, not through the proxy. The outbound node and routing rows show the current app state.',
            ),
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      decoration: ShapeDecoration(
        color: colors.surface,
        shape: AppShape.all(20).copyWith(
          side: BorderSide(color: colors.onSurface.withValues(alpha: 0.09)),
        ),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(color: context.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: AppTextStyle.footnote.of(context, emphasized: true),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeedGauge extends StatelessWidget {
  const _SpeedGauge({
    required this.size,
    required this.value,
    required this.color,
    required this.startColor,
    required this.label,
    required this.showValue,
  });

  final double size;
  final double value;
  final Color color;
  final Color startColor;
  final String label;
  final bool showValue;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final startColor = this.startColor;
    return SizedBox(
      width: size,
      height: size * 0.92,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: speedGaugeFraction(value)),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        builder: (context, fraction, _) {
          return CustomPaint(
            painter: _GaugePainter(
              fraction: fraction,
              color: color,
              startColor: startColor,
              trackColor: colors.onSurface.withValues(alpha: 0.08),
              needleColor: colors.onSurface,
              labelStyle: AppTextStyle.caption1
                  .of(context)
                  .copyWith(color: colors.onSurfaceVariant),
              passedLabelColor: colors.onSurface,
              showNeedle: showValue,
            ),
            child: Padding(
              padding: EdgeInsets.only(top: size * 0.56),
              child: Column(
                children: [
                  if (!showValue)
                    Text(
                      label,
                      style: AppTextStyle.footnote
                          .of(context)
                          .copyWith(color: colors.onSurfaceVariant),
                    ),
                  Text(
                    showValue ? _formatValue(value) : '—',
                    style: AppTextStyle.display.of(context).toTabular,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GlyphIcon(AppGlyphs.arrowDown, size: 16, color: color),
                      const SizedBox(width: 4),
                      Text(
                        'Mbps',
                        style: AppTextStyle.subheadline
                            .of(context)
                            .copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatValue(double value) =>
      value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({
    required this.fraction,
    required this.color,
    required this.startColor,
    required this.trackColor,
    required this.needleColor,
    required this.labelStyle,
    required this.passedLabelColor,
    required this.showNeedle,
  });

  final double fraction;
  final Color color;
  final Color startColor;
  final Color trackColor;
  final Color needleColor;
  final TextStyle labelStyle;
  final Color passedLabelColor;
  final bool showNeedle;

  static const _start = math.pi * 0.75;
  static const _sweep = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width / 13;
    final center = Offset(size.width / 2, size.width / 2);
    final radius = size.width / 2 - strokeWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawArc(rect, _start, _sweep, false, stroke..color = trackColor);

    final sweep = _sweep * fraction;
    if (fraction > 0.002) {
      canvas.drawArc(
        rect,
        _start,
        sweep,
        false,
        stroke
          ..shader = SweepGradient(
            endAngle: _sweep,
            colors: [startColor, color],
            transform: const GradientRotation(_start),
          ).createShader(rect),
      );
      stroke.shader = null;
    }

    final labelRadius = radius - strokeWidth / 2 - size.width * 0.085;
    final segments = _gaugeMarks.length - 1;
    for (var i = 0; i < _gaugeMarks.length; i++) {
      final position = i / segments;
      final angle = _start + _sweep * position;
      final mark = _gaugeMarks[i];
      final text = i == segments ? '1G+' : mark.toStringAsFixed(0);
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: position <= fraction + 0.001
              ? labelStyle.copyWith(color: passedLabelColor)
              : labelStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelCenter =
          center + Offset(math.cos(angle), math.sin(angle)) * labelRadius;
      painter.paint(
        canvas,
        labelCenter - Offset(painter.width / 2, painter.height / 2),
      );
    }

    if (!showNeedle) return;
    final angle = _start + sweep;
    final direction = Offset(math.cos(angle), math.sin(angle));
    final normal = Offset(-direction.dy, direction.dx);
    final outer = size.width / 2;
    final base = center - direction * outer * 0.1;
    final tip = center + direction * outer * 0.5;
    final baseHalf = outer * 0.06;
    final tipHalf = outer * 0.038;
    final needle = Path()
      ..moveTo(base.dx + normal.dx * baseHalf, base.dy + normal.dy * baseHalf)
      ..lineTo(tip.dx + normal.dx * tipHalf, tip.dy + normal.dy * tipHalf)
      ..lineTo(tip.dx - normal.dx * tipHalf, tip.dy - normal.dy * tipHalf)
      ..lineTo(base.dx - normal.dx * baseHalf, base.dy - normal.dy * baseHalf)
      ..close();
    canvas.drawPath(
      needle,
      Paint()
        ..shader = ui.Gradient.linear(
          base,
          tip,
          [
            needleColor.withValues(alpha: 0),
            needleColor.withValues(alpha: 0.35),
            needleColor.withValues(alpha: 0.9),
          ],
          const [0, 0.4, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(_GaugePainter oldDelegate) {
    return oldDelegate.fraction != fraction ||
        oldDelegate.color != color ||
        oldDelegate.startColor != startColor ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.needleColor != needleColor ||
        oldDelegate.passedLabelColor != passedLabelColor ||
        oldDelegate.showNeedle != showNeedle ||
        oldDelegate.labelStyle != labelStyle;
  }
}

class _PhaseSteps extends StatelessWidget {
  const _PhaseSteps({required this.phase, required this.finished});

  final SpeedTestPhase? phase;
  final bool finished;

  @override
  Widget build(BuildContext context) {
    const phases = [
      SpeedTestPhase.latency,
      SpeedTestPhase.download,
      SpeedTestPhase.upload,
    ];
    final colors = context.colorScheme;
    final currentPhase = phase;
    final currentIndex = finished
        ? phases.length
        : currentPhase == null
        ? -1
        : phases.indexOf(currentPhase);
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < phases.length; i++) ...[
          if (i > 0)
            Container(
              width: 16,
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 5),
              color: i <= currentIndex
                  ? colors.primary.withValues(alpha: 0.5)
                  : colors.outlineVariant,
            ),
          _PhaseDot(
            label: switch (phases[i]) {
              SpeedTestPhase.latency => zh ? '延迟' : 'Latency',
              SpeedTestPhase.download => zh ? '下载' : 'Download',
              SpeedTestPhase.upload => zh ? '上传' : 'Upload',
            },
            done: i < currentIndex,
            active: i == currentIndex,
          ),
        ],
      ],
    );
  }
}

class _PhaseDot extends StatelessWidget {
  const _PhaseDot({
    required this.label,
    required this.done,
    required this.active,
  });

  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final filled = done || active;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: ShapeDecoration(
            color: filled ? colors.primary : colors.outlineVariant,
            shape: AppShape.circle,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTextStyle.caption1
              .of(context)
              .copyWith(
                color: active ? colors.primary : colors.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _SpeedTile extends StatelessWidget {
  const _SpeedTile({
    required this.glyph,
    required this.label,
    required this.value,
    required this.active,
    required this.color,
  });

  final Glyph glyph;
  final String label;
  final String value;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      decoration: ShapeDecoration(
        color: active ? colors.primary.withValues(alpha: 0.08) : colors.surface,
        shape: AppShape.all(16).copyWith(
          side: BorderSide(
            color: active
                ? colors.primary.withValues(alpha: 0.35)
                : colors.onSurface.withValues(alpha: 0.09),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              spacing: 4,
              children: [
                GlyphIcon(glyph, size: 16, color: color),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.footnote
                        .of(context, emphasized: true)
                        .copyWith(color: colors.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.title1
                  .of(context, emphasized: true)
                  .toTabular,
            ),
          ],
        ),
      ),
    );
  }
}
