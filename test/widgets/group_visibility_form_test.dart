import 'dart:async';

import 'package:fl_clash/common/exception.dart';
import 'package:fl_clash/features/form/form_row.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/widgets/group_visibility_form.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/host_scaffold.dart';
import '../helpers/test_app.dart';

Future<void> _open(
  WidgetTester tester, {
  List<String> groupNames = const ['Alpha', 'BETA', 'Gamma'],
  Set<String> hiddenGroupNames = const {},
  required Future<void> Function(Set<String>) onSave,
  Size size = const Size(1000, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    TestApp(
      locale: const Locale('en'),
      overrides: [viewSizeProvider.overrideWithBuild((_, _) => size)],
      child: HostScaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: PopupAnchor(
            targetBuilder: (open) =>
                TextButton(onPressed: open, child: const Text('open')),
            popupBuilder: (_) => GroupVisibilityForm(
              groupNames: groupNames,
              hiddenGroupNames: hiddenGroupNames,
              onSave: onSave,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(
    ModalRoute.of(tester.element(find.byType(GroupVisibilityForm))),
    isA<AnchoredPopupRoute<void>>(),
  );
}

Finder _row(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(FormRow));

Finder _switch(String name) =>
    find.descendant(of: _row(name), matching: find.byType(Switch));

bool _visible(WidgetTester tester, String name) =>
    tester.widget<Switch>(_switch(name)).value;

Finder get _save => find.byTooltip('Save');
Finder get _cancel => find.byTooltip('Cancel');

IconButton _headerButton(WidgetTester tester, String tooltip) =>
    tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip(tooltip),
        matching: find.byType(IconButton),
      ),
    );

Finder get _search => find.descendant(
  of: find.byType(SearchField),
  matching: find.byType(TextField),
);

void main() {
  testWidgets(
    'copies the hidden draft and counts only current eligible groups',
    (tester) async {
      final hidden = {'BETA', 'Missing'};
      Set<String>? saved;
      await _open(
        tester,
        groupNames: const ['Alpha', 'BETA', 'Gamma', 'Alpha'],
        hiddenGroupNames: hidden,
        onSave: (value) async => saved = value,
      );

      expect(find.byType(Switch), findsNWidgets(3));
      expect(find.text('2 of 3 groups visible'), findsOneWidget);
      expect(_visible(tester, 'Alpha'), isTrue);
      expect(_visible(tester, 'BETA'), isFalse);
      await tester.tap(_row('Alpha'));
      await tester.pumpAndSettle();

      expect(_visible(tester, 'Alpha'), isFalse);
      expect(hidden, {'BETA', 'Missing'});
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(saved, {'Alpha', 'BETA', 'Missing'});
      expect(identical(saved, hidden), isFalse);
      expect(find.byType(GroupVisibilityForm), findsNothing);
    },
  );

  testWidgets('joined bulk buttons use softened inner corners', (tester) async {
    await _open(tester, hiddenGroupNames: {'BETA'}, onSave: (_) async {});

    final buttons = tester
        .widgetList<ConnectedButton>(
          find.descendant(
            of: find.byType(ConnectedButtonGroup),
            matching: find.byType(ConnectedButton),
          ),
        )
        .toList();
    expect(buttons, hasLength(2));
    expect(buttons.every((button) => !button.selected), isTrue);
    expect(buttons.map((button) => button.inner), everyElement(AppCorner.md));
    final buttonFinder = find.descendant(
      of: find.byType(ConnectedButtonGroup),
      matching: find.byType(ConnectedButton),
    );
    for (var index = 0; index < buttons.length; index++) {
      final surface = find.descendant(
        of: buttonFinder.at(index),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container && widget.decoration is ShapeDecoration,
        ),
      );
      final size = tester.getSize(surface);
      final decoration =
          tester.widget<Container>(surface).decoration! as ShapeDecoration;
      final path = decoration.shape.getOuterPath(Offset.zero & size);
      final innerX = index == 0 ? size.width - 1 : 1.0;
      final insetX = index == 0 ? size.width - 10 : 10.0;
      expect(path.contains(Offset(innerX, 1)), isFalse);
      expect(path.contains(Offset(insetX, 10)), isTrue);
    }
    expect(buttons.first.first, isTrue);
    expect(buttons.first.last, isFalse);
    expect(buttons.last.first, isFalse);
    expect(buttons.last.last, isTrue);
  });

  testWidgets('bulk actions affect only case-insensitive search matches', (
    tester,
  ) async {
    Set<String>? saved;
    await _open(
      tester,
      hiddenGroupNames: {'Gamma', 'Missing'},
      onSave: (value) async => saved = value,
    );

    await tester.enterText(_search, 'aLP');
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('BETA'), findsNothing);
    await tester.tap(find.text('Deselect all'));
    await tester.pumpAndSettle();
    expect(_visible(tester, 'Alpha'), isFalse);
    expect(find.text('1 of 3 groups visible'), findsOneWidget);

    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(_visible(tester, 'Alpha'), isTrue);
    await tester.enterText(_search, 'bEt');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deselect all'));
    await tester.pumpAndSettle();
    await tester.tap(_save);
    await tester.pumpAndSettle();

    expect(saved, {'BETA', 'Gamma', 'Missing'});
  });

  testWidgets('reset clears the entire draft even with an unmatched search', (
    tester,
  ) async {
    Set<String>? saved;
    await _open(
      tester,
      hiddenGroupNames: {'Alpha', 'BETA', 'Gamma', 'Missing'},
      onSave: (value) async => saved = value,
    );

    await tester.enterText(_search, 'not a group');
    await tester.pumpAndSettle();
    expect(find.text('No matching results'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    await tester.tap(find.byTooltip('Reset'));
    await tester.pumpAndSettle();
    expect(find.text('3 of 3 groups visible'), findsOneWidget);
    await tester.tap(_save);
    await tester.pumpAndSettle();

    expect(saved, isEmpty);
  });

  testWidgets('cancel discards changes and reopening uses the original input', (
    tester,
  ) async {
    var saves = 0;
    final hidden = {'BETA'};
    await _open(tester, hiddenGroupNames: hidden, onSave: (_) async => saves++);

    await tester.tap(_switch('Alpha'));
    await tester.pumpAndSettle();
    await tester.tap(_cancel);
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(hidden, {'BETA'});
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(_visible(tester, 'Alpha'), isTrue);
    expect(_visible(tester, 'BETA'), isFalse);
  });

  testWidgets('awaits one save and blocks further draft changes while saving', (
    tester,
  ) async {
    final pending = Completer<void>();
    var saves = 0;
    await _open(
      tester,
      onSave: (_) {
        saves++;
        return pending.future;
      },
    );

    await tester.tap(_switch('BETA'));
    await tester.pumpAndSettle();
    await tester.tap(_save);
    await tester.pump();
    expect(find.byType(ActivityIndicator), findsOneWidget);
    expect(_headerButton(tester, 'Save').onPressed, isNull);
    expect(_headerButton(tester, 'Reset').onPressed, isNull);
    expect(find.byType(GroupVisibilityForm), findsOneWidget);
    expect(tester.widget<Switch>(_switch('Alpha')).onChanged, isNull);
    await tester.tap(_switch('Alpha'));
    await tester.tap(_row('Gamma'));
    await tester.tap(find.byTooltip('Reset'));
    await tester.tap(find.text('Deselect all'));
    await tester.pump();
    expect(saves, 1);
    expect(_visible(tester, 'Alpha'), isTrue);
    expect(_visible(tester, 'BETA'), isFalse);
    expect(_visible(tester, 'Gamma'), isTrue);

    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(GroupVisibilityForm), findsNothing);
  });

  testWidgets('duplicate save taps and a retained handler share one save', (
    tester,
  ) async {
    final pending = Completer<void>();
    var saves = 0;
    await _open(
      tester,
      onSave: (_) {
        saves++;
        return pending.future;
      },
    );
    final save = _headerButton(tester, 'Save').onPressed!;

    await tester.tap(_save);
    save();
    await tester.pump();
    await tester.tap(_save);
    save();
    await tester.pump();
    expect(saves, 1);
    expect(find.byType(ActivityIndicator), findsOneWidget);
    expect(find.byType(GroupVisibilityForm), findsOneWidget);

    pending.complete();
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(find.byType(GroupVisibilityForm), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed save stays open with a readable error and can retry', (
    tester,
  ) async {
    var attempts = 0;
    await _open(
      tester,
      onSave: (_) async {
        attempts++;
        if (attempts == 1) {
          throw const MessageException('The active profile changed.');
        }
      },
    );

    await tester.tap(_switch('BETA'));
    await tester.pumpAndSettle();
    await tester.tap(_save);
    await tester.pumpAndSettle();

    expect(find.byType(ActivityIndicator), findsNothing);
    expect(_headerButton(tester, 'Save').onPressed, isNotNull);
    expect(_headerButton(tester, 'Reset').onPressed, isNotNull);
    expect(find.byType(GroupVisibilityForm), findsOneWidget);
    expect(find.text('The active profile changed.'), findsOneWidget);
    expect(_visible(tester, 'BETA'), isFalse);
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byType(GroupVisibilityForm), findsNothing);
  });

  testWidgets('empty group list has an empty state and can reset stale names', (
    tester,
  ) async {
    Set<String>? saved;
    await _open(
      tester,
      groupNames: const [],
      hiddenGroupNames: {'Missing'},
      onSave: (value) async => saved = value,
    );

    expect(find.text('No proxy groups available'), findsOneWidget);
    expect(find.text('0 of 0 groups visible'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    await tester.tap(find.byTooltip('Reset'));
    await tester.pumpAndSettle();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
  });

  testWidgets('empty and long names retain their exact save keys', (
    tester,
  ) async {
    final longName = List.filled(30, 'A long group name ').join();
    Set<String>? saved;
    await _open(
      tester,
      groupNames: ['', longName],
      onSave: (value) async => saved = value,
    );

    expect(find.text('Unnamed'), findsOneWidget);
    expect(find.text(longName), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Deselect all'));
    await tester.pumpAndSettle();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(saved, {'', longName});
  });

  testWidgets('phone popup keeps controls reachable above the keyboard', (
    tester,
  ) async {
    Set<String>? saved;
    await _open(
      tester,
      size: const Size(390, 844),
      groupNames: [for (var index = 0; index < 35; index++) 'Group $index'],
      onSave: (value) async => saved = value,
    );

    await tester.tap(_search);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    final popup = tester.getRect(find.byType(GroupVisibilityForm));
    expect(popup.left, greaterThanOrEqualTo(0));
    expect(popup.right, lessThanOrEqualTo(390));
    expect(popup.top, greaterThanOrEqualTo(0));
    expect(popup.bottom, lessThanOrEqualTo(544));
    expect(popup.width, lessThanOrEqualTo(420));
    expect(popup.height, lessThanOrEqualTo(640));
    expect(_search.hitTestable(), findsOneWidget);
    expect(find.text('Select all').hitTestable(), findsOneWidget);
    expect(find.text('Deselect all').hitTestable(), findsOneWidget);
    expect(_cancel.hitTestable(), findsOneWidget);
    expect(find.byTooltip('Reset').hitTestable(), findsOneWidget);
    expect(_save.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      _switch('Group 34'),
      240,
      scrollable: find
          .descendant(
            of: find.byType(GroupVisibilityForm),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(_switch('Group 34').hitTestable(), findsOneWidget);
    expect(tester.getRect(_switch('Group 34')).bottom, lessThanOrEqualTo(544));
    await tester.tap(_switch('Group 34'));
    await tester.pumpAndSettle();
    expect(_visible(tester, 'Group 34'), isFalse);
    expect(_cancel.hitTestable(), findsOneWidget);
    expect(find.byTooltip('Reset').hitTestable(), findsOneWidget);
    expect(_save.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(saved, {'Group 34'});
    expect(find.byType(GroupVisibilityForm), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save completion after dismissal does not pop the parent', (
    tester,
  ) async {
    final pending = Completer<void>();
    await _open(tester, onSave: (_) => pending.future);
    await tester.tap(_save);
    await tester.pump();
    await tester.tap(_cancel);
    await tester.pumpAndSettle();

    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(find.byType(GroupVisibilityForm), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a dismissed pending save does not pop a newly pushed route', (
    tester,
  ) async {
    final pending = Completer<void>();
    await _open(tester, onSave: (_) => pending.future);
    final popupContext = tester.element(find.byType(GroupVisibilityForm));
    final navigator = Navigator.of(popupContext);

    await tester.tap(_save);
    await tester.pump();
    await tester.tap(_cancel);
    unawaited(
      navigator.push(
        HostPageRoute<void>(
          builder: (_) => const HostScaffold(body: Text('next route')),
        ),
      ),
    );
    expect(popupContext.mounted, isTrue);
    pending.complete();
    await tester.pumpAndSettle();

    expect(find.text('next route'), findsOneWidget);
    expect(navigator.canPop(), isTrue);
    expect(find.byType(GroupVisibilityForm), findsNothing);
    expect(tester.takeException(), isNull);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('open').hitTestable(), findsOneWidget);
  });

  testWidgets('a retained save handler does nothing after disposal', (
    tester,
  ) async {
    var saves = 0;
    await _open(tester, onSave: (_) async => saves++);
    final save = _headerButton(tester, 'Save').onPressed!;
    await tester.tap(_cancel);
    await tester.pumpAndSettle();

    save();
    await tester.pump();
    expect(saves, 0);
    expect(tester.takeException(), isNull);
  });
}
