import 'package:fl_clash/common/network_toolbox.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Independent diagnostics inspired by a network toolbox; DNS and TCP use the
/// platform network, while the HTTP probe uses the application's core.
class NetworkToolboxView extends ConsumerStatefulWidget {
  const NetworkToolboxView({super.key});

  @override
  ConsumerState<NetworkToolboxView> createState() => _NetworkToolboxViewState();
}

class _NetworkToolboxViewState extends ConsumerState<NetworkToolboxView> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '443');
  String? _dns, _tcp, _route;
  bool _running = false;

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
    if (!validDiagnosticHost(host) ||
        port == null ||
        port < 1 ||
        port > 65535) {
      setState(
        () => _route = t(
          '请输入域名或 IP，以及 1–65535 的端口。',
          'Enter a hostname or IP and a port from 1 to 65535.',
        ),
      );
      return;
    }
    setState(() {
      _running = true;
      _dns = _tcp = _route = null;
    });
    const timeout = Duration(seconds: 8);
    final isChinese = _zh;
    String label(String zh, String en) => isChinese ? zh : en;
    final dns = () async {
      try {
        final addresses = await systemDnsLookup(host, timeout);
        return addresses.join('\n');
      } catch (e) {
        return label('系统 DNS 查询失败：$e', 'System DNS lookup failed: $e');
      }
    }();
    final tcp = () async {
      try {
        final elapsed = await tcpConnectLatency(host, port, timeout);
        return label(
          '连接成功：${elapsed.inMilliseconds} ms',
          'Connected: ${elapsed.inMilliseconds} ms',
        );
      } catch (e) {
        return label('连接失败：$e', 'Connection failed: $e');
      }
    }();
    final route = () async {
      // The core probe captures the rule of the final HTTP request, including
      // redirects. It is an actual request, not a simulated rule-only match.
      final target = Uri(scheme: 'https', host: host, port: port).toString();
      try {
        final result = await ref
            .read(coreHandlerProvider)
            .probe(ProbeParams(url: target, timeout: 8000));
        if (result == null) return label('核心未返回结果。', 'No result from core.');
        if (result.error != null) {
          return label(
            '探测失败：${result.message ?? result.error}',
            'Probe failed: ${result.message ?? result.error}',
          );
        }
        final rule = result.rule.isEmpty ? '—' : result.rule;
        final payload = result.rulePayload.isEmpty
            ? ''
            : ' (${result.rulePayload})';
        final chain = result.chains.isEmpty ? '—' : result.chains.join(' → ');
        return '${result.url}\nHTTP ${result.statusCode} · ${result.delay} ms\n'
            '${label('规则', 'Rule')}: $rule$payload\n${label('代理链', 'Proxy chain')}: $chain';
      } catch (e) {
        return label('核心探测失败：$e', 'Core probe failed: $e');
      }
    }();
    final answers = await Future.wait([dns, tcp, route]);
    if (!mounted) return;
    setState(() {
      _dns = answers[0];
      _tcp = answers[1];
      _route = answers[2];
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
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
              '系统 DNS 和 TCP 使用设备网络；HTTPS 探测经应用内核，显示最终请求的规则。',
              'System DNS and TCP use the device network. HTTPS uses the app core and shows the final request’s rule.',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _host,
            decoration: InputDecoration(
              labelText: t('域名或 IP', 'Hostname or IP'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _port,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: t('端口', 'Port')),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _running ? null : _run,
            child: Text(
              _running ? t('检测中…', 'Checking…') : t('开始检测', 'Run checks'),
            ),
          ),
          if (_dns != null) ...[
            const SizedBox(height: 20),
            Text(
              t('系统 DNS', 'System DNS'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SelectableText(_dns!),
          ],
          if (_tcp != null) ...[
            const SizedBox(height: 20),
            Text(
              t('TCP 连接延迟（非 ICMP Ping）', 'TCP connect latency (not ICMP ping)'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SelectableText(_tcp!),
          ],
          if (_route != null) ...[
            const SizedBox(height: 20),
            Text(
              t('HTTPS 实际请求与分流', 'HTTPS request and routing'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SelectableText(_route!),
          ],
        ],
      ),
    );
  }
}
