import 'package:fl_clash/common/network_toolbox.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter/widgets.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ToolboxDiagnostic { all, dns, tcp, https, tls }

/// Independent diagnostics inspired by a network toolbox; DNS and TCP use the
/// platform network, as does the TLS inspection. The HTTP probe uses the core.
class NetworkToolboxView extends ConsumerStatefulWidget {
  const NetworkToolboxView({super.key, this.initial = ToolboxDiagnostic.all});
  final ToolboxDiagnostic initial;

  @override
  ConsumerState<NetworkToolboxView> createState() => _NetworkToolboxViewState();
}

class _NetworkToolboxViewState extends ConsumerState<NetworkToolboxView> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '443');
  String? _dns, _tcp, _route, _tls, _error;
  bool _running = false;
  ToolboxDiagnostic _selected = ToolboxDiagnostic.all;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';
  String t(String zh, String en) => _zh ? zh : en;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim());
    final needsPort = _selected != ToolboxDiagnostic.dns;
    if (!validDiagnosticHost(host) ||
        (needsPort && (port == null || port < 1 || port > 65535))) {
      setState(
        () => _error = t(
          needsPort ? '请输入域名或 IP，以及 1–65535 的端口。' : '请输入域名或 IP。',
          needsPort
              ? 'Enter a hostname or IP and a port from 1 to 65535.'
              : 'Enter a hostname or IP.',
        ),
      );
      return;
    }
    setState(() {
      _running = true;
      _dns = _tcp = _route = _tls = _error = null;
    });
    const timeout = Duration(seconds: 8);
    final isChinese = _zh;
    String label(String zh, String en) => isChinese ? zh : en;
    final dns =
        _selected == ToolboxDiagnostic.all || _selected == ToolboxDiagnostic.dns
        ? () async {
            try {
              final addresses = await systemDnsLookup(host, timeout);
              return addresses.join('\n');
            } catch (e) {
              return label('系统 DNS 查询失败：$e', 'System DNS lookup failed: $e');
            }
          }()
        : Future<String?>.value(null);
    final tcp =
        _selected == ToolboxDiagnostic.all || _selected == ToolboxDiagnostic.tcp
        ? () async {
            try {
              final elapsed = await tcpConnectLatency(host, port!, timeout);
              return label(
                '连接成功：${elapsed.inMilliseconds} ms',
                'Connected: ${elapsed.inMilliseconds} ms',
              );
            } catch (e) {
              return label('连接失败：$e', 'Connection failed: $e');
            }
          }()
        : Future<String?>.value(null);
    final route =
        _selected == ToolboxDiagnostic.all ||
            _selected == ToolboxDiagnostic.https
        ? () async {
            // The core probe captures the rule of the final HTTP request, including
            // redirects. It is an actual request, not a simulated rule-only match.
            final target = Uri(
              scheme: 'https',
              host: host,
              port: port!,
            ).toString();
            try {
              final result = await ref
                  .read(coreHandlerProvider)
                  .invokeMethod(
                    method: CoreMethod.probeToolbox,
                    arguments: {'url': target, 'timeout': 8000},
                    timeout: const Duration(seconds: 20),
                  );
              if (result is! Map) {
                return label('核心未返回结果。', 'No result from core.');
              }
              final error = result['error'] as String? ?? '';
              if (error.isNotEmpty) {
                return label(
                  '探测失败：${result['message'] ?? error}',
                  'Probe failed: ${result['message'] ?? error}',
                );
              }
              final rule = result['rule'] as String? ?? '';
              final payload = result['rule-payload'] as String? ?? '';
              final chains = (result['chains'] as List?)?.join(' → ') ?? '';
              return "${result['url']}\nHTTP ${result['status-code']} · ${result['delay']} ms\n"
                  "${label('规则', 'Rule')}: ${rule.isEmpty ? '—' : rule}${payload.isEmpty ? '' : ' ($payload)'}\n"
                  "${label('代理链', 'Proxy chain')}: ${chains.isEmpty ? '—' : chains}";
            } catch (e) {
              return label('核心探测失败：$e', 'Core probe failed: $e');
            }
          }()
        : Future<String?>.value(null);
    final tls =
        _selected == ToolboxDiagnostic.all || _selected == ToolboxDiagnostic.tls
        ? () async {
            try {
              final cert = await inspectTlsCertificate(host, port!, timeout);
              return '${label('主体', 'Subject')}: ${cert.subject}\n'
                  '${label('颁发者', 'Issuer')}: ${cert.issuer}\n'
                  '${label('生效时间', 'Valid from')}: ${cert.startValidity.toUtc().toIso8601String()}\n'
                  '${label('到期时间', 'Expires')}: ${cert.endValidity.toUtc().toIso8601String()}';
            } catch (e) {
              return label(
                'TLS 连接或证书验证失败：$e',
                'TLS connection or certificate validation failed: $e',
              );
            }
          }()
        : Future<String?>.value(null);
    final answers = await Future.wait<String?>([dns, tcp, route, tls]);
    if (!mounted) return;
    setState(() {
      _dns = answers[0];
      _tcp = answers[1];
      _route = answers[2];
      _tls = answers[3];
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      title: t('网络工具箱', 'Network toolbox'),
      body: ListView(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: context.contentTopPadding,
          bottom: 32,
        ),
        children: [
          Text(
            t(
              '系统 DNS、TCP 和 TLS 使用设备网络；HTTPS 探测经应用内核，显示最终请求的规则。',
              'System DNS, TCP and TLS use the device network. HTTPS uses the app core and shows the final request’s rule.',
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final choice in ToolboxDiagnostic.values)
                Chip(
                  label: switch (choice) {
                    ToolboxDiagnostic.all => t('全部检测', 'All checks'),
                    ToolboxDiagnostic.dns => t('DNS 查询', 'DNS lookup'),
                    ToolboxDiagnostic.tcp => t('TCP 延迟', 'TCP latency'),
                    ToolboxDiagnostic.https => t('HTTPS 分流', 'HTTPS routing'),
                    ToolboxDiagnostic.tls => t('TLS 证书', 'TLS certificate'),
                  },
                  selected: _selected == choice,
                  onPressed: _running
                      ? null
                      : () => setState(() {
                          _selected = choice;
                          _dns = _tcp = _route = _tls = _error = null;
                        }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _host,
            decoration: InputDecoration(
              hintText: t('域名或 IP', 'Hostname or IP'),
            ),
          ),
          const SizedBox(height: 12),
          if (_selected != ToolboxDiagnostic.dns)
            TextField(
              controller: _port,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(hintText: t('端口', 'Port')),
            ),
          const SizedBox(height: 16),
          TonalButton(
            onPressed: _running ? null : _run,
            label: _running ? t('检测中…', 'Checking…') : t('开始检测', 'Run checks'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: context.colorScheme.error)),
          ],
          if (_dns != null) ...[
            const SizedBox(height: 20),
            Text(
              t('系统 DNS', 'System DNS'),
              style: AppTextStyle.headline.of(context),
            ),
            SelectableText(_dns!),
          ],
          if (_tcp != null) ...[
            const SizedBox(height: 20),
            Text(
              t('TCP 连接延迟（非 ICMP Ping）', 'TCP connect latency (not ICMP ping)'),
              style: AppTextStyle.headline.of(context),
            ),
            SelectableText(_tcp!),
          ],
          if (_tls != null) ...[
            const SizedBox(height: 20),
            Text(
              t(
                'TLS 证书（设备网络，时间为 UTC）',
                'TLS certificate (device network, times in UTC)',
              ),
              style: AppTextStyle.headline.of(context),
            ),
            SelectableText(_tls!),
          ],
          if (_route != null) ...[
            const SizedBox(height: 20),
            Text(
              t('HTTPS 实际请求与分流', 'HTTPS request and routing'),
              style: AppTextStyle.headline.of(context),
            ),
            SelectableText(_route!),
          ],
        ],
      ),
    );
  }
}
