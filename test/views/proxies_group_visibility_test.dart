import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/proxies/proxies.dart';
import 'package:fl_clash/views/proxies/tab.dart';
import 'package:fl_clash/widgets/group_visibility_form.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/inherited.dart';

import '../helpers/glyph_finders.dart';
import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

class _VisibilityProfiles extends TestProfiles {
  _VisibilityProfiles(super.initial);

  int saves = 0;

  @override
  Future<void> setHiddenGroupNames(int profileId, Set<String> names) async {
    saves++;
    updateProfile(
      profileId,
      (profile) => profile.copyWith(hiddenGroupNames: Set.of(names)),
    );
  }
}

void main() {
  late ProviderContainer container;
  late ProviderSubscription<Profile?> subscription;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(
          () => _VisibilityProfiles([
            const Profile(
              id: 1,
              autoUpdateDuration: Duration.zero,
              currentGroupName: 'Group B',
              selectedMap: {'Group A': 'Node A'},
            ),
            const Profile(id: 2, autoUpdateDuration: Duration.zero),
          ]),
        ),
      ],
    );
    globalState.container = container;
    container.read(currentProfileIdProvider.notifier).update((_) => 1);
    container
        .read(groupsProvider.notifier)
        .update(
          (_) => const [
            Group(
              name: 'Group A',
              type: GroupType.Selector,
              hidden: false,
              all: [Proxy(name: 'Node A', type: 'Direct')],
            ),
            Group(
              name: 'Group B',
              type: GroupType.Selector,
              hidden: false,
              all: [Proxy(name: 'Node B', type: 'Direct')],
            ),
          ],
        );
    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mode: Mode.rule));
    container
        .read(proxiesStyleSettingProvider.notifier)
        .update((style) => style.copyWith(type: ProxiesType.list));
    subscription = container.listen(currentProfileProvider, (_, _) {});
  });

  tearDown(() {
    subscription.close();
    container.dispose();
  });

  _VisibilityProfiles profiles() =>
      container.read(profilesProvider.notifier) as _VisibilityProfiles;

  Future<void> pumpPage(WidgetTester tester, {bool picker = false}) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(child: ProxiesView(picker: picker)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'main page always keeps management and restores from all hidden',
    (tester) async {
      profiles().updateProfile(
        1,
        (profile) => profile.copyWith(hiddenGroupNames: {'Group A', 'Group B'}),
      );
      await pumpPage(tester);
      expect(find.byGlyph(AppGlyphs.sliders), findsOneWidget);
      expect(
        find.byKey(const ValueKey('proxy-groups-all-hidden')),
        findsOneWidget,
      );
      final l10n = tester.element(find.byType(ProxiesView)).appLocalizations;
      await tester.tap(find.text(l10n.groupVisibilityRestore));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('proxy-groups-all-hidden')),
        findsNothing,
      );
      expect(container.read(currentProfileProvider)!.hiddenGroupNames, isEmpty);
      expect(container.read(currentProfileProvider)!.selectedMap, {
        'Group A': 'Node A',
      });
      expect(profiles().saves, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('picker retains all groups and omits the management entry', (
    tester,
  ) async {
    profiles().updateProfile(
      1,
      (profile) => profile.copyWith(hiddenGroupNames: {'Group A', 'Group B'}),
    );
    await pumpPage(tester, picker: true);
    expect(find.byGlyph(AppGlyphs.sliders), findsNothing);
    expect(find.byKey(const ValueKey('proxy-groups-all-hidden')), findsNothing);
    expect(container.read(proxiesListStateProvider).groups, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'hiding the active tab selects a visible tab without changing nodes',
    (tester) async {
      container
          .read(proxiesStyleSettingProvider.notifier)
          .update((style) => style.copyWith(type: ProxiesType.tab));
      await pumpPage(tester);
      expect(
        tester
            .state<ProxiesTabViewState>(find.byType(ProxiesTabView))
            .currentGroup!
            .name,
        'Group B',
      );
      profiles().updateProfile(
        1,
        (profile) => profile.copyWith(hiddenGroupNames: {'Group B'}),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .state<ProxiesTabViewState>(find.byType(ProxiesTabView))
            .currentGroup!
            .name,
        'Group A',
      );
      expect(container.read(currentProfileProvider)!.selectedMap, {
        'Group A': 'Node A',
      });
      expect(
        container.read(currentProfileProvider)!.currentGroupName,
        'Group A',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'equal visible tabs fall back after a profile or picker selects a hidden tab',
    (tester) async {
      container
          .read(groupsProvider.notifier)
          .update(
            (groups) => [
              ...groups,
              const Group(
                name: 'Group C',
                type: GroupType.Selector,
                hidden: false,
                all: [Proxy(name: 'Node C', type: 'Direct')],
              ),
            ],
          );
      profiles().updateProfile(
        1,
        (profile) => profile.copyWith(
          currentGroupName: 'Group C',
          hiddenGroupNames: {'Group B'},
        ),
      );
      profiles().updateProfile(
        2,
        (profile) => profile.copyWith(
          currentGroupName: 'Group B',
          hiddenGroupNames: {'Group B'},
        ),
      );
      container
          .read(proxiesStyleSettingProvider.notifier)
          .update((style) => style.copyWith(type: ProxiesType.tab));
      await pumpPage(tester);
      ProxiesTabViewState tabs() =>
          tester.state<ProxiesTabViewState>(find.byType(ProxiesTabView));
      expect(tabs().currentGroup!.name, 'Group C');
      container.read(currentProfileIdProvider.notifier).update((_) => 2);
      await tester.pumpAndSettle();
      expect(tabs().currentGroup!.name, 'Group A');
      expect(
        container.read(currentProfileProvider)!.currentGroupName,
        'Group A',
      );
      expect(container.read(currentProfileProvider)!.selectedMap, isEmpty);
      expect(
        container
            .read(profilesProvider)
            .firstWhere((profile) => profile.id == 1)
            .currentGroupName,
        'Group C',
      );
      profiles().updateProfile(
        2,
        (profile) => profile.copyWith(currentGroupName: 'Group B'),
      );
      await tester.pumpAndSettle();
      expect(tabs().currentGroup!.name, 'Group A');
      expect(
        container.read(currentProfileProvider)!.currentGroupName,
        'Group A',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a retained inactive main page cannot overwrite a picker tab', (
    tester,
  ) async {
    profiles().updateProfile(
      1,
      (profile) => profile.copyWith(
        currentGroupName: 'Group A',
        hiddenGroupNames: {'Group B'},
      ),
    );
    container
        .read(proxiesStyleSettingProvider.notifier)
        .update((style) => style.copyWith(type: ProxiesType.tab));
    var pickerVisible = false;
    late StateSetter updatePage;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          child: StatefulBuilder(
            builder: (context, setState) {
              updatePage = setState;
              return Stack(
                children: [
                  Offstage(
                    offstage: pickerVisible,
                    child: TickerMode(
                      enabled: !pickerVisible,
                      child: PageActivityScope(
                        isActive: !pickerVisible,
                        child: const ProxiesView(),
                      ),
                    ),
                  ),
                  if (pickerVisible) const ProxiesView(picker: true),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    updatePage(() => pickerVisible = true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Group B'));
    await tester.pumpAndSettle();
    final tabStates = tester
        .stateList<ProxiesTabViewState>(
          find.byType(ProxiesTabView, skipOffstage: false),
        )
        .toList();
    expect(tabStates, hasLength(2));
    expect(tabStates.first.currentGroup!.name, 'Group A');
    expect(tabStates.last.currentGroup!.name, 'Group B');
    expect(container.read(currentProfileProvider)!.currentGroupName, 'Group B');
    expect(container.read(currentProfileProvider)!.selectedMap, {
      'Group A': 'Node A',
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('all-hidden recovery opens the same anchored draft', (
    tester,
  ) async {
    profiles().updateProfile(
      1,
      (profile) => profile.copyWith(hiddenGroupNames: {'Group A', 'Group B'}),
    );
    await pumpPage(tester);
    final l10n = tester.element(find.byType(ProxiesView)).appLocalizations;
    final recovery = find.descendant(
      of: find.byKey(const ValueKey('proxy-groups-all-hidden')),
      matching: find.text(l10n.groupVisibilityTitle),
    );
    expect(
      find.ancestor(of: recovery, matching: find.byType(PopupAnchor)),
      findsOneWidget,
    );
    await tester.tap(recovery);
    await tester.pumpAndSettle();
    expect(find.byType(GroupVisibilityForm), findsOneWidget);
    await tester.tap(find.byTooltip(l10n.cancel));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('proxy-groups-all-hidden')),
      findsOneWidget,
    );
    expect(profiles().saves, 0);
    expect(tester.takeException(), isNull);
  });

  for (final loading in [false, true]) {
    testWidgets('disabled management ignores pointer-down when '
        '${loading ? 'loading' : 'no profile is selected'}', (tester) async {
      if (loading) {
        container
            .read(loadingProvider(LoadingTag.proxies).notifier)
            .update((_) => true);
      } else {
        container.read(currentProfileIdProvider.notifier).update((_) => null);
      }
      if (loading) {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: TestApp(child: ProxiesView()),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
      } else {
        await pumpPage(tester);
      }
      final gesture = await tester.startGesture(
        tester.getCenter(find.byGlyph(AppGlyphs.sliders)),
      );
      await tester.pump();
      await gesture.up();
      if (loading) {
        await tester.pump(const Duration(milliseconds: 100));
      } else {
        await tester.pumpAndSettle();
      }
      expect(find.byType(GroupVisibilityForm), findsNothing);
      expect(profiles().saves, 0);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(390, 844), const Size(1200, 800)]) {
    testWidgets('panel preserves page query and search transition at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      container.read(viewSizeProvider.notifier).update((_) => size);
      await pumpPage(tester);
      final rest = tester.getRect(find.byGlyph(AppGlyphs.sliders));
      await tester.tap(find.byGlyph(AppGlyphs.search));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final fieldPane = find.ancestor(
        of: find.byType(TextField),
        matching: find.byType(GooPane),
      );
      final growing = tester.getRect(fieldPane);
      await tester.pumpAndSettle();
      final expanded = tester.getRect(fieldPane);
      expect(growing.width, lessThan(expanded.width));
      final pageController = tester
          .widget<TextField>(find.byType(TextField))
          .controller;
      await tester.enterText(find.byType(TextField), 'Node A');
      await tester.pumpAndSettle();
      expect(container.read(queryProvider(QueryTag.proxies)), 'Node A');
      await tester.tap(find.byGlyph(AppGlyphs.sliders).hitTestable().last);
      await tester.pumpAndSettle();
      final panel = find.byType(GroupVisibilityForm);
      expect(panel, findsOneWidget);
      final l10n = tester.element(panel).appLocalizations;
      await tester.enterText(
        find.descendant(of: panel, matching: find.byType(TextField)),
        'Group B',
      );
      await tester.pumpAndSettle();
      expect(container.read(queryProvider(QueryTag.proxies)), 'Node A');
      expect(
        container.read(proxyPageListStateProvider).groups.map((g) => g.name),
        ['Group A'],
      );
      await tester.tap(
        find.descendant(of: panel, matching: find.byTooltip(l10n.cancel)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GroupVisibilityForm), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller,
        same(pageController),
      );
      expect(pageController!.text, 'Node A');
      final scaffold = tester.state<ScaffoldState>(
        find.descendant(
          of: find.byType(ProxiesView),
          matching: find.byType(Scaffold),
        ),
      );
      scaffold.handleExitSearching();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byType(TextField), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(tester.getRect(find.byGlyph(AppGlyphs.sliders)), rest);
      expect(profiles().saves, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty desktop search survives opening and closing the panel', (
    tester,
  ) async {
    const size = Size(1200, 800);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container.read(viewSizeProvider.notifier).update((_) => size);
    await pumpPage(tester);
    await tester.tap(find.byGlyph(AppGlyphs.search));
    await tester.pumpAndSettle();
    final pageController = tester
        .widget<TextField>(find.byType(TextField))
        .controller;
    await tester.tap(find.byGlyph(AppGlyphs.sliders).hitTestable().last);
    await tester.pumpAndSettle();
    final panel = find.byType(GroupVisibilityForm);
    expect(panel, findsOneWidget);
    final l10n = tester.element(panel).appLocalizations;
    await tester.tap(
      find.descendant(of: panel, matching: find.byTooltip(l10n.cancel)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller,
      same(pageController),
    );
    expect(container.read(queryProvider(QueryTag.proxies)), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a draft cannot save after switching profiles and returning', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.tap(find.byGlyph(AppGlyphs.sliders));
    await tester.pumpAndSettle();
    expect(find.byType(GroupVisibilityForm), findsOneWidget);
    final l10n = tester
        .element(find.byType(GroupVisibilityForm))
        .appLocalizations;
    await tester.tap(find.text(l10n.cancelSelectAll));
    await tester.pumpAndSettle();
    container.read(currentProfileIdProvider.notifier).update((_) => 2);
    await tester.pump();
    container.read(currentProfileIdProvider.notifier).update((_) => 1);
    await tester.pump();
    await tester.tap(find.byGlyph(AppGlyphs.check));
    await tester.pumpAndSettle();
    expect(find.byType(GroupVisibilityForm), findsOneWidget);
    expect(
      find.text(l10n.groupVisibilityProfileChanged, findRichText: true),
      findsOneWidget,
    );
    expect(profiles().saves, 0);
    expect(container.read(currentProfileProvider)!.hiddenGroupNames, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
