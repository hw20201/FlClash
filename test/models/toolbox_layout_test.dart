import 'package:fl_clash/models/toolbox_layout.dart';
import 'package:test/test.dart';

void main() {
  group('ToolboxModuleId and ToolboxCardSize', () {
    test('expose stable IDs and dimensions with module constraints', () {
      expect(ToolboxModuleId.values.map((module) => module.id), [
        'exitIp',
        'dnsLookup',
        'trafficStatistics',
      ]);
      expect(
        ToolboxCardSize.values.map(
          (size) => (size.id, size.columns, size.rows),
        ),
        [('1x1', 1, 1), ('2x1', 2, 1), ('1x2', 1, 2), ('2x2', 2, 2)],
      );
      for (final module in [
        ToolboxModuleId.exitIp,
        ToolboxModuleId.dnsLookup,
      ]) {
        expect(module.allows(ToolboxCardSize.large), isFalse);
      }
      expect(
        ToolboxModuleId.trafficStatistics.allows(ToolboxCardSize.large),
        isTrue,
      );
    });
  });

  group('ToolboxLayout JSON', () {
    test('defaults every module to 1x1', () {
      final layout = ToolboxLayout.defaults();

      for (final module in ToolboxModuleId.values) {
        expect(layout.sizeOf(module), ToolboxCardSize.small);
      }
    });

    test('recovers from malformed and unsupported schema payloads', () {
      for (final source in [
        '{',
        '{"schemaVersion":0,"modules":{"exitIp":"2x1"}}',
        '{"modules":{"exitIp":"2x1"}}',
        '{"schemaVersion":1,"modules":[]}',
      ]) {
        expect(ToolboxLayout.decode(source), ToolboxLayout.defaults());
      }
    });

    test('defaults missing, unknown, and illegal module values', () {
      final layout = ToolboxLayout.decode(
        '{"schemaVersion":1,"modules":{'
        '"exitIp":"2x2",'
        '"dnsLookup":"2x1",'
        '"retiredModule":"1x2"'
        '}}',
      );

      expect(layout.sizeOf(ToolboxModuleId.exitIp), ToolboxCardSize.small);
      expect(layout.sizeOf(ToolboxModuleId.dnsLookup), ToolboxCardSize.wide);
      expect(
        layout.sizeOf(ToolboxModuleId.trafficStatistics),
        ToolboxCardSize.small,
      );
    });

    test('encodes canonically and decodes back to the same layout', () {
      final layout = ToolboxLayout.defaults()
          .withSize(ToolboxModuleId.exitIp, ToolboxCardSize.wide)
          .withSize(ToolboxModuleId.dnsLookup, ToolboxCardSize.tall)
          .withSize(ToolboxModuleId.trafficStatistics, ToolboxCardSize.large);
      final encoded = layout.encode();

      expect(
        encoded,
        '{"schemaVersion":1,"modules":{"exitIp":"2x1",'
        '"dnsLookup":"1x2","trafficStatistics":"2x2"}}',
      );
      expect(ToolboxLayout.decode(encoded), layout);
    });
  });

  group('ToolboxLayout packing', () {
    test('packs deterministically in product order without overlap', () {
      final layout = ToolboxLayout.defaults()
          .withSize(ToolboxModuleId.exitIp, ToolboxCardSize.wide)
          .withSize(ToolboxModuleId.dnsLookup, ToolboxCardSize.tall)
          .withSize(ToolboxModuleId.trafficStatistics, ToolboxCardSize.large);

      for (final columnCount in [2, 4]) {
        final placements = layout.pack(columnCount: columnCount);

        expect(
          placements.map((placement) => placement.moduleId),
          ToolboxModuleId.values,
        );
        expect(layout.pack(columnCount: columnCount), placements);
        _expectPlacementsFit(placements, columnCount);
      }
    });

    test('clamps only the placement span in a one-column grid', () {
      final layout = ToolboxLayout.defaults().withSize(
        ToolboxModuleId.exitIp,
        ToolboxCardSize.wide,
      );
      final encodedBeforePacking = layout.encode();
      final exitPlacement = layout.pack(columnCount: 1).first;

      expect(exitPlacement.size, ToolboxCardSize.wide);
      expect(exitPlacement.columnSpan, 1);
      expect(layout.sizeOf(ToolboxModuleId.exitIp), ToolboxCardSize.wide);
      expect(layout.encode(), encodedBeforePacking);
      _expectPlacementsFit(layout.pack(columnCount: 1), 1);
    });

    test('requires a positive column count', () {
      expect(
        () => ToolboxLayout.defaults().pack(columnCount: 0),
        throwsArgumentError,
      );
    });
  });

  test('rejects an illegal size change without altering the layout', () {
    final layout = ToolboxLayout.defaults();

    expect(
      () => layout.withSize(ToolboxModuleId.exitIp, ToolboxCardSize.large),
      throwsArgumentError,
    );
    expect(layout.sizeOf(ToolboxModuleId.exitIp), ToolboxCardSize.small);
    expect(
      ToolboxLayout.fromSizes({
        ToolboxModuleId.exitIp: ToolboxCardSize.large,
      }).sizeOf(ToolboxModuleId.exitIp),
      ToolboxCardSize.small,
    );
  });
}

void _expectPlacementsFit(
  List<ToolboxCardPlacement> placements,
  int columnCount,
) {
  final occupied = <(int, int)>{};
  for (final placement in placements) {
    expect(placement.row, greaterThanOrEqualTo(0));
    expect(placement.column, greaterThanOrEqualTo(0));
    expect(
      placement.column + placement.columnSpan,
      lessThanOrEqualTo(columnCount),
    );
    expect(placement.columnSpan, lessThanOrEqualTo(placement.size.columns));
    expect(placement.rowSpan, placement.size.rows);
    for (var rowOffset = 0; rowOffset < placement.rowSpan; rowOffset++) {
      for (
        var columnOffset = 0;
        columnOffset < placement.columnSpan;
        columnOffset++
      ) {
        expect(
          occupied.add((
            placement.row + rowOffset,
            placement.column + columnOffset,
          )),
          isTrue,
        );
      }
    }
  }
}
