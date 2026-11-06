import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'package:fl_clash/views/network_toolbox_home.dart';
import 'package:fl_clash/views/network_toolbox.dart';
import 'package:fl_clash/views/toolbox_utilities.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets(
    'toolbox cards render on phone and navigate without network traffic',
    (tester) async {
      // Render a legible CI preview instead of square Ahem glyphs.
      final previewFont = File(
        '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
      );
      if (previewFont.existsSync()) {
        await tester.runAsync(() async {
          final loader = FontLoader('Ahem')
            ..addFont(
              Future.value(ByteData.sublistView(previewFont.readAsBytesSync())),
            );
          await loader.load();
        });
      }
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const TestApp(
          locale: Locale('zh', 'CN'),
          wrapInProviderScope: true,
          child: RepaintBoundary(
            key: ValueKey('preview'),
            child: NetworkToolboxHome(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('toolbox-all')), findsOneWidget);
      expect(find.byKey(const ValueKey('toolbox-route')), findsOneWidget);
      expect(find.byKey(const ValueKey('toolbox-speed')), findsOneWidget);
      expect(find.byKey(const ValueKey('toolbox-ip')), findsOneWidget);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('preview')),
      );
      // Engine image encoding needs real asynchronous time, not the test clock.
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory("build/toolbox-preview").createSync(recursive: true);
        File("build/toolbox-preview/toolbox-phone.png")
            .writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
      await tester.tap(find.byKey(const ValueKey('toolbox-dns')));
      await tester.pumpAndSettle();
      expect(find.byType(NetworkToolboxView), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('subnet calculator computes locally', (tester) async {
    await tester.pumpWidget(
      const TestApp(
        locale: Locale('en'),
        wrapInProviderScope: true,
        child: ToolboxUtilityView(tool: ToolboxUtility.subnet),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), '192.168.1.10/24');
    await tester.tap(find.text('Calculate'));
    await tester.pumpAndSettle();
    expect(find.textContaining('192.168.1.0/24'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('large text and narrow screens stack cards without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      TestApp(
        locale: const Locale('en'),
        wrapInProviderScope: true,
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.8)),
            child: const NetworkToolboxHome(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
