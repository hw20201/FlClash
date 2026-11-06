import 'package:fl_clash/common/ip_lookup.dart';
import 'package:fl_clash/common/network_toolbox.dart';
import 'package:fl_clash/common/speed_test.dart';
import 'package:fl_clash/common/toolbox_utilities.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum ToolboxUtility { headers, interfaces, subnet, speedTest, ipLookup }

class ToolboxUtilityView extends StatefulWidget {
  const ToolboxUtilityView({super.key, required this.tool});
  final ToolboxUtility tool;
  @override
  State<ToolboxUtilityView> createState() => _ToolboxUtilityViewState();
}

class _ToolboxUtilityViewState extends State<ToolboxUtilityView> {
  final _input = TextEditingController();
  final _port = TextEditingController(text: '443');
  String? _result;
  bool _running = false;
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
          final test = await runSpeedtest();
          result =
              '${t('服务器', 'Server')}: ${test.server.name} · ${test.server.sponsor} (${test.server.country})\n'
              '${t('延迟', 'Latency')}: ${test.latency.inMilliseconds} ms\n'
              '${t('下载', 'Download')}: ${test.downloadMbps.toStringAsFixed(1)} Mbps\n'
              '${t('上传', 'Upload')}: ${test.uploadMbps.toStringAsFixed(1)} Mbps';
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

  @override
  Widget build(BuildContext context) => Scaffold(
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
        if (widget.tool != ToolboxUtility.interfaces &&
            widget.tool != ToolboxUtility.speedTest)
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
            decoration: InputDecoration(hintText: t('HTTPS 端口', 'HTTPS port')),
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
