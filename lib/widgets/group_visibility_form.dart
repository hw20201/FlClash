import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/form/custom_issue.dart';
import 'package:fl_clash/features/form/form_row.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter/widgets.dart';

class GroupVisibilityForm extends StatefulWidget {
  final List<String> groupNames;
  final Set<String> hiddenGroupNames;
  final Future<void> Function(Set<String>) onSave;

  const GroupVisibilityForm({
    super.key,
    required this.groupNames,
    required this.hiddenGroupNames,
    required this.onSave,
  });

  @override
  State<GroupVisibilityForm> createState() => _GroupVisibilityFormState();
}

class _GroupVisibilityFormState extends State<GroupVisibilityForm> {
  late final List<String> _groupNames;
  late final Set<String> _hiddenGroupNames;
  var _query = '';
  var _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _groupNames = widget.groupNames.toSet().toList(growable: false);
    _hiddenGroupNames = Set.of(widget.hiddenGroupNames);
  }

  List<String> get _matches => _query.isEmpty
      ? _groupNames
      : _groupNames
            .where((name) => name.toLowerCase().contains(_query))
            .toList(growable: false);

  void _setVisible(Iterable<String> names, bool visible) {
    if (!mounted || _saving) {
      return;
    }
    setState(() {
      if (visible) {
        _hiddenGroupNames.removeAll(names);
      } else {
        _hiddenGroupNames.addAll(names);
      }
    });
  }

  void _reset() {
    if (!mounted || _saving) {
      return;
    }
    setState(_hiddenGroupNames.clear);
  }

  Future<void> _save() async {
    if (!mounted || _saving) {
      return;
    }
    final fallbackError = context.appLocalizations.databaseWriteFailedTip;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(Set.of(_hiddenGroupNames));
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        final message = error
            .toString()
            .replaceFirst(RegExp(r'^Exception:\s*'), '')
            .trim();
        setState(() {
          _error = message.isEmpty ? fallbackError : message;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _bulkButton({
    required String label,
    required bool selected,
    required bool first,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: ConnectedButton(
        selected: selected,
        first: first,
        last: !first,
        outer: AppCorner.xxl,
        inner: AppCorner.md,
        background: context.raisedSurfaceLevel.colorOf(context.colorScheme),
        onTap: onTap,
        semanticLabel: label,
        builder: (foreground) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.subheadline
                .of(context)
                .copyWith(color: foreground),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final matches = _matches;
    final visibleCount = _groupNames
        .where((name) => !_hiddenGroupNames.contains(name))
        .length;
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          appLocalizations.groupVisibilityDescription,
          style: AppTextStyle.footnote.of(context),
        ),
      ),
      SearchField(
        glyph: AppGlyphs.search,
        hintText: appLocalizations.search,
        onChanged: (value) => setState(() => _query = value.toLowerCase()),
        onSubmitted: () => FocusScope.of(context).unfocus(),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: ConnectedButtonGroup(
          children: [
            _bulkButton(
              label: appLocalizations.selectAll,
              selected:
                  matches.isNotEmpty &&
                  matches.every((name) => !_hiddenGroupNames.contains(name)),
              first: true,
              onTap: () => _setVisible(matches, true),
            ),
            _bulkButton(
              label: appLocalizations.cancelSelectAll,
              selected:
                  matches.isNotEmpty &&
                  matches.every(_hiddenGroupNames.contains),
              first: false,
              onTap: () => _setVisible(matches, false),
            ),
          ],
        ),
      ),
      generateSection(
        title: appLocalizations.groupVisibilityCount(
          visibleCount,
          _groupNames.length,
        ),
        atTop: true,
        items: [
          if (matches.isEmpty)
            FormRow(
              title: _groupNames.isEmpty
                  ? appLocalizations.groupVisibilityNoGroups
                  : appLocalizations.noSearchResults,
            ),
          for (final name in matches)
            MemoBuilder(
              key: ValueKey(name),
              inputs: [name, _hiddenGroupNames.contains(name), _saving],
              builder: (context) {
                final visible = !_hiddenGroupNames.contains(name);
                final label = name.isEmpty
                    ? context.appLocalizations.unnamed
                    : name;
                return FormRow(
                  title: label,
                  onPressed: _saving
                      ? null
                      : () => _setVisible([name], !visible),
                  trailing: Switch(
                    value: visible,
                    semanticLabel: label,
                    onChanged: _saving
                        ? null
                        : (value) => _setVisible([name], value),
                  ),
                );
              },
            ),
        ],
      ),
    ];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420, maxHeight: 640),
      child: Surface(
        color: SurfaceLevel.floatingOf(
          context.colorScheme,
        ).colorOf(context.colorScheme),
        shape: AppShape.xl,
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: TonalButtonTheme(
                size: TonalButtonSize.section,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: appLocalizations.cancel,
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const GlyphIcon(AppGlyphs.close),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          appLocalizations.groupVisibilityTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.headline.of(context),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: appLocalizations.reset,
                      onPressed: _saving ? null : _reset,
                      icon: const GlyphIcon(AppGlyphs.reset),
                    ),
                    IconButton(
                      tooltip: appLocalizations.save,
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const ActivityIndicator(size: 20)
                          : const GlyphIcon(AppGlyphs.check),
                    ),
                  ],
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  ErrorBanner(message: _error),
                  ...children,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
