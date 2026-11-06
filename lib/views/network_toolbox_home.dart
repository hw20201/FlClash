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
      Widget page, {
      bool featured = false,
      double? height,
    }) {
      final shape = AppShape.all(28);
      final colors = context.colorScheme;
      return SizedBox(
        height: height,
        child: Container(
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
                    if (height != null)
                      const Spacer()
                    else
                      const SizedBox(height: 18),
                    Text(
                      title,
                      style:
                          (featured
                                  ? AppTextStyle.title3
                                  : AppTextStyle.headline)
                              .of(context, emphasized: true),
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
                    if (featured) ...[
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '→',
                          style: AppTextStyle.title2.of(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final route = card(
      'route',
      t('路由追踪', 'Routing trace'),
      t(
        '发起 HTTPS 请求，查看最终规则与代理链。不是 IP 跳点追踪。',
        'Send HTTPS through the core and inspect the final rule and proxy chain. Not IP-hop traceroute.',
      ),
      const GlyphIcon(AppGlyphs.connections),
      const NetworkToolboxView(initial: ToolboxDiagnostic.https),
      featured: true,
    );
    final dns = card(
      'dns',
      t('DNS 查询', 'DNS lookup'),
      t(
        '使用设备系统解析器，查看 IPv4 / IPv6。',
        'Resolve IPv4 / IPv6 with the device resolver.',
      ),
      const GlyphIcon(AppGlyphs.dns),
      const NetworkToolboxView(initial: ToolboxDiagnostic.dns),
    );
    final tls = card(
      'tls',
      t('TLS 证书', 'TLS certificate'),
      t('检查证书颁发者、有效期和信任验证。', 'Inspect the issuer, validity and TLS trust.'),
      const GlyphIcon(AppGlyphs.lock),
      const NetworkToolboxView(initial: ToolboxDiagnostic.tls),
    );
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
                Widget row(Widget a, Widget b) => columns
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: a),
                          const SizedBox(width: 12),
                          Expanded(child: b),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [a, const SizedBox(height: 12), b],
                      );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    card(
                      'all',
                      t('连通性综合检测', 'Connectivity overview'),
                      t(
                        '一次检查 DNS、TCP、TLS 与 HTTPS 分流；按需输入目标，不会自动联网。',
                        'Check DNS, TCP, TLS and HTTPS routing for a destination you choose. No automatic traffic.',
                      ),
                      const GlyphIcon(AppGlyphs.speed),
                      const NetworkToolboxView(),
                    ),
                    const SizedBox(height: 12),
                    row(
                      route,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [dns, const SizedBox(height: 12), tls],
                      ),
                    ),
                    const SizedBox(height: 12),
                    row(
                      card(
                        'tcp',
                        t('TCP 延迟', 'TCP latency'),
                        t(
                          '直连目标端口的连接耗时，非 ICMP Ping。',
                          'Device-network connection timing. Not ICMP ping.',
                        ),
                        const GlyphIcon(AppGlyphs.bolt),
                        const NetworkToolboxView(
                          initial: ToolboxDiagnostic.tcp,
                        ),
                      ),
                      card(
                        'headers',
                        t('HTTP 响应头', 'HTTP headers'),
                        t(
                          'HEAD 请求查看状态与响应头，不下载正文。',
                          'Inspect status and headers with a HEAD request. No body download.',
                        ),
                        const GlyphIcon(AppGlyphs.code),
                        const ToolboxUtilityView(tool: ToolboxUtility.headers),
                      ),
                    ),
                    const SizedBox(height: 12),
                    row(
                      card(
                        'interfaces',
                        t('本机 IP', 'Local IP addresses'),
                        t(
                          '查看设备网卡地址，不是公网出口 IP。',
                          'List device interface addresses, not the public exit IP.',
                        ),
                        const GlyphIcon(AppGlyphs.devices),
                        const ToolboxUtilityView(
                          tool: ToolboxUtility.interfaces,
                        ),
                      ),
                      card(
                        'subnet',
                        t('子网计算', 'Subnet calculator'),
                        t(
                          '本地计算 IPv4 CIDR、掩码与可用地址范围。',
                          'Calculate IPv4 CIDR, netmask and host range offline.',
                        ),
                        const GlyphIcon(AppGlyphs.split),
                        const ToolboxUtilityView(tool: ToolboxUtility.subnet),
                      ),
                    ),
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
