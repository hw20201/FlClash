import 'dart:convert';

enum ToolboxModuleId {
  exitIp('exitIp'),
  dnsLookup('dnsLookup'),
  trafficStatistics('trafficStatistics');

  const ToolboxModuleId(this.id);

  final String id;

  bool allows(ToolboxCardSize size) =>
      size != ToolboxCardSize.large || this == trafficStatistics;

  static ToolboxModuleId? fromId(Object? id) {
    for (final module in values) {
      if (module.id == id) {
        return module;
      }
    }
    return null;
  }
}

enum ToolboxCardSize {
  small('1x1', 1, 1),
  wide('2x1', 2, 1),
  tall('1x2', 1, 2),
  large('2x2', 2, 2);

  const ToolboxCardSize(this.id, this.columns, this.rows);

  final String id;
  final int columns;
  final int rows;

  static ToolboxCardSize? fromId(Object? id) {
    for (final size in values) {
      if (size.id == id) {
        return size;
      }
    }
    return null;
  }
}

final class ToolboxLayout {
  static const schemaVersion = 1;

  final Map<ToolboxModuleId, ToolboxCardSize> sizes;

  ToolboxLayout._(this.sizes);

  factory ToolboxLayout.defaults() => ToolboxLayout.fromSizes(const {});

  factory ToolboxLayout.fromSizes(Map<ToolboxModuleId, ToolboxCardSize> sizes) {
    final normalized = <ToolboxModuleId, ToolboxCardSize>{};
    for (final module in ToolboxModuleId.values) {
      final size = sizes[module];
      normalized[module] = size != null && module.allows(size)
          ? size
          : ToolboxCardSize.small;
    }
    return ToolboxLayout._(Map.unmodifiable(normalized));
  }

  factory ToolboxLayout.decode(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      return ToolboxLayout.defaults();
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['schemaVersion'] != schemaVersion) {
      return ToolboxLayout.defaults();
    }
    final modules = decoded['modules'];
    if (modules is! Map<String, dynamic>) {
      return ToolboxLayout.defaults();
    }

    final sizes = <ToolboxModuleId, ToolboxCardSize>{};
    for (final module in ToolboxModuleId.values) {
      final size = ToolboxCardSize.fromId(modules[module.id]);
      sizes[module] = size != null && module.allows(size)
          ? size
          : ToolboxCardSize.small;
    }
    return ToolboxLayout.fromSizes(sizes);
  }

  ToolboxCardSize sizeOf(ToolboxModuleId module) => sizes[module]!;

  ToolboxLayout withSize(ToolboxModuleId module, ToolboxCardSize size) {
    if (!module.allows(size)) {
      throw ArgumentError.value(
        size,
        'size',
        '${module.id} does not allow ${size.id}',
      );
    }
    return ToolboxLayout.fromSizes({...sizes, module: size});
  }

  String encode() => jsonEncode({
    'schemaVersion': schemaVersion,
    'modules': {
      for (final module in ToolboxModuleId.values) module.id: sizeOf(module).id,
    },
  });

  List<ToolboxCardPlacement> pack({required int columnCount}) {
    if (columnCount <= 0) {
      throw ArgumentError.value(
        columnCount,
        'columnCount',
        'Must be positive.',
      );
    }

    final occupied = <int, Set<int>>{};
    final placements = <ToolboxCardPlacement>[];
    for (final module in ToolboxModuleId.values) {
      final size = sizeOf(module);
      final columnSpan = size.columns < columnCount
          ? size.columns
          : columnCount;
      var row = 0;
      var column = 0;
      while (true) {
        var found = false;
        for (
          var candidate = 0;
          candidate <= columnCount - columnSpan;
          candidate++
        ) {
          if (!_fits(occupied, row, candidate, columnSpan, size.rows)) {
            continue;
          }
          column = candidate;
          found = true;
          break;
        }
        if (found) {
          break;
        }
        row++;
      }

      for (var rowOffset = 0; rowOffset < size.rows; rowOffset++) {
        final occupiedColumns = occupied.putIfAbsent(
          row + rowOffset,
          () => <int>{},
        );
        for (var columnOffset = 0; columnOffset < columnSpan; columnOffset++) {
          occupiedColumns.add(column + columnOffset);
        }
      }
      placements.add(
        ToolboxCardPlacement(
          moduleId: module,
          size: size,
          row: row,
          column: column,
          columnSpan: columnSpan,
          rowSpan: size.rows,
        ),
      );
    }
    return List.unmodifiable(placements);
  }

  @override
  bool operator ==(Object other) =>
      other is ToolboxLayout &&
      ToolboxModuleId.values.every(
        (module) => other.sizeOf(module) == sizeOf(module),
      );

  @override
  int get hashCode => Object.hashAll([
    for (final module in ToolboxModuleId.values) sizeOf(module),
  ]);
}

final class ToolboxCardPlacement {
  const ToolboxCardPlacement({
    required this.moduleId,
    required this.size,
    required this.row,
    required this.column,
    required this.columnSpan,
    required this.rowSpan,
  });

  final ToolboxModuleId moduleId;
  final ToolboxCardSize size;
  final int row;
  final int column;
  final int columnSpan;
  final int rowSpan;

  @override
  bool operator ==(Object other) =>
      other is ToolboxCardPlacement &&
      other.moduleId == moduleId &&
      other.size == size &&
      other.row == row &&
      other.column == column &&
      other.columnSpan == columnSpan &&
      other.rowSpan == rowSpan;

  @override
  int get hashCode =>
      Object.hash(moduleId, size, row, column, columnSpan, rowSpan);
}

bool _fits(
  Map<int, Set<int>> occupied,
  int row,
  int column,
  int columnSpan,
  int rowSpan,
) {
  for (var rowOffset = 0; rowOffset < rowSpan; rowOffset++) {
    final occupiedColumns = occupied[row + rowOffset];
    for (var columnOffset = 0; columnOffset < columnSpan; columnOffset++) {
      if (occupiedColumns?.contains(column + columnOffset) ?? false) {
        return false;
      }
    }
  }
  return true;
}
