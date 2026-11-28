import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/toolbox_layout.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';

class ToolboxModuleCard extends StatelessWidget {
  const ToolboxModuleCard({
    super.key,
    required this.module,
    required this.size,
    required this.editing,
    required this.onSizeChanged,
    required this.onDragResize,
    required this.summary,
    required this.page,
  });

  final ToolboxModuleId module;
  final ToolboxCardSize size;
  final bool editing;
  final ValueChanged<ToolboxCardSize> onSizeChanged;
  final void Function(ToolboxCardSize start, Offset delta, double threshold)
  onDragResize;
  final Widget summary;
  final Widget page;

  Glyph get _glyph => switch (module) {
    ToolboxModuleId.exitIp => AppGlyphs.connections,
    ToolboxModuleId.dnsLookup => AppGlyphs.dns,
    ToolboxModuleId.trafficStatistics => AppGlyphs.dataUsage,
  };

  String _title(BuildContext context) {
    final l10n = context.appLocalizations;
    return switch (module) {
      ToolboxModuleId.exitIp => l10n.toolboxExitIp,
      ToolboxModuleId.dnsLookup => l10n.dnsLookup,
      ToolboxModuleId.trafficStatistics => l10n.toolboxTrafficStatistics,
    };
  }

  List<ToolboxCardSize> get _availableSizes =>
      ToolboxCardSize.values.where(module.allows).toList(growable: false);

  String _sizeLabel(BuildContext context, ToolboxCardSize value) {
    final l10n = context.appLocalizations;
    return switch (value) {
      ToolboxCardSize.small => l10n.toolboxSizeSmall,
      ToolboxCardSize.wide => l10n.toolboxSizeWide,
      ToolboxCardSize.tall => l10n.toolboxSizeTall,
      ToolboxCardSize.large => l10n.toolboxSizeLarge,
    };
  }

  Widget _buildCard(BuildContext context, VoidCallback? open) {
    final l10n = context.appLocalizations;
    return Card(
      key: ValueKey(switch (module) {
        ToolboxModuleId.exitIp => 'toolbox-exit-ip',
        ToolboxModuleId.dnsLookup => 'toolbox-dns-lookup',
        ToolboxModuleId.trafficStatistics => 'toolbox-traffic',
      }),
      shape: AppShape.lg,
      padding: const EdgeInsets.all(14),
      onPressed: editing ? null : open,
      inert: editing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            spacing: 8,
            children: [
              GlyphIcon(_glyph, size: 22),
              Expanded(
                child: Text(
                  _title(context),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.headline.of(context),
                ),
              ),
              if (editing)
                _ResizeHandle(
                  key: ValueKey('toolbox-resize-handle-${module.id}'),
                  size: size,
                  threshold: 54,
                  onTap: () {
                    final index = _availableSizes.indexOf(size);
                    onSizeChanged(
                      _availableSizes[(index + 1) % _availableSizes.length],
                    );
                  },
                  onResize: onDragResize,
                  tooltip: l10n.toolboxCardSize,
                )
              else
                GlyphIcon(
                  AppGlyphs.chevronForward,
                  size: 18,
                  color: context.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(child: summary),
          if (editing) ...[
            const SizedBox(height: 4),
            ListItem<ToolboxCardSize>.options(
              key: ValueKey('toolbox-size-${module.id}'),
              title: Text(l10n.toolboxCardSize),
              options: _availableSizes,
              value: size,
              textBuilder: (value) => _sizeLabel(context, value),
              onChanged: onSizeChanged,
              minTileHeight: 44,
              minVerticalPadding: 4,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (editing) return _buildCard(context, null);
    if (context.isMobileView) {
      return OpenContainer<void>(
        closedShape: AppShape.lg,
        closedBuilder: (_, open) => _buildCard(context, open),
        openBuilder: (_, _) => page,
      );
    }
    return _buildCard(
      context,
      () => showNestedExtend<void>(context, builder: (_) => page),
    );
  }
}

class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle({
    super.key,
    required this.size,
    required this.threshold,
    required this.onTap,
    required this.onResize,
    required this.tooltip,
  });

  final ToolboxCardSize size;
  final double threshold;
  final VoidCallback onTap;
  final void Function(ToolboxCardSize start, Offset delta, double threshold)
  onResize;
  final String tooltip;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  Offset _delta = Offset.zero;
  ToolboxCardSize? _start;

  void _onDragStart(DragStartDetails _) {
    _start = widget.size;
    _delta = Offset.zero;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _delta += details.delta;
  }

  void _onDragEnd(DragEndDetails _) {
    final start = _start;
    if (start != null) widget.onResize(start, _delta, widget.threshold);
    _clearDrag();
  }

  void _onDragCancel() => _clearDrag();

  void _clearDrag() {
    _start = null;
    _delta = Offset.zero;
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onHorizontalDragStart: _onDragStart,
    onHorizontalDragUpdate: _onDragUpdate,
    onHorizontalDragEnd: _onDragEnd,
    onHorizontalDragCancel: _onDragCancel,
    onVerticalDragStart: _onDragStart,
    onVerticalDragUpdate: _onDragUpdate,
    onVerticalDragEnd: _onDragEnd,
    onVerticalDragCancel: _onDragCancel,
    child: IconButton(
      tooltip: widget.tooltip,
      onPressed: widget.onTap,
      icon: const GlyphIcon(AppGlyphs.dragHandle),
    ),
  );
}
