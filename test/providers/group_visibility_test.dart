import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

import '../helpers/test_profiles.dart';

void main() {
  late ProviderContainer container;
  const groups = [
    Group(
      name: 'A',
      type: GroupType.Selector,
      hidden: false,
      all: [
        Proxy(name: 'Matching node', type: 'Direct'),
        Proxy(name: 'Timed out', type: 'ss'),
        Proxy(name: 'B', type: 'Selector'),
      ],
    ),
    Group(
      name: 'B',
      type: GroupType.Selector,
      hidden: false,
      all: [Proxy(name: 'Matching node', type: 'Direct')],
    ),
    Group(name: 'Configured hidden', type: GroupType.Selector, hidden: true),
  ];

  setUp(() {
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(
          () => TestProfiles([
            Profile(
              id: 1,
              autoUpdateDuration: Duration.zero,
              currentGroupName: 'B',
              selectedMap: {'A': 'B'},
              hiddenGroupNames: {'B'},
            ),
            Profile(
              id: 2,
              autoUpdateDuration: Duration.zero,
              hiddenGroupNames: {'A'},
            ),
          ]),
        ),
      ],
    );
    container.read(currentProfileIdProvider.notifier).update((_) => 1);
    container.read(groupsProvider.notifier).update((_) => groups);
    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mode: Mode.rule));
  });

  tearDown(() => container.dispose());

  List<String> listNames() => container
      .read(proxyPageListStateProvider)
      .groups
      .map((group) => group.name)
      .toList();
  List<String> tabNames() => container
      .read(proxyPageTabStateProvider)
      .groups
      .map((group) => group.name)
      .toList();

  test(
    'main list and tabs hide top-level groups without changing shared data',
    () {
      expect(listNames(), ['A']);
      expect(tabNames(), ['A']);
      expect(container.read(proxyPageTabControllerStateProvider).groupNames, [
        'A',
      ]);
      expect(
        container.read(proxiesListStateProvider).groups.map((g) => g.name),
        ['A', 'B'],
      );
      expect(
        container.read(proxiesTabStateProvider).groups.map((g) => g.name),
        ['A', 'B'],
      );
      expect(
        container.read(visibleGroupsStateProvider).value.map((g) => g.name),
        ['A', 'B'],
      );
      expect(container.read(groupsProvider), groups);
      expect(
        container.read(proxyPageListStateProvider).groups.single.all.last.name,
        'B',
      );
      expect(container.read(currentProfileProvider)!.selectedMap, {'A': 'B'});
      expect(container.read(currentProfileProvider)!.currentGroupName, 'B');
    },
  );

  test('current-tab changes keep the filtered group list stable', () async {
    var groupChanges = 0;
    final subscription = container.listen(
      proxyPageTabStateProvider.select((state) => state.groups),
      (_, _) => groupChanges++,
    );
    addTearDown(subscription.close);
    final before = container.read(proxyPageGroupsProvider(tab: true));
    final profiles = container.read(profilesProvider.notifier) as TestProfiles;
    profiles.updateProfile(
      1,
      (profile) => profile.copyWith(currentGroupName: 'A'),
    );
    await container.pump();
    expect(container.read(proxyPageGroupsProvider(tab: true)), same(before));
    expect(container.read(proxyPageTabStateProvider).currentGroupName, 'A');
    expect(groupChanges, 0);
  });

  test(
    'search cannot reveal hidden groups and does not mutate preferences',
    () {
      container
          .read(queryProvider(QueryTag.proxies).notifier)
          .update((_) => 'Matching');
      expect(listNames(), ['A']);
      expect(tabNames(), ['A']);
      expect(
        container.read(filterGroupsStateProvider('Matching')).value,
        hasLength(2),
      );
      container
          .read(queryProvider(QueryTag.proxies).notifier)
          .update((_) => 'unmatched-query-9182');
      expect(listNames(), isEmpty);
      container
          .read(queryProvider(QueryTag.proxies).notifier)
          .update((_) => '');
      expect(listNames(), ['A']);
      expect(container.read(currentProfileProvider)!.hiddenGroupNames, {'B'});
    },
  );

  test(
    'profile changes isolate visibility and empty defaults restore all eligible groups',
    () {
      expect(listNames(), ['A']);
      container.read(currentProfileIdProvider.notifier).update((_) => 2);
      expect(listNames(), ['B']);
      expect(tabNames(), ['B']);
      final profiles =
          container.read(profilesProvider.notifier) as TestProfiles;
      profiles.updateProfile(
        2,
        (profile) => profile.copyWith(hiddenGroupNames: {}),
      );
      expect(listNames(), ['A', 'B']);
      container.read(currentProfileIdProvider.notifier).update((_) => 1);
      expect(listNames(), ['A']);
    },
  );

  test(
    'mode eligibility remains authoritative and never clears saved names',
    () {
      container
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(mode: Mode.direct));
      expect(listNames(), isEmpty);
      container
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(mode: Mode.global));
      expect(listNames(), ['A', 'Configured hidden']);
      container
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(mode: Mode.rule));
      expect(listNames(), ['A']);
      expect(container.read(currentProfileProvider)!.hiddenGroupNames, {'B'});
    },
  );

  test(
    'all groups can be hidden and new groups keep their default eligibility',
    () {
      final profiles =
          container.read(profilesProvider.notifier) as TestProfiles;
      profiles.updateProfile(
        1,
        (profile) => profile.copyWith(hiddenGroupNames: {'A', 'B'}),
      );
      expect(listNames(), isEmpty);
      expect(tabNames(), isEmpty);
      container
          .read(groupsProvider.notifier)
          .update(
            (_) => [
              ...groups,
              const Group(name: 'New', type: GroupType.Selector, hidden: false),
            ],
          );
      expect(listNames(), ['New']);
      container.read(groupsProvider.notifier).update((_) => []);
      expect(listNames(), isEmpty);
      expect(container.read(currentProfileProvider)!.hiddenGroupNames, {
        'A',
        'B',
      });
    },
  );

  test(
    'main header follows the effective visible group when the saved tab is hidden',
    () {
      final testing = container.read(delayTestingGroupsProvider.notifier);
      testing.start('B');
      expect(container.read(currentGroupDelayTestingProvider), isTrue);
      expect(
        container.read(proxyPageCurrentGroupDelayTestingProvider),
        isFalse,
      );
      testing.stop('B');
      testing.start('A');
      expect(container.read(currentGroupDelayTestingProvider), isFalse);
      expect(container.read(proxyPageCurrentGroupDelayTestingProvider), isTrue);
      container
          .read(profilesProvider.notifier)
          .updateProfile(
            1,
            (profile) => profile.copyWith(hiddenGroupNames: {'A', 'B'}),
          );
      expect(
        container.read(proxyPageCurrentGroupDelayTestingProvider),
        isFalse,
      );
    },
  );

  test(
    'timeout filtering and custom visibility compose without leaking hidden groups',
    () {
      const url = 'https://test.invalid';
      container
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(testUrl: url));
      container
          .read(delayDataSourceProvider.notifier)
          .setDelay(const Delay(url: url, name: 'Timed out', value: -1));
      container
          .read(proxiesStyleSettingProvider.notifier)
          .update((style) => style.copyWith(hideTimeoutProxies: true));
      expect(listNames(), ['A']);
      expect(tabNames(), ['A']);
      expect(
        container
            .read(proxyPageListStateProvider)
            .groups
            .single
            .all
            .map((proxy) => proxy.name),
        ['Matching node', 'B'],
      );
      expect(
        container
            .read(visibleGroupsStateProvider)
            .value
            .map((group) => group.name),
        ['A', 'B'],
      );
      container
          .read(queryProvider(QueryTag.proxies).notifier)
          .update((_) => 'Matching');
      expect(listNames(), ['A']);
      expect(container.read(currentProfileProvider)!.hiddenGroupNames, {'B'});
    },
  );
}
