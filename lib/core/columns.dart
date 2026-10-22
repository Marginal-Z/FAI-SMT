/// Header-row detection and column mapping by keyword aliases.
library;

import 'table_reader.dart';

/// A logical field and the header texts that may name it.
class FieldSpec {
  const FieldSpec(this.key, this.aliases,
      {this.required = false, this.exclude = const []});

  final String key;
  final List<String> aliases;
  final bool required;

  /// Header fragments that disqualify a column (e.g. 主件 for a component field).
  final List<String> exclude;
}

class ColumnMap {
  ColumnMap(this.headerRow, this.columns, this.sheet);

  /// Index of the header row inside [sheet], or -1 when the file has no header.
  final int headerRow;
  final Map<String, int> columns;
  final Grid sheet;

  int? operator [](String key) => columns[key];

  String get(List<String> row, String key) {
    final c = columns[key];
    return (c != null && c < row.length) ? row[c].trim() : '';
  }

  Iterable<List<String>> get dataRows => sheet.rows.skip(headerRow + 1);
}

String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[\s_\-\.:："]'), '')
    .replaceAll('（', '(')
    .replaceAll('）', ')');

/// Drops unit decorations: `Center-X(mm)`, `X/mm`, `X[mil]`.
String _stripParen(String s) =>
    s.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '').replaceAll(RegExp(r'/(mm|mil|inch|in)$'), '');

int _score(String header, String alias) {
  final h = _norm(header);
  final a = _norm(alias);
  if (h.isEmpty || a.isEmpty) return 0;
  if (h == a) return 4;
  if (_stripParen(h) == a) return 3;
  // Short aliases (x, y, r, pn) must match exactly; longer ones may be contained.
  if (a.length >= 2 && !RegExp(r'^[a-z]{1,2}$').hasMatch(a) && h.contains(a)) {
    return 1;
  }
  return 0;
}

/// Finds the best header row among the first rows of every sheet and maps
/// [fields] to columns. Returns null when the required fields are not found.
ColumnMap? detectColumns(List<Grid> sheets, List<FieldSpec> fields,
    {int scanRows = 40}) {
  ColumnMap? best;
  var bestScore = -1;
  for (final sheet in sheets) {
    for (var r = 0; r < sheet.rows.length && r < scanRows; r++) {
      final row = sheet.rows[r];
      final mapping = _mapRow(row, fields);
      if (!fields.where((f) => f.required).every((f) => mapping.containsKey(f.key))) {
        continue;
      }
      final score = mapping.values.fold<int>(0, (a, b) => a + b.$2);
      if (score > bestScore) {
        bestScore = score;
        best = ColumnMap(r, {for (final e in mapping.entries) e.key: e.value.$1}, sheet);
      }
    }
  }
  return best;
}

/// Greedy assignment: strongest (field, column) pairs first, one column per field.
Map<String, (int, int)> _mapRow(List<String> row, List<FieldSpec> fields) {
  final candidates = <(String, int, int)>[];
  for (final f in fields) {
    for (var c = 0; c < row.length; c++) {
      final h = _norm(row[c]);
      if (f.exclude.any((e) => h.contains(_norm(e)))) continue;
      var s = 0;
      for (final a in f.aliases) {
        final v = _score(row[c], a);
        if (v > s) s = v;
      }
      if (s > 0) candidates.add((f.key, c, s));
    }
  }
  candidates.sort((a, b) => b.$3.compareTo(a.$3));
  final out = <String, (int, int)>{};
  final usedCols = <int>{};
  for (final (key, col, score) in candidates) {
    if (out.containsKey(key) || usedCols.contains(col)) continue;
    out[key] = (col, score);
    usedCols.add(col);
  }
  return out;
}

class Fields {
  static const bom = [
    FieldSpec('partNo', ['料件编号', '料号', '子件料号', '元件料号', '物料编码', '物料编号', '料件', 'Part No', 'PartNumber', 'Part Number', 'PN', 'Item'], required: true, exclude: ['主件', 'parent', '替代', '取代']),
    FieldSpec('name', ['品名', '物料名称', '名称', 'Name', 'Item Name'], exclude: ['主件']),
    FieldSpec('spec', ['规格', '物料描述', '描述', '规格描述', 'Spec', 'Specification', 'Description']),
    FieldSpec('qty', ['组成用量', '用量', '数量', '单位用量', 'Qty', 'Quantity', 'Usage']),
    FieldSpec('refs', ['插件位置', '位号', '零件位置', '位置', '插件位号', 'Designator', 'Reference', 'RefDes', 'Location'], required: true),
    FieldSpec('alt', ['替代料号', '替代料', '取替代料号', '取替代料件', '取代料号', 'Alternate', 'Substitute']),
  ];

  static const station = [
    FieldSpec('slot', ['站位', '料站', '站号', '站位号', '料架', 'Feeder', 'Slot', 'Station', 'Location No']),
    FieldSpec('partNo', ['料号', '物料编码', '料件编号', '物料编号', '物料料号', 'Part No', 'PartNumber', 'Part Number', 'PN', 'Component'], required: true, exclude: ['关联', '主料', 'BOM']),
    FieldSpec('related', ['关联料号', '主料号', 'BOM料号', 'Related PN', 'Main PN']),
    FieldSpec('desc', ['物料描述', '描述', '规格', '品名', '物料名称', 'Description', 'Spec', 'Comment']),
    FieldSpec('qty', ['数量', '用量', '点数', '贴装数量', 'Qty', 'Quantity', 'Count']),
    FieldSpec('refs', ['位号', '插件位置', '贴装位号', '位置', 'Designator', 'Reference', 'RefDes', 'Location'], required: true),
  ];

  static const coords = [
    FieldSpec('ref', ['Designator', '位号', 'RefDes', 'Ref', 'Reference', 'Part Designator', 'Name', '元件位号'], required: true),
    FieldSpec('x', ['Center-X', 'Mid X', 'MidX', 'Center X', 'CenterX', 'X', 'X坐标', 'PosX', 'Pos X', 'LocationX', 'Ref X', 'Ref-X'], required: true),
    FieldSpec('y', ['Center-Y', 'Mid Y', 'MidY', 'Center Y', 'CenterY', 'Y', 'Y坐标', 'PosY', 'Pos Y', 'LocationY', 'Ref Y', 'Ref-Y'], required: true),
    FieldSpec('rot', ['Rotation', 'Rot', 'Angle', '角度', '旋转', '旋转角度', 'Orientation', 'Orient', 'R', 'Theta']),
    FieldSpec('layer', ['Layer', 'Side', '面', '面别', 'TB', 'T/B', 'Mirror', '层']),
    FieldSpec('value', ['Comment', 'Value', 'Val', '值', '规格']),
    FieldSpec('footprint', ['Footprint', 'Pattern', 'Package', '封装', 'PCB Footprint', 'Part Type']),
    FieldSpec('smd', ['SMD', 'Mount', 'Type']),
  ];
}
