import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/proxies/list.dart';
import 'package:fl_clash/widgets/group_visibility_form.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tab.dart';

class ProxiesView extends ConsumerStatefulWidget {
  const ProxiesView({super.key, this.picker = false});

  /// Leaves the bar only its search and delay test, for picking a proxy from a
  /// sheet.
  final bool picker;

  @override
  ConsumerState<ProxiesView> createState() => _ProxiesViewState();
}

class _ProxiesViewState extends ConsumerState<ProxiesView> {
  final GlobalKey<ProxiesTabViewState> _proxiesTabKey = GlobalKey();

  // The same instance on every build, so the bar changing with the current
  // group or its delay test leaves the page alone.
  late final _tabView = ProxiesTabView(
    key: _proxiesTabKey,
    applyGroupVisibility: !widget.picker,
  );
  bool _isTab = false;

  void _updateStyle(
    ProxiesStyleProps Function(ProxiesStyleProps state) update,
  ) {
    ref.read(proxiesStyleSettingProvider.notifier).update(update);
  }

  List<PopupMenuItem> _buildMenuItems(
    BuildContext context,
    ProxiesStyleProps style,
  ) {
    final appLocalizations = context.appLocalizations;
    return [
      _optionsMenuItem(
        glyph: AppGlyphs.appsList,
        label: appLocalizations.style,
        section: const PopupMenuSection(),
        options: ProxiesType.values,
        value: style.type,
        textOf: (type) => type.label,
        onSelected: (type) =>
            _updateStyle((state) => state.copyWith(type: type)),
      ),
      _optionsMenuItem(
        glyph: AppGlyphs.sort,
        label: appLocalizations.sort,
        options: ProxiesSortType.values,
        value: style.sortType,
        textOf: (type) => switch (type) {
          ProxiesSortType.none => appLocalizations.defaultText,
          ProxiesSortType.delay => appLocalizations.delay,
          ProxiesSortType.name => appLocalizations.name,
        },
        onSelected: (type) =>
            _updateStyle((state) => state.copyWith(sortType: type)),
      ),
      _optionsMenuItem(
        glyph: AppGlyphs.dashboard,
        label: appLocalizations.layout,
        options: ProxiesLayout.values,
        value: style.layout,
        textOf: (layout) => switch (layout) {
          ProxiesLayout.tight => appLocalizations.tight,
          ProxiesLayout.standard => appLocalizations.standard,
          ProxiesLayout.loose => appLocalizations.loose,
        },
        onSelected: (layout) =>
            _updateStyle((state) => state.copyWith(layout: layout)),
      ),
      _optionsMenuItem(
        glyph: AppGlyphs.textSize,
        label: appLocalizations.size,
        options: ProxyCardType.values,
        value: style.cardType,
        textOf: (type) => type.label,
        onSelected: (type) =>
            _updateStyle((state) => state.copyWith(cardType: type)),
      ),
      if (style.type == ProxiesType.list)
        _optionsMenuItem(
          glyph: AppGlyphs.iconTile,
          label: appLocalizations.iconStyle,
          options: ProxiesIconStyle.values,
          value: style.iconStyle,
          textOf: (iconStyle) => switch (iconStyle) {
            ProxiesIconStyle.filled => appLocalizations.iconStyleFilled,
            ProxiesIconStyle.plain => appLocalizations.iconStylePlain,
            ProxiesIconStyle.hidden => appLocalizations.iconStyleHidden,
          },
          onSelected: (iconStyle) =>
              _updateStyle((state) => state.copyWith(iconStyle: iconStyle)),
        ),
      PopupMenuItem(
        glyph: AppGlyphs.eyeOff,
        label: appLocalizations.hideTimeoutProxies,
        checked: style.hideTimeoutProxies,
        section: const PopupMenuSection(),
        onPressed: () => _updateStyle(
          (state) =>
              state.copyWith(hideTimeoutProxies: !state.hideTimeoutProxies),
        ),
      ),
    ];
  }

  Future<void> _saveVisibility(int profileId, Set<String> hidden) async {
    if (ref.read(currentProfileProvider)?.id != profileId) {
      throw MessageException(
        context.appLocalizations.groupVisibilityProfileChanged,
      );
    }
    await ref
        .read(profilesProvider.notifier)
        .setHiddenGroupNames(profileId, hidden);
  }

  Widget _buildGroupVisibilityAction(IconButtonData data) =>
      _GroupVisibilityAnchor(
        targetBuilder: (open) => AppBarActionButton(
          data: data.copyWith(
            onPressed: data.onPressed == null || data.isLoading ? null : open,
          ),
        ),
      );

  Future<void> _restoreGroupVisibility() async {
    final profile = ref.read(currentProfileProvider);
    if (profile == null) return;
    try {
      await _saveVisibility(profile.id, {});
    } catch (error) {
      if (mounted) {
        await dialogs.showMessage(message: TextSpan(text: error.toString()));
      }
    }
  }

  Widget _buildBody(ProxiesStyleProps style) {
    final child = switch (style.type) {
      ProxiesType.tab => _tabView,
      ProxiesType.list => ProxiesListView(applyGroupVisibility: !widget.picker),
    };
    if (widget.picker) return child;
    return Consumer(
      builder: (context, ref, _) {
        if (ref.watch(loadingProvider(LoadingTag.proxies))) return child;
        final groups = ref.watch(currentGroupsStateProvider).value;
        if (groups.isEmpty) return child;
        final hidden =
            ref.watch(currentProfileProvider)?.hiddenGroupNames ??
            const <String>{};
        final allHidden = groups.every((group) => hidden.contains(group.name));
        if (!allHidden) return child;
        final l10n = context.appLocalizations;
        return NullStatus(
          key: const ValueKey('proxy-groups-all-hidden'),
          illustration: NullStatusIllustration.proxies,
          label: l10n.groupVisibilityAllHidden,
          action: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _GroupVisibilityAnchor(
                targetBuilder: (open) => TonalButton(
                  onPressed: open,
                  label: l10n.groupVisibilityTitle,
                ),
              ),
              TextButton(
                onPressed: _restoreGroupVisibility,
                child: Text(l10n.groupVisibilityRestore),
              ),
            ],
          ),
        );
      },
    );
  }

  IconButtonData? _buildDelayAction() {
    if (!_isTab) {
      return null;
    }
    final isDelayTesting = ref.watch(
      widget.picker
          ? currentGroupDelayTestingProvider
          : proxyPageCurrentGroupDelayTestingProvider,
    );
    return IconButtonData(
      glyph: AppGlyphs.bolt,
      onPressed: () {
        _proxiesTabKey.currentState?.delayTestCurrentGroup();
      },
      tooltip: context.appLocalizations.delayTest,
      isLoading: isDelayTesting,
    );
  }

  void _onSearch(String value) {
    ref.read(queryProvider(QueryTag.proxies).notifier).value = value;
  }

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      proxiesStyleSettingProvider.select(
        (state) => state.type == ProxiesType.tab,
      ),
      (prev, next) {
        if (prev != next) {
          setState(() {
            _isTab = next;
          });
        }
      },
      fireImmediately: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = ref.watch(proxiesStyleSettingProvider);
    final isLoading = ref.watch(loadingProvider(LoadingTag.proxies));
    final picker = widget.picker;
    final delayAction = _buildDelayAction();
    final profile = ref.watch(currentProfileProvider);
    final primaryAction = picker
        ? delayAction
        : IconButtonData(
            glyph: AppGlyphs.sliders,
            // PopupAnchor handles opening; the bar retains the enabled state.
            onPressed: profile == null || isLoading ? null : () {},
            tooltip: context.appLocalizations.groupVisibilityTitle,
            isSelected: profile?.hiddenGroupNames.isNotEmpty ?? false,
          );
    return Scaffold(
      isLoading: isLoading,
      resizeToAvoidBottomInset: false,
      primaryAction: primaryAction,
      primaryActionBuilder: picker ? null : _buildGroupVisibilityAction,
      searchActions: [if (!picker) ?primaryAction, ?delayAction],
      iconActions: [
        if (!picker) ?delayAction,
        if (_isTab && !picker)
          IconButtonData(
            glyph: AppGlyphs.locate,
            onPressed: () {
              _proxiesTabKey.currentState?.scrollToGroupSelected();
            },
            tooltip: context.appLocalizations.scrollToSelected,
          ),
      ],
      menuItems: picker ? const [] : _buildMenuItems(context, style),
      title: context.appLocalizations.proxies,
      searchState: AppBarSearchState(onSearch: _onSearch),
      body: _buildBody(style),
    );
  }
}

class _GroupVisibilityAnchor extends StatelessWidget {
  const _GroupVisibilityAnchor({required this.targetBuilder});

  final Widget Function(PopupOpen open) targetBuilder;

  @override
  Widget build(BuildContext context) => PopupAnchor(
    targetBuilder: targetBuilder,
    popupBuilder: (_) => const _GroupVisibilityPopup(),
  );
}

class _GroupVisibilityPopup extends ConsumerStatefulWidget {
  const _GroupVisibilityPopup();

  @override
  ConsumerState<_GroupVisibilityPopup> createState() =>
      _GroupVisibilityPopupState();
}

class _GroupVisibilityPopupState extends ConsumerState<_GroupVisibilityPopup> {
  late final Profile? _profile;
  late final List<String> _names;
  late final ProviderSubscription<int?> _subscription;
  var _profileChanged = false;

  @override
  void initState() {
    super.initState();
    _profile = ref.read(currentProfileProvider);
    _names = ref
        .read(currentGroupsStateProvider)
        .value
        .map((group) => group.name)
        .toList();
    _subscription = ref.listenManual(currentProfileIdProvider, (_, next) {
      if (next != _profile?.id) _profileChanged = true;
    });
  }

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }

  Future<void> _save(Set<String> hidden) async {
    final profile = _profile;
    if (profile == null ||
        _profileChanged ||
        ref.read(currentProfileIdProvider) != profile.id) {
      throw MessageException(
        context.appLocalizations.groupVisibilityProfileChanged,
      );
    }
    await ref
        .read(profilesProvider.notifier)
        .setHiddenGroupNames(profile.id, hidden);
  }

  @override
  Widget build(BuildContext context) => GroupVisibilityForm(
    groupNames: _names,
    hiddenGroupNames: _profile?.hiddenGroupNames ?? const {},
    onSave: _save,
  );
}

PopupMenuItem _optionsMenuItem<T>({
  required Glyph glyph,
  required String label,
  required List<T> options,
  required T value,
  required String Function(T option) textOf,
  required ValueSetter<T> onSelected,
  PopupMenuSection? section,
}) {
  return PopupMenuItem(
    glyph: glyph,
    label: label,
    section: section,
    subItems: [
      for (final option in options)
        PopupMenuItem(
          label: textOf(option),
          checked: option == value,
          onPressed: () => onSelected(option),
        ),
    ],
  );
}
