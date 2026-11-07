/// BOM files: finds the header row and works out what each column holds
/// from its contents (part number, description, quantity, designators, other
/// columns), not from the header text alone, then reads the parts.
library;

import 'dart:math' as math;

import 'bom_model.dart';
import 'classify.dart';
import 'knowledge.dart';
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
// Long digit-only codes (T100 / SAP style part numbers such as 460100030):
// numbers by form, but no quantity or row number is this long.
final _digitCode = RegExp(r'^\d{6,20}$');
// Words in any script (names such as 电阻, Resistor, ตัวต้านทาน).
final _wordy = RegExp(r'^[\p{L}\p{M}][\p{L}\p{M}\s\-/&().]*$', unicode: true);
/// Depth written in a level column: `1`, `.2`, `..3`, `1.2.3`.
int? _levelValue(String v) {
  final t = v.trim();
  if (RegExp(r'^\d{1,2}$').hasMatch(t)) return int.parse(t);
  final dots = RegExp(r'^(\.+)(\d{1,2})$').firstMatch(t);
  if (dots != null) return int.parse(dots.group(2)!);
  if (RegExp(r'^\d+(\.\d+)+$').hasMatch(t)) return t.split('.').length;
  return null;
}

/// Integer depths of a multi-level BOM: starting at the shallowest level and
/// going at most one level deeper from one row to the next.
bool _stepsLikeLevels(List<String> values) {
  final v = values.map(_levelValue).toList();
  if (v.any((x) => x == null || x > 9)) return false;
  final min = v.cast<int>().reduce(math.min);
  if (v.first != min) return false;
  for (var i = 1; i < v.length; i++) {
    if (v[i]! > v[i - 1]! + 1) return false;
  }
  return true;
}

/// A value's form: letters → A, digits → 9, other characters kept.
String _shapeOf(String s) => s.toUpperCase().replaceAll(RegExp(r'[A-Z]'), 'A').replaceAll(RegExp(r'\d'), '9');

final _letter = RegExp(r'\p{L}', unicode: true);
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
  BomRole.mpn: ['mpn', 'mfrpn', 'mfrp/n', 'mfgpn', 'mfgp/n', 'manufacturerpartnumber', 'manufacturerpn', 'manufacturerp/n', 'mfrpartnumber', 'mfgpartnumber', 'mfrpart#', 'vendorpartnumber', '厂商料号', '原厂料号', '原厂型号', '制造商料号', '厂家料号', '厂家型号', '厂商型号', '制造商型号', 'herstellerteilenummer', 'herstellernummer'],
  BomRole.maker: ['manufacturer', 'manufacturername', 'mfr', 'mfg', 'maker', 'brand', '厂商', '厂家', '制造商', '品牌', '生产商', 'hersteller', 'fabricant', 'ผู้ผลิต', 'ยี่ห้อ'],
  BomRole.alternate: ['alternate', 'alternative', 'alternates', 'alt', 'altpn', 'substitute', 'secondsource', '2ndsource', '替代', '替代料', '替代料号', '代用料', '备选', '备选料', '关联料号', 'ersatz', 'ersatzteil'],
  BomRole.level: ['level', 'lvl', 'bomlevel', '阶层', '层级', '层次', '阶次', 'ebene', 'stufe'],
  BomRole.dnp: ['dnp', 'dni', 'dnf', 'fitted', 'populate', 'populated', 'mounted', 'notfitted', '贴装', '是否贴装', '是否安装', '是否上件', '是否装配', '装配', '上件', '不贴', '空贴', 'bestückt'],
};

// Header words for "the maker's" and for "number / code".
const _makerWords = ['maker', 'mfr', 'mfg', 'manufacturer', 'oem', 'vendor', '厂商', '厂家', '原厂', '制造商', 'hersteller', 'ผู้ผลิต'];
const _codeWords = ['p/n', 'pn', 'no', 'number', 'code', '#', 'part', '编码', '编号', '料号', '型号', 'nummer', 'รหัส'];

/// Header words that mean "fitted": a no under them marks a part not fitted.
const _fittedHeaders = ['fitted', 'populate', 'populated', 'mounted', '贴装', '是否贴装', '是否安装', '是否上件', '是否装配', '装配', '上件', 'bestückt'];
const _yes = {'y', 'yes', '是', '1', 'x', 'true', '√', 'ja', 'ใช่'};
const _no = {'n', 'no', '否', '0', 'false', '-', 'nein', 'ไม่'};

String _norm(String h) => toHalfWidth(h).toLowerCase().replaceAll(RegExp(r'[\s_]+'), '');

double _hint(String header, BomRole role) {
  final h = _norm(header);
  if (h.isEmpty) return 0;
  final words = _hints[role];
  if (words == null) return 0;
  for (final w in words) {
    if (h == w) return 1.0;
  }
  for (final w in words) {
    if (w.length < 2) continue;
    // Latin words of the column attributes only at the start or end
    // ("amount" is not "mounted"); other scripts anywhere.
    final latin = w.codeUnits.every((u) => u < 0x250);
    if (role.attribute && latin ? (h.startsWith(w) || h.endsWith(w)) : h.contains(w)) return 0.7;
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
  // Further sheets with the same columns (a BOM split over several sheets,
  // e.g. top and bottom side) are read into the same document.
  final layout = _layoutKey(best);
  final more = <BomDocument>[];
  for (final g in sheets) {
    if (g.name == best.sheet) continue;
    try {
      final f = _readSheet(g, file: file, id: id, sheets: names);
      if (_layoutKey(f) == layout && layout.isNotEmpty) more.add(f);
    } on BomReadException {
      continue;
    }
  }
  if (more.isEmpty) return best;
  final records = [...best.records, for (final f in more) ...f.records];
  final warnings = [
    for (final f in [best, ...more]) ...f.warnings.where((w) => w.code == 'w_no_part_no'),
  ];
  final doc = BomDocument(id: id, file: file, sheet: best.sheet, sheets: names, headerRow: best.headerRow, columns: best.columns, records: records, warnings: warnings);
  _partWarnings(doc);
  return doc;
}

/// Columns by role and header; equal for sheets of one BOM.
String _layoutKey(BomDocument d) =>
    d.headerRow < 0 ? '' : [for (final c in d.columns) '${c.index}:${c.role.name}:${cleanCell(c.header).toLowerCase()}'].join('|');

/// Whether the row under the header row is the second row of a two-row
/// header.
bool _secondHeaderRow(Grid g, int headerRow, int width) {
  var mergedDown = 0, groupAbove = false;
  for (var c = 0; c < width; c++) {
    final m = g.mergeAt(headerRow, c);
    if (m == null) continue;
    if (m.$1 == headerRow && m.$3 > headerRow) mergedDown++;
    if (m.$1 == headerRow && m.$4 > m.$2 && cleanCell(g.cell(headerRow + 1, c)).isNotEmpty) groupAbove = true;
  }
  if (mergedDown == 0 && !groupAbove) return false;
  // The next row holds only words, no part data.
  final next = [for (var c = 0; c < width; c++) cleanCell(g.cell(headerRow + 1, c))].where((v) => v.isNotEmpty).toList();
  return next.isNotEmpty && next.every((v) => !_numberCell.hasMatch(v) && !splitRefs(v).every(_designator.hasMatch));
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
  double fill = 0, refs = 0, refsMany = 0, number = 0, index = 0, partNo = 0, unique = 0, text = 0, avgLen = 0, code = 0, wordy = 0, letters = 0, shape = 0;

  /// Most common value shape (letters → A, digits → 9).
  String topShape = '';
}

_Features _features(List<String> values, int rows) {
  final f = _Features();
  final v = values.where((s) => s.isNotEmpty).toList();
  if (v.isEmpty || rows == 0) return f;
  f.fill = v.length / rows;
  var refs = 0, many = 0, num = 0, pn = 0, text = 0, len = 0, code = 0, wordy = 0, letters = 0;
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
    if (_digitCode.hasMatch(s)) {
      code++;
      pn++;
    } else if (_partNoLike.hasMatch(s) && RegExp(r'\d').hasMatch(s) && !_numberCell.hasMatch(s) && !_designator.hasMatch(s.toUpperCase())) {
      pn++;
    }
    if (_cjk.hasMatch(s) || _param.hasMatch(s) || s.contains(' ')) text++;
    if (_wordy.hasMatch(s) && s.length >= 2) wordy++;
    if (_letter.hasMatch(s)) letters++;
  }
  f.refs = refs / v.length;
  f.refsMany = many / v.length;
  f.number = num / v.length;
  f.index = v.length > 2 ? consecutive / (v.length - 1) : 0;
  f.partNo = pn / v.length;
  f.unique = v.toSet().length / v.length;
  f.text = text / v.length;
  f.avgLen = len / v.length;
  f.code = code / v.length;
  f.wordy = wordy / v.length;
  f.letters = letters / v.length;
  final shapes = <String, int>{};
  for (final s in v) {
    final k = _shapeOf(s);
    shapes[k] = (shapes[k] ?? 0) + 1;
  }
  final top = shapes.entries.reduce((a, b) => a.value >= b.value ? a : b);
  f.shape = top.value / v.length;
  f.topShape = top.key;
  return f;
}

BomDocument _readSheet(Grid g, {required String file, required String id, required List<String> sheets}) {
  final headerRow = _headerRow(g);
  final width = g.rows.fold<int>(0, (m, r) => math.max(m, r.length));
  if (width == 0) throw BomReadException('bom_empty');
  // A two-row header: a header cell merged down into the next row, or a
  // group title merged across columns above the sub-titles.
  final twoRow = headerRow >= 0 && headerRow + 1 < g.rows.length && _secondHeaderRow(g, headerRow, width);
  final lastHeader = twoRow ? headerRow + 1 : headerRow;
  final data = [
    for (var r = lastHeader + 1; r < g.rows.length; r++)
      if (g.rows[r].any((c) => c.trim().isNotEmpty)) r,
  ];
  if (data.isEmpty) throw BomReadException('bom_no_parts');
  final headers = [
    for (var c = 0; c < width; c++)
      headerRow < 0
          ? ''
          : {for (var r = headerRow; r <= lastHeader; r++) cleanCell(g.shown(r, c))}.where((h) => h.isNotEmpty).join(' '),
  ];
  String header(int c) => headers[c];
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

  // A column of component makers (named in general industry knowledge).
  bool isMaker(int c) {
    final v = [for (final r in data) cleanCell(g.cell(r, c)).toLowerCase()].where((x) => x.isNotEmpty).toList();
    return v.isNotEmpty && v.where(makers.contains).length / v.length >= 0.5;
  }

  // A column that says what the items are: most values name an item kind
  // or carry parameters (a remark such as "RoHS" does neither).
  bool describes(int c) {
    final v = [for (final r in data) cleanCell(g.cell(r, c))].where((x) => x.isNotEmpty).toList();
    if (v.isEmpty) return false;
    final hits = v.where((x) => _param.hasMatch(x) || classifyItem(x, const []).$1 != ItemKind.unknown).length;
    return hits / v.length >= 0.5;
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
      BomRole.maker => isMaker(c),
      BomRole.mpn || BomRole.alternate => f.partNo > 0.4,
      BomRole.level || BomRole.dnp => true,
      BomRole.other => false,
    };
    return [if (byHeader) 'header', if (byContent) 'content'].join('+');
  }

  BomColumn col(int c, BomRole role, {String label = ''}) =>
      BomColumn(c, header(c), role, label: label, confidence: (scores[c] ?? 1).clamp(0.0, 1.0).toDouble(), evidence: evidence(c, role));

  // Columns whose header names an attribute (MPN, maker, alternate, level,
  // DNP) more strongly than a main field are taken first: "MPN" is not the
  // part number, "Manufacturer Part Number" is not either.
  final attrs = <int, BomRole>{};
  const attributeRoles = [BomRole.mpn, BomRole.maker, BomRole.alternate, BomRole.level, BomRole.dnp];
  const mainRoles = [BomRole.partNo, BomRole.description, BomRole.quantity, BomRole.refs, BomRole.serial];
  for (var c = 0; c < width; c++) {
    var best = 0.0;
    BomRole? role;
    for (final r in attributeRoles) {
      final h = _hint(header(c), r);
      if (h > best) {
        best = h;
        role = r;
      }
    }
    // A part number qualified by the maker ("Maker P/N", "OEM No.",
    // "原厂编码") is the maker part number.
    final h = _norm(header(c));
    if (_makerWords.any((w) => h.contains(w)) && _codeWords.any((w) => h.contains(w)) && _hint(header(c), BomRole.maker) < 1) {
      best = 1;
      role = BomRole.mpn;
    }
    if (role == null || best < 0.7) continue;
    final main = mainRoles.map((r) => _hint(header(c), r)).reduce(math.max);
    if (best >= main && features[c].fill >= 0.02) {
      attrs[c] = role;
      used.add(c);
    }
  }

  // Sequential numbers (序号) are not compared.
  final indexCols = <int>{
    for (var c = 0; c < width; c++)
      if (features[c].code < 0.5 && ((features[c].number > 0.9 && features[c].index > 0.8) || (_hint(header(c), BomRole.serial) >= 1 && features[c].number > 0.6))) c,
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

  final qtyCol = pick((c) => features[c].number * features[c].fill * (1 - features[c].code) + qtyMatch(c) * 0.6 + _hint(header(c), BomRole.quantity) * 0.8, min: 0.4);
  // Part number: unique codes; an internal numbering keeps one form (a
  // maker part number column varies), which settles headerless sheets.
  // Every part line has one, so a sparse column (alternates) never is.
  final pnCol = pick((c) => (features[c].partNo * (0.4 + 0.6 * features[c].unique) + features[c].partNo * features[c].shape * 0.3 + _hint(header(c), BomRole.partNo) * 0.8) * features[c].fill * features[c].fill, min: 0.3);
  // Description: one column, or name and specification side by side.
  final descCols = <int>[];
  // Codes are not descriptions, even when "…823A" reads like a current.
  final first = pick((c) => features[c].text * math.min(features[c].avgLen / 10, 1.0) * (1 - features[c].partNo) + _hint(header(c), BomRole.description) * 0.8, min: 0.3);
  if (first != null) {
    descCols.add(first);
    for (var c = 0; c < width; c++) {
      if (used.contains(c)) continue;
      final f = features[c];
      // By header, or by content: a well-filled column of names or
      // parameters that is neither a code nor a number.
      final byContent = f.fill >= 0.7 && f.letters >= 0.6 && (f.text >= 0.5 || f.wordy >= 0.7) && f.partNo < 0.3 && f.number < 0.2 && f.refs < 0.2 && !isMaker(c) && describes(c);
      if ((_hint(header(c), BomRole.description) >= 0.7 && f.fill > 0.3) || byContent) {
        descCols.add(c);
        used.add(c);
      }
    }
    descCols.sort();
  }

  // Remaining columns recognised by content.
  final pnShape = pnCol == null ? '' : features[pnCol].topShape;
  for (var c = 0; c < width; c++) {
    if (used.contains(c) || attrs.containsKey(c)) continue;
    final f = features[c];
    if (f.fill < 0.02) continue;
    final values = [for (final r in data) cleanCell(g.cell(r, c))].where((v) => v.isNotEmpty).toList();
    if (isMaker(c)) {
      attrs[c] = BomRole.maker;
    } else if (values.isNotEmpty && values.every((v) => _levelValue(v) != null) && values.map(_levelValue).toSet().length >= 2 && (values.any((v) => v.startsWith('.') || v.contains('.')) || _stepsLikeLevels(values))) {
      attrs[c] = BomRole.level;
    } else if (header(c).isEmpty && f.fill >= 0.5 && values.every((v) => _yes.contains(v.toLowerCase()) || _no.contains(v.toLowerCase())) && values.toSet().length <= 6) {
      // A yes/no column without a header: a fitted flag, read by majority
      // (most lines of a BOM are fitted). Kept at low confidence.
      attrs[c] = BomRole.dnp;
      scores[c] = 0.5;
    } else if (values.isNotEmpty && values.where(isDnpText).length >= math.max(1, values.length * 0.3) && values.toSet().length <= 6) {
      attrs[c] = BomRole.dnp;
    } else if (f.partNo >= 0.6) {
      // More part codes: the same form as the part numbers means other
      // parts of this company (alternates); another form, maker numbers.
      final sameForm = pnShape.isNotEmpty && values.where((v) => v.split(RegExp(r'[,;/、\s]+')).any((x) => _shapeOf(x) == pnShape)).length >= values.length * 0.6;
      if (sameForm) {
        attrs[c] = BomRole.alternate;
      } else if (f.fill >= 0.5 && f.letters >= 0.5) {
        attrs[c] = BomRole.mpn;
      }
    }
  }

  final columns = <BomColumn>[];
  for (var c = 0; c < width; c++) {
    final h = header(c);
    if (attrs.containsKey(c)) {
      columns.add(col(c, attrs[c]!, label: attrs[c]!.name));
    } else if (c == pnCol) {
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
  int? attrCol(BomRole role) => attrs.entries.where((e) => e.value == role).map((e) => e.key).firstOrNull;
  final dnpCol = attrCol(BomRole.dnp), levelCol = attrCol(BomRole.level), altCol = attrCol(BomRole.alternate);
  // Under a "fitted" header a no means not fitted; under "DNP" a yes does.
  // Without a telling header, the majority answer is "fitted".
  bool fittedPolarity() {
    if (dnpCol == null) return false;
    final h = _norm(header(dnpCol));
    if (_fittedHeaders.any((w) => h.contains(w))) return true;
    if (_hint(header(dnpCol), BomRole.dnp) > 0) return false;
    final v = [for (final r in data) cleanCell(g.cell(r, dnpCol)).toLowerCase()].where((x) => x.isNotEmpty);
    return v.where(_yes.contains).length >= v.where(_no.contains).length;
  }

  final fittedHeader = fittedPolarity();
  bool dnpValue(String v) {
    final t = v.toLowerCase().trim();
    if (t.isEmpty) return false;
    if (isDnpText(t)) return true;
    return fittedHeader ? _no.contains(t) : (dnpCol != null && _yes.contains(t));
  }

  // Open assemblies of a multi-level BOM, by level.
  final parents = <int, String>{};
  for (final r in data) {
    // A cell merged down from the row above shows that row's value;
    // quantities and designators are only read where written, so they
    // are never counted twice.
    String cell(int? c) {
      if (c == null) return '';
      final own = cleanCell(g.cell(r, c));
      if (own.isNotEmpty) return own;
      final m = g.mergeAt(r, c);
      return m != null && m.$1 < r && m.$2 == m.$4 ? cleanCell(g.cell(m.$1, m.$2)) : '';
    }

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
    final rid = '$id:${g.name}!${r + 1}';
    final level = levelCol == null ? null : _levelValue(cell(levelCol));
    String? parent;
    if (level != null) {
      parent = [for (var l = level - 1; l >= 0; l--) parents[l]].nonNulls.firstOrNull;
      parents[level] = rid;
      parents.removeWhere((l, _) => l > level);
    }
    final (kind, kindEvidence) = classifyItem(desc, refs);
    records.add(
      BomRecord(
        id: rid,
        sources: [source],
        cells: [for (var c = 0; c < width; c++) g.cell(r, c)],
        partNo: pn,
        description: desc,
        quantity: qty,
        refs: [...refs],
        extra: {
          for (final col in columns)
            if (col.role.attribute) col.label: cell(col.index),
        },
        dnp: (dnpCol != null && dnpValue(cell(dnpCol))) || isDnpText(desc) && _dnpInDescription(desc),
        level: level,
        parentId: parent,
        // A related-part column often repeats the line's own number.
        alternates: altCol == null ? const [] : [for (final a in cell(altCol).split(RegExp(r'[,;/、\s]+'))) if (a.isNotEmpty && a != pn) a],
        kind: kind,
        kindEvidence: kindEvidence,
      ),
    );
  }
  if (records.isEmpty) throw BomReadException('bom_no_parts');
  final doc = BomDocument(id: id, file: file, sheet: g.name, sheets: sheets, headerRow: headerRow, columns: columns, records: records, warnings: warnings);

  _partWarnings(doc);
  return doc;
}

/// Checks inside one file, per part: quantity against designator count,
/// designators used twice.
void _partWarnings(BomDocument doc) {
  final warnings = doc.warnings;
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
}

/// A description marks its line not fitted only with a standalone marker
/// ("DNP", "NC", "不贴"), not inside a part name.
bool _dnpInDescription(String desc) =>
    desc.split(RegExp(r'[\s,，;；()（）\[\]]+')).any((w) => w.isNotEmpty && isDnpText(w) && w.length <= 12);
