import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/widgets/widgets.dart';
import 'package:flutter/widgets.dart';

extension DashboardWidgetView on DashboardWidget {
  Widget get card => switch (this) {
    DashboardWidget.currentOutbound => const CurrentOutboundCard(),
    DashboardWidget.networkSpeed => const NetworkSpeedCard(),
    DashboardWidget.outboundMode => const OutboundModeCard(),
    DashboardWidget.vpnButton => const VpnCard(),
    DashboardWidget.networkTakeover => const NetworkTakeoverCard(),
    DashboardWidget.serviceStatus => const ServiceStatusCard(),
    DashboardWidget.profiles => const ProfilesCard(),
    DashboardWidget.proxyGroups => const ProxyGroupsCard(),
    DashboardWidget.connectionStats => const ConnectionStatsCard(),
    DashboardWidget.trafficStats => const TrafficStatsCard(),
    DashboardWidget.speedTest => const SpeedTestCard(),
    DashboardWidget.intranetIp => const IntranetIpCard(),
    DashboardWidget.memoryInfo => const MemoryInfo(),
  };

  Glyph get glyph => switch (this) {
    DashboardWidget.currentOutbound => AppGlyphs.status,
    DashboardWidget.networkSpeed => AppGlyphs.speed,
    DashboardWidget.outboundMode => AppGlyphs.split,
    DashboardWidget.vpnButton => AppGlyphs.vpn,
    DashboardWidget.networkTakeover => AppGlyphs.shuffle,
    DashboardWidget.serviceStatus => AppGlyphs.verified,
    DashboardWidget.profiles => AppGlyphs.profiles,
    DashboardWidget.proxyGroups => AppGlyphs.layers,
    DashboardWidget.connectionStats => AppGlyphs.connections,
    DashboardWidget.trafficStats => AppGlyphs.dataUsage,
    DashboardWidget.speedTest => AppGlyphs.speed,
    DashboardWidget.intranetIp => AppGlyphs.devices,
    DashboardWidget.memoryInfo => AppGlyphs.memory,
  };

  String label(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return switch (this) {
      DashboardWidget.currentOutbound => appLocalizations.status,
      DashboardWidget.networkSpeed => appLocalizations.networkSpeed,
      DashboardWidget.outboundMode => appLocalizations.outboundMode,
      DashboardWidget.vpnButton => 'VPN',
      DashboardWidget.networkTakeover => appLocalizations.networkTakeover,
      DashboardWidget.serviceStatus => appLocalizations.serviceStatus,
      DashboardWidget.profiles => appLocalizations.profile,
      DashboardWidget.proxyGroups => appLocalizations.proxyGroup,
      DashboardWidget.connectionStats => appLocalizations.connectionStats,
      DashboardWidget.trafficStats => _t(context, '流量统计', 'Traffic stats'),
      DashboardWidget.speedTest => _t(context, '速度测试', 'Speed test'),
      DashboardWidget.intranetIp => appLocalizations.intranetIP,
      DashboardWidget.memoryInfo => appLocalizations.memoryInfo,
    };
  }

  String? description(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return switch (this) {
      DashboardWidget.currentOutbound => appLocalizations.currentOutboundDesc,
      DashboardWidget.connectionStats => appLocalizations.connectionStatsDesc,
      DashboardWidget.memoryInfo => appLocalizations.memoryInfoDesc,
      _ => null,
    };
  }

  /// It holds the start button, which has nowhere else to go.
  bool get removable => this != DashboardWidget.currentOutbound;
}

String _t(BuildContext context, String zh, String en) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
