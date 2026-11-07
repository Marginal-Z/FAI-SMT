/// BOM files: finds the header row and works out what each column holds
/// from its contents (part number, description, quantity, designators, other
/// columns), not from the header text alone, then reads the parts.
library;

import 'dart:math' as math;

import 'bom_model.dart';
import 'refdes.dart';
import 'table_reader.dart';

export 'bom_model.dart';

class BomReadException implements Exception {
  BomReadException(this.code);

  /// `bom_empty`, `bom_no_parts`.
  final String code;

  @override
  String toString() => 'BomReadException($code)';
}

// ---------------------------------------------------------------- text helpers

/// Full-width letters, digits and symbols to their ASCII forms.
String toHalfWidth(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0xFF01 && r <= 0xFF5E) {
      b.writeCharCode(r - 0xFEE0);
    } else if (r == 0x3000) {
      b.write(' ');
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

/// A cell value as compared: half-width, trimmed, inner runs of spaces made one.
String cleanCell(String s) => toHalfWidth(s).replaceAll(RegExp(r'\s+'), ' ').trim();

final _cjk = RegExp(r'[⺀-鿿豈-﫿]');
final _numberCell = RegExp(r'^-?\d+(?:\.\d+)?$');
final _designator = RegExp(r'^\d{0,3}[A-Z]{1,6}\d{1,5}[A-Z]?$');
final _partNoLike = RegExp(r'^[A-Za-z0-9][A-Za-z0-9\-_./#]{3,39}$');
final _param = RegExp(r'\d+(?:\.\d+)?\s?(?:K|M|R|Ω|UF|NF|PF|MF|UH|NH|MH|V|W|A|%|MHZ|KHZ|HZ|PPM)\b|\b(?:01005|0201|0402|0603|0805|1206|1210|2512)\b', caseSensitive: false);

double? parseQuantity(String s) {
  final t = toHalfWidth(s).replaceAll(',', '').trim();
  if (t.isEmpty) return null;
  final m = RegExp(r'^-?\d+(?:\.\d+)?').firstMatch(t);
  return m == null ? null : double.tryParse(m.group(0)!);
}

String formatQuantity(double? q) {
  if (q == null) return '';
  return q == q.roundToDouble() ? q.toInt().toString() : q.toString();
}

// ------------------------------------------------------------- header hints

const _hints = <BomRole, List<String>>{
  BomRole.partNo: ['料号', '料件编号', '物料编码', '物料编号', '物料代码', '品号', '元件编号', '组件料号', '编码', 'partno', 'partnumber', 'p/n', 'pn', 'itemcode', 'material'],
  BomRole.description: ['描述', '品名', '规格', '名称', '型号规格', '物料名称', '物料描述', 'description', 'desc', 'value', 'comment', 'spec'],
  BomRole.quantity: ['用量', '数量', '组成用量', '单机用量', '单位用量', 'qty', 'quantity', 'count', 'usage'],
  BomRole.refs: ['位号', '插件位置', '元件位置', '点位', '位置', 'designator', 'reference', 'refdes', 'ref', 'location', 'position'],
  BomRole.serial: ['序号', '项次', '项目', '行号', 'no', 'no.', 'item', '#', 'line'],
};

String _norm(String h) => toHalfWidth(h).toLowerCase().replaceAll(RegExp(r'[\s_]+'), '');

double _hint(String header, BomRole role) {
  final h = _norm(header);
  if (h.isEmpty) return 0;
  for (final w in _hints[role]!) {
    if (h == w) return 1.0;
  }
  for (final w in _hints[role]!) {
    if (w.length >= 2 && h.contains(w)) return 0.7;
  }
  return 0;
}

// ----------------------------------------------------------------- detection

/// Picks the sheet that looks most like a BOM and reads it. [file] is the
/// file name and [id] the document's tag in a check; both end up in every
/// record's source reference.
BomDocument readBom(List<Grid> sheets, {String file = '', String id = 'S'}) {
  BomDocument? best;
  var bestScore = -1.0;
  final names = [for (final g in sheets) g.name];
  for (final g in sheets) {
    try {
      final f = _readSheet(g, file: file, id: id, sheets: names);
      final score = f.parts.length.toDouble() + (f.column(BomRole.refs) != null ? 5 : 0) + (f.column(BomRole.partNo) != null ? 5 : 0);
      if (score > bestScore) {
        best = f;
        bestScore = score;
      }
    } on BomReadException {
      continue;
    }
  }
  if (best == null) throw BomReadException(sheets.every((g) => g.rows.isEmpty) ? 'bom_empty' : 'bom_no_parts');
  return best;
}

/// Header row: the row in the first 30 with the most header words; without
/// any, the first wide row followed by data rows when its own cells are text.
int _headerRow(Grid g) {
  var best = -1;
  var bestScore = 0.0;
  final limit = math.min(30, g.rows.length);
  for (var r = 0; r < limit; r++) {
    final cells = g.rows[r].where((c) => c.trim().isNotEmpty).toList();
    if (cells.length < 2) continue;
    var score = 0.0;
    for (final c in cells) {
      var h = 0.0;
      for (final role in _hints.keys) {
        h = math.max(h, _hint(c, role));
      }
      score += h;
    }
    if (score > bestScore) {
      bestScore = score;
      best = r;
    }
  }
  if (bestScore >= 1.4) return best;
  for (var r = 0; r < limit - 1; r++) {
    final cells = g.rows[r].where((c) => c.trim().isNotEmpty).toList();
    if (cells.length < 3) continue;
    final textOnly = cells.every((c) => !_numberCell.hasMatch(cleanCell(c)));
    final next = g.rows[r + 1].where((c) => c.trim().isNotEmpty).toList();
    if (textOnly && next.length >= 3 && next.any((c) => _numberCell.hasMatch(cleanCell(c)) || splitRefs(c).every(_designator.hasMatch))) return r;
    return -1;
  }
  return -1;
}

class _Features {
  double fill = 0, refs = 0, refsMany = 0, number = 0, index = 0, partNo = 0, unique = 0, text = 0, avgLen = 0;
}

_Features _features(List<String> values, int rows) {
  final f = _Features();
  final v = values.where((s) => s.isNotEmpty).toList();
  if (v.isEmpty || rows == 0) return f;
  f.fill = v.length / rows;
  var refs = 0, many = 0, num = 0, pn = 0, text = 0, len = 0;
  int? prev;
  var consecutive = 0;
  for (final s in v) {
    len += s.length;
    final tokens = splitRefs(s);
    if (tokens.isNotEmpty && tokens.every(_designator.hasMatch)) {
      refs++;
      if (tokens.length > 1) many++;
    }
    if (_numberCell.hasMatch(s)) {
      num++;
      final n = int.tryParse(s);
      if (n != null && prev != null && n == prev + 1) consecutive++;
      prev = n;
    }
    if (_partNoLike.hasMatch(s) && RegExp(r'\d').hasMatch(s) && !_numberCell.hasMatch(s) && !_designator.hasMatch(s.toUpperCase())) pn++;
    if (_cjk.hasMatch(s) || _param.hasMatch(s) || s.contains(' ')) text++;
  }
  f.refs = refs / v.length;
  f.refsMany = many / v.length;
  f.number = num / v.length;
  f.index = v.length > 2 ? consecutive / (v.length - 1) : 0;
  f.partNo = pn / v.length;
  f.unique = v.toSet().length / v.length;
  f.text = text / v.length;
  f.avgLen = len / v.length;
  return f;
}

BomDocument _readSheet(Grid g, {required String file, required String id, required List<String> sheets}) {
  final headerRow = _headerRow(g);
  final width = g.rows.fold<int>(0, (m, r) => math.max(m, r.length));
  if (width == 0) throw BomReadException('bom_empty');
  final data = [
    for (var r = headerRow + 1; r < g.rows.length; r++)
      if (g.rows[r].any((c) => c.trim().isNotEmpty)) r,
  ];
  if (data.isEmpty) throw BomReadException('bom_no_parts');
  String header(int c) => headerRow >= 0 ? cleanCell(g.cell(headerRow, c)) : '';
  final features = [for (var c = 0; c < width; c++) _features([for (final r in data) cleanCell(g.cell(r, c))], data.length)];

  final used = <int>{};
  // Score of each picked column, as its confidence.
  final scores = <int, double>{};
  int? pick(double Function(int c) score, {double min = 0.35}) {
    int? best;
    var bestScore = min;
    for (var c = 0; c < width; c++) {
      if (used.contains(c) || features[c].fill < 0.05) continue;
      final s = score(c);
      if (s > bestScore) {
        bestScore = s;
        best = c;
      }
    }
    if (best != null) {
      used.add(best);
      scores[best] = bestScore;
    }
    return best;
  }

  // What a recognition was based on: the header, the contents, or both.
  String evidence(int c, BomRole role) {
    final byHeader = _hint(header(c), role) > 0;
    final f = features[c];
    final byContent = switch (role) {
      BomRole.refs => f.refs > 0.5,
      BomRole.quantity => f.number > 0.6,
      BomRole.partNo => f.partNo > 0.4,
      BomRole.description => f.text > 0.4,
      BomRole.serial => f.index > 0.8,
      BomRole.other => false,
    };
    return [if (byHeader) 'header', if (byContent) 'content'].join('+');
  }

  BomColumn col(int c, BomRole role, {String label = ''}) =>
      BomColumn(c, header(c), role, label: label, confidence: (scores[c] ?? 1).clamp(0.0, 1.0).toDouble(), evidence: evidence(c, role));

  // Sequential numbers (序号) are not compared.
  final indexCols = <int>{
    for (var c = 0; c < width; c++)
      if ((features[c].number > 0.9 && features[c].index > 0.8) || (_hint(header(c), BomRole.serial) >= 1 && features[c].number > 0.6)) c,
  };
  used.addAll(indexCols);

  final refsCol = pick((c) => features[c].refs * features[c].fill + features[c].refsMany * 0.4 + _hint(header(c), BomRole.refs) * 0.8);
  // Quantity: numbers, best when they match the designator count.
  double qtyMatch(int c) {
    if (refsCol == null) return 0;
    var hit = 0, n = 0;
    for (final r in data) {
      final q = parseQuantity(g.cell(r, c));
      final refs = splitRefs(g.cell(r, refsCol)).length;
      if (q == null || refs == 0) continue;
      n++;
      if (q == refs) hit++;
    }
    return n == 0 ? 0 : hit / n;
  }

  final qtyCol = pick((c) => features[c].number * features[c].fill + qtyMatch(c) * 0.6 + _hint(header(c), BomRole.quantity) * 0.8, min: 0.4);
  final pnCol = pick((c) => features[c].partNo * features[c].fill * (0.4 + 0.6 * features[c].unique) + _hint(header(c), BomRole.partNo) * 0.8, min: 0.3);
  // Description: one column, or name and specification side by side.
  final descCols = <int>[];
  final first = pick((c) => features[c].text * math.min(features[c].avgLen / 10, 1.0) + _hint(header(c), BomRole.description) * 0.8, min: 0.3);
  if (first != null) {
    descCols.add(first);
    for (var c = 0; c < width; c++) {
      if (used.contains(c)) continue;
      if (_hint(header(c), BomRole.description) >= 0.7 && features[c].fill > 0.3) {
        descCols.add(c);
        used.add(c);
      }
    }
    descCols.sort();
  }

  final columns = <BomColumn>[];
  for (var c = 0; c < width; c++) {
    final h = header(c);
    if (c == pnCol) {
      columns.add(col(c, BomRole.partNo));
    } else if (descCols.contains(c)) {
      columns.add(col(c, BomRole.description));
    } else if (c == qtyCol) {
      columns.add(col(c, BomRole.quantity));
    } else if (c == refsCol) {
      columns.add(col(c, BomRole.refs));
    } else if (indexCols.contains(c)) {
      columns.add(col(c, BomRole.serial));
    } else if (features[c].fill >= 0.05) {
      columns.add(BomColumn(c, h, BomRole.other, label: h.isEmpty ? '#${c + 1}' : _norm(h), evidence: h.isEmpty ? '' : 'header'));
    }
  }
  if (pnCol == null && refsCol == null) throw BomReadException('bom_no_parts');

  // Records: one per part line. A row with designators but nothing else
  // continues the previous record (long designator cells wrapped onto the
  // next row).
  final warnings = <BomWarning>[];
  final records = <BomRecord>[];
  final headerKeys = {for (final col in columns) cleanCell(col.header)};
  for (final r in data) {
    String cell(int? c) => c == null ? '' : cleanCell(g.cell(r, c));
    final pn = cell(pnCol);
    final desc = [for (final c in descCols) cell(c)].where((s) => s.isNotEmpty).join(' ');
    final refs = refsCol == null ? const <String>[] : splitRefs(g.cell(r, refsCol));
    final qty = qtyCol == null ? null : parseQuantity(g.cell(r, qtyCol));
    final source = SourceRef(file, g.name, r + 1);
    // A repeated header row inside the data.
    if (pn.isNotEmpty && headerKeys.contains(pn)) continue;
    if (pn.isEmpty) {
      if (refs.isNotEmpty && desc.isEmpty && qty == null && records.isNotEmpty) {
        records.last.refs.addAll(refs);
        records.last.sources.add(source);
        continue;
      }
      if (refs.isEmpty && desc.isEmpty) continue;
      warnings.add(BomWarning('w_no_part_no', row: r + 1));
    }
    records.add(
      BomRecord(
        id: '$id:${g.name}!${r + 1}',
        sources: [source],
        cells: [for (var c = 0; c < width; c++) g.cell(r, c)],
        partNo: pn,
        description: desc,
        quantity: qty,
        refs: [...refs],
        extra: {
          for (final col in columns)
            if (col.role == BomRole.other) col.label: cell(col.index),
        },
      ),
    );
  }
  if (records.isEmpty) throw BomReadException('bom_no_parts');
  final doc = BomDocument(id: id, file: file, sheet: g.name, sheets: sheets, headerRow: headerRow, columns: columns, records: records, warnings: warnings);

  // Checks inside one file, per part.
  final seen = <String, String>{};
  for (final p in doc.parts) {
    if (p.quantity != null && p.refs.isNotEmpty && p.quantity != p.refs.length) {
      warnings.add(BomWarning('w_qty_refs', row: p.rows.first, detail: '${p.partNo}: ${formatQuantity(p.quantity)} / ${p.refs.length}'));
    }
    for (final ref in p.refs) {
      final other = seen[ref];
      if (other != null) warnings.add(BomWarning('w_dup_ref', row: p.rows.first, detail: '$ref: $other / ${p.partNo}'));
      seen[ref] = p.partNo;
    }
  }
  return doc;
}
