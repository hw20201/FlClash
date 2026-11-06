import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/network_toolbox.dart';
import 'package:fl_clash/views/toolbox_utilities.dart';
import 'package:flutter/widgets.dart';

/// A launchpad of working tools, rather than a single combined form.
/// The reference's soft cards and asymmetric hierarchy remain adaptive to theme,
/// narrow screens, large text, desktop pointers and remote-control focus.
class NetworkToolboxHome extends StatelessWidget {
  const NetworkToolboxHome({super.key});

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    String t(String a, String b) => zh ? a : b;
    void open(Widget page) => Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, animation, secondaryAnimation) => page,
        transitionsBuilder: (_, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
    Widget card(
      String id,
      String title,
      String detail,
      Widget icon,
      Widget page,
    ) {
      final shape = AppShape.all(28);
      final colors = context.colorScheme;
      return Container(
        decoration: ShapeDecoration(
          color: colors.surface,
          shape: shape.copyWith(
            side: BorderSide(color: colors.onSurface.withValues(alpha: 0.09)),
          ),
          shadows: [
            BoxShadow(
              color: colors.onSurface.withValues(alpha: 0.035),
              blurRadius: 18,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: PressSurface(
          key: ValueKey('toolbox-$id'),
          fill: Colors.transparent,
          shape: shape,
          childFills: true,
          onPressed: () => open(page),
          child: Semantics(
            button: true,
            label: '$title. $detail',
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: IconTheme(
                      data: IconThemeData(color: colors.primary, size: 26),
                      child: icon,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    style: AppTextStyle.headline.of(context, emphasized: true),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    detail,
                    style: AppTextStyle.subheadline
                        .of(context)
                        .copyWith(
                          color: colors.onSurface.withValues(alpha: 0.68),
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final cards = <Widget>[
      card(
        'all',
        t('连通性综合检测', 'Connectivity overview'),
        t(
          '一次检查 DNS、TCP、TLS 与 HTTPS 分流。',
          'Check DNS, TCP, TLS and HTTPS routing at once.',
        ),
        const GlyphIcon(AppGlyphs.dashboard),
        const NetworkToolboxView(),
      ),
      card(
        'route',
        t('路由追踪', 'Routing trace'),
        t('查看最终规则与代理链。', 'Inspect the final rule and proxy chain.'),
        const GlyphIcon(AppGlyphs.connections),
        const NetworkToolboxView(initial: ToolboxDiagnostic.https),
      ),
      card(
        'dns',
        t('DNS 查询', 'DNS lookup'),
        t(
          '查看 IPv4 / IPv6 解析结果。',
          'Resolve IPv4 / IPv6 with the device resolver.',
        ),
        const GlyphIcon(AppGlyphs.dns),
        const NetworkToolboxView(initial: ToolboxDiagnostic.dns),
      ),
      card(
        'tls',
        t('TLS 证书', 'TLS certificate'),
        t('检查颁发者、有效期与信任。', 'Inspect the issuer, validity and TLS trust.'),
        const GlyphIcon(AppGlyphs.lock),
        const NetworkToolboxView(initial: ToolboxDiagnostic.tls),
      ),
      card(
        'tcp',
        t('TCP 延迟', 'TCP latency'),
        t('直连目标端口的连接耗时。', 'Device-network connection timing.'),
        const GlyphIcon(AppGlyphs.bolt),
        const NetworkToolboxView(initial: ToolboxDiagnostic.tcp),
      ),
      card(
        'headers',
        t('HTTP 响应头', 'HTTP headers'),
        t(
          'HEAD 请求查看状态与响应头。',
          'Inspect status and headers with a HEAD request.',
        ),
        const GlyphIcon(AppGlyphs.code),
        const ToolboxUtilityView(tool: ToolboxUtility.headers),
      ),
      card(
        'interfaces',
        t('本机 IP', 'Local IP addresses'),
        t('查看设备网卡地址。', 'List device interface addresses.'),
        const GlyphIcon(AppGlyphs.devices),
        const ToolboxUtilityView(tool: ToolboxUtility.interfaces),
      ),
      card(
        'subnet',
        t('子网计算', 'Subnet calculator'),
        t(
          '本地计算 IPv4 CIDR 与地址范围。',
          'Calculate IPv4 CIDR, netmask and host range offline.',
        ),
        const GlyphIcon(AppGlyphs.split),
        const ToolboxUtilityView(tool: ToolboxUtility.subnet),
      ),
      card(
        'ip',
        t('IP 全能查', 'IP lookup'),
        t('查公网 IP、归属地与运营商。', 'Look up a public IP, location and ISP.'),
        const GlyphIcon(AppGlyphs.locate),
        const ToolboxUtilityView(tool: ToolboxUtility.ipLookup),
      ),
    ];

    return Scaffold(
      title: t('网络工具箱', 'Network toolbox'),
      backgroundColor: Color.alphaBlend(
        context.colorScheme.primary.withValues(alpha: 0.035),
        context.colorScheme.surface,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, context.contentTopPadding, 20, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: LayoutBuilder(
              builder: (context, box) {
                // Stack at accessibility text sizes rather than clipping cards.
                final columns =
                    box.maxWidth >= 320 &&
                    MediaQuery.textScalerOf(context).scale(17) <= 24;
                final step = columns ? 2 : 1;
                final rows = <Widget>[];
                for (var i = 0; i < cards.length; i += step) {
                  final end = (i + step).clamp(0, cards.length);
                  final pair = cards.sublist(i, end);
                  if (pair.length == 2) {
                    rows.add(
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: pair[0]),
                          const SizedBox(width: 12),
                          Expanded(child: pair[1]),
                        ],
                      ),
                    );
                  } else {
                    rows.add(
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: pair[0]),
                          if (columns) ...[
                            const SizedBox(width: 12),
                            const Expanded(child: SizedBox.shrink()),
                          ],
                        ],
                      ),
                    );
                  }
                  if (end < cards.length) {
                    rows.add(const SizedBox(height: 12));
                  }
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    card(
                      'speed',
                      t('网速测试', 'Speed test'),
                      t(
                        '测下载、上传速度与延迟。',
                        'Measure download, upload and latency.',
                      ),
                      const GlyphIcon(AppGlyphs.speed),
                      const ToolboxUtilityView(tool: ToolboxUtility.speedTest),
                    ),
                    const SizedBox(height: 12),
                    ...rows,
                    const SizedBox(height: 20),
                    Text(
                      t(
                        '设备网络工具可能仍受系统 VPN 路由影响；“路由追踪”显式经过应用内核。',
                        'Device-network tools may still follow system VPN routing. Routing trace explicitly uses the app core.',
                      ),
                      style: AppTextStyle.footnote.of(context),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
