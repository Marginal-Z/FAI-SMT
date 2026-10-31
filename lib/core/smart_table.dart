/// Content-based table recognition.
///
/// Finds the header row and the role of every column from what the cells
/// contain — designator lists, part-number codes, quantities that equal the
/// number of designators, component descriptions, feeder slots — instead of
/// a fixed list of header names. Header words only break ties between
/// columns whose contents look alike, and every role can be overridden by
/// the user.
library;

import 'dart:math' as math;

import 'columns.dart';
import 'refdes.dart';
import 'table_reader.dart';

enum TableKind { bom, station }

/// What a column holds.
enum ColumnRole { partNo, refs, qty, desc, slot, alt, related, side, other }

/// Content statistics of one column over the data rows.
class ColumnProfile {
  ColumnProfile(this.index);

  final int index;
  int rows = 0;
  int filled = 0;
  int distinct = 0;
  double num = 0;
  double ref = 0;
  double code = 0;
  double codeList = 0;
  double text = 0;
  double elec = 0;
  double slot = 0;
  double side = 0;

  /// Share of plain words: letters, not a number, code or designator.
  double word = 0;

  /// Share of designator tokens with a usual prefix (R, C, U, LED …).
  double refVocab = 0;
  int refPrefixes = 0;
  double avgTokens = 0;
  double avgLen = 0;

  /// Share of values with the most common separator skeleton (`x-x-x`).
  double skeleton = 0;

  /// Numeric values that keep increasing row after row (项次 / No.).
  double sequence = 0;

  double get fill => rows == 0 ? 0 : filled / rows;
  double get uniq => filled == 0 ? 0 : distinct / filled;
}

/// One column of a recognised table.
class ColumnInfo {
  ColumnInfo({required this.index, required this.header, required this.role, required this.confidence, required this.samples, required this.profile, this.manual = false});

  final int index;
  final String header;
  final ColumnRole role;

  /// 0–1: how clearly the contents match the role.
  final double confidence;
  final List<String> samples;
  final ColumnProfile profile;

  /// Set by the user rather than recognised.
  final bool manual;

  /// Spreadsheet column letter (A, B, … AA).
  String get letter {
    var n = index + 1;
    var s = '';
    while (n > 0) {
      final r = (n - 1) % 26;
      s = String.fromCharCode(65 + r) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  ColumnInfo withRole(ColumnRole r, {bool manual = true}) =>
      ColumnInfo(index: index, header: header, role: r, confidence: manual ? 1 : confidence, samples: samples, profile: profile, manual: manual);
}

/// Where the table is and what each column holds.
class TableLayout {
  TableLayout({required this.kind, required this.sheet, required this.headerRow, required this.columns, required this.score});

  final TableKind kind;
  final Grid sheet;

  /// Header row inside [sheet], or -1 when the table has none.
  final int headerRow;
  final List<ColumnInfo> columns;
  final double score;

  int? col(ColumnRole r) {
    for (final c in columns) {
      if (c.role == r) return c.index;
    }
    return null;
  }

  List<int> cols(ColumnRole r) => [for (final c in columns) if (c.role == r) c.index];

  ColumnInfo? info(ColumnRole r) {
    for (final c in columns) {
      if (c.role == r) return c;
    }
    return null;
  }

  bool get usable => col(ColumnRole.partNo) != null && col(ColumnRole.refs) != null;

  /// Header text of a column, or `#n` without a header row.
  String headerOf(int col) {
    final h = headerRow >= 0 ? sheet.cell(headerRow, col).trim() : '';
    return h.isEmpty ? '#${col + 1}' : h.replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Columns with no recognised role, by header text.
  Map<int, String> get otherColumns => {for (final c in columns) if (c.role == ColumnRole.other) c.index: headerOf(c.index)};

  /// Mapping in the field names the parsers use.
  ColumnMap toColumnMap() {
    final m = <String, int>{};
    void put(String key, int? c) {
      if (c != null) m[key] = c;
    }

    final desc = cols(ColumnRole.desc);
    put('partNo', col(ColumnRole.partNo));
    put('refs', col(ColumnRole.refs));
    put('qty', col(ColumnRole.qty));
    if (kind == TableKind.bom) {
      if (desc.isNotEmpty) m['name'] = desc[0];
      if (desc.length > 1) m['spec'] = desc[1];
      put('alt', col(ColumnRole.alt));
    } else {
      if (desc.isNotEmpty) m['desc'] = desc[0];
      if (desc.length > 1) m['desc2'] = desc[1];
      put('slot', col(ColumnRole.slot));
      put('related', col(ColumnRole.related));
      put('side', col(ColumnRole.side));
    }
    return ColumnMap(headerRow, m, sheet);
  }

  /// The same table with column [index] set to [role] by the user. A role
  /// that can only be held once moves away from the column that had it.
  TableLayout withRole(int index, ColumnRole role, {bool manual = true}) {
    final single = role != ColumnRole.desc && role != ColumnRole.other;
    return TableLayout(
      kind: kind,
      sheet: sheet,
      headerRow: headerRow,
      score: score,
      columns: [
        for (final c in columns)
          if (c.index == index)
            c.withRole(role, manual: manual)
          else if (single && c.role == role)
            c.withRole(ColumnRole.other, manual: manual)
          else
            c,
      ],
    );
  }
}

// ---------------------------------------------------------------- cells

final _number = RegExp(r'^[-+]?(\d{1,3}(,\d{3})+|\d+)(\.\d+)?$');
final _refToken = RegExp(r'^\d{0,3}([A-Z]{1,6})\d{1,5}[A-Z]?$');
final _codeToken = RegExp(r'^[A-Z0-9][A-Z0-9\-_.\/#+]{3,39}$');
final _digit = RegExp(r'\d');
final _letter = RegExp(r'[A-Z]');
final _cjk = RegExp(r'[一-鿿฀-๿]');
final _slotToken = RegExp(r'^[A-Z0-9]{1,6}([\-_.:/ ]+[A-Z0-9]{1,6}){0,4}$');
final _listSplit = RegExp(r'[,，;；、\s]+');
final _elec = RegExp(
  r'(\d+(\.\d+)?\s*(P|N|U|µ|M|K)?(F|H|Ω|OHM|R|V|A|W|HZ|PPM|MAH)\b)|(\d+(\.\d+)?\s*%)|±|'
  r'\b(0201|0402|0603|0805|1206|1210|2512|SOT|SOD|SOP|SSOP|TSSOP|QFN|DFN|QFP|LQFP|BGA|FBGA|LGA|TO-?\d+|SMD|X5R|X7R|NPO|C0G)|'
  r'(电阻|电容|电感|二极管|三极管|晶振|晶体|芯片|贴片|连接器|插座|座子|磁珠|保险|开关|变压器|模组|排针|IC)|'
  r'\b(RES|RESISTOR|CAP|CAPACITOR|IND|INDUCTOR|DIODE|TRANSISTOR|MOSFET|CRYSTAL|OSCILLATOR|CONNECTOR|HEADER|FUSE|LED|FERRITE|BEAD|SWITCH|RELAY|TVS|ESD|LDO|MCU|DRAM|FLASH|EMMC)S?\b',
);

/// Usual designator prefixes; others still count, just less.
const _refPrefixes = {
  'R', 'C', 'L', 'U', 'D', 'Q', 'J', 'Y', 'X', 'F', 'FB', 'LED', 'TP', 'SW', 'K', 'T', 'P', 'CN', 'CON', 'BT', 'RN', 'RP', 'RA', 'CR', 'ZD', //
  'VR', 'IC', 'MK', 'ANT', 'LD', 'RV', 'TR', 'M', 'S', 'B', 'E', 'EC', 'CE', 'H', 'JP', 'PS', 'Z', 'ZR', 'SP', 'BZ', 'FL', 'MH', 'MP', 'PT',
  'RT', 'RL', 'TH', 'VD', 'VT', 'NTC', 'PTC', 'DS', 'G', 'CY', 'CX', 'CA', 'LS', 'XT', 'OSC', 'USB', 'HDMI', 'DZ', 'TVS', 'PD', 'W', 'IR',
};

const _sideWords = {
  'T', 'B', 'TOP', 'BOT', 'BOTTOM', 'A', 'A面', 'B面', 'TOPLAYER', 'BOTTOMLAYER', '顶层', '底层', '正面', '反面', '背面', 'TOP SIDE', 'BOTTOM SIDE', 'FRONT', 'BACK', 'C面', 'S面',
};

/// Header words that break ties between columns whose contents look alike.
/// They never decide a role on their own.
const _hints = {
  ColumnRole.partNo: ['料号', '料件', '编号', '编码', 'PART', 'P/N', 'PN', 'ITEM', 'MATERIAL', 'CODE'],
  ColumnRole.refs: ['位号', '位置', '点位', 'DESIGNATOR', 'REF', 'LOCATION', 'POSITION'],
  ColumnRole.qty: ['数量', '用量', '点数', 'QTY', 'QUANTITY', 'COUNT', 'USAGE'],
  ColumnRole.desc: ['品名', '规格', '描述', '名称', 'DESC', 'SPEC', 'NAME', 'COMMENT', 'VALUE'],
  ColumnRole.slot: ['站位', '料站', '站', '料架', 'FEEDER', 'SLOT', 'STATION', 'TABLE'],
  ColumnRole.alt: ['替代', '取代', '代用', 'ALT', 'SUBST', 'SECOND'],
  ColumnRole.related: ['关联', '主料', 'BOM料号', 'RELATED', 'MAIN'],
  ColumnRole.side: ['面别', '面', 'SIDE', 'LAYER', 'T/B'],
};

/// Per-cell features, computed once per sheet.
class _Cell {
  _Cell(String raw) : value = raw.trim() {
    final v = value.toUpperCase();
    if (v.isEmpty) return;
    empty = false;
    num = _number.hasMatch(v);
    if (num) numValue = double.tryParse(v.replaceAll(',', ''));
    final tokens = splitRefs(v);
    refCount = tokens.length;
    var ok = 0, vocab = 0;
    for (final t in tokens) {
      final m = _refToken.firstMatch(t);
      if (m == null) continue;
      ok++;
      final p = m.group(1)!;
      prefixes.add(p);
      if (_refPrefixes.contains(p)) vocab++;
    }
    ref = tokens.isNotEmpty && ok == tokens.length;
    refVocab = tokens.isEmpty ? 0 : vocab / tokens.length;
    code = _isCode(v);
    if (!code) {
      final parts = v.split(_listSplit).where((e) => e.isNotEmpty).toList();
      codeList = parts.length > 1 && parts.every(_isCode);
    }
    text = _cjk.hasMatch(v) || (v.contains(' ') && _letter.hasMatch(v));
    elec = _elec.hasMatch(v);
    slot = v.length <= 18 && _digit.hasMatch(v) && !elec && _slotToken.hasMatch(v);
    word = (_letter.hasMatch(v) || _cjk.hasMatch(v)) && !num && !code && !ref;
    side = _sideWords.contains(v);
    skeleton = v.replaceAll(RegExp(r'[A-Z0-9]+'), 'x');
  }

  final String value;
  bool empty = true;
  bool num = false;
  double? numValue;
  bool ref = false;
  double refVocab = 0;
  int refCount = 0;
  final Set<String> prefixes = {};
  bool code = false;
  bool codeList = false;
  bool text = false;
  bool elec = false;
  bool slot = false;
  bool side = false;
  bool word = false;
  String skeleton = '';
}

bool _isCode(String v) {
  if (!_codeToken.hasMatch(v)) return false;
  // Without digits only hyphenated codes count (P-DDR), not words (DDR).
  if (!_digit.hasMatch(v)) return RegExp(r'^[A-Z]+[\-_.][A-Z0-9\-_.]+$').hasMatch(v);
  // Plain numbers are codes only when long and whole (ERP numbers).
  if (_number.hasMatch(v)) return v.length >= 6 && !v.contains('.') && !v.contains(',');
  // Short digit groups (1-01, 2/3) are slots or dates, not part numbers.
  if (!_letter.hasMatch(v)) return v.length >= 7;
  return true;
}

class _Sheet {
  _Sheet(this.grid, int limit) {
    final n = math.min(grid.rows.length, limit);
    cells = [for (var r = 0; r < n; r++) [for (final v in grid.rows[r]) _Cell(v)]];
    width = cells.fold(0, (w, r) => math.max(w, r.length));
  }

  final Grid grid;
  late final List<List<_Cell>> cells;
  late final int width;

  _Cell at(int r, int c) => c < cells[r].length ? cells[r][c] : _blank;
}

final _blank = _Cell('');

double _clamp(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

String _normHeader(String s) => s.toUpperCase().replaceAll(RegExp(r'[\s_\-.:：（）()]'), '');

bool _hinted(String header, ColumnRole role) {
  final h = _normHeader(header);
  if (h.isEmpty) return false;
  return (_hints[role] ?? const []).any((w) => h.contains(_normHeader(w)));
}

// ------------------------------------------------------------- profiling

ColumnProfile _profile(_Sheet s, int col, int from, int to) {
  final p = ColumnProfile(col);
  final values = <String>{};
  final skeletons = <String, int>{};
  final prefixes = <String>{};
  var num = 0, ref = 0, code = 0, codeList = 0, text = 0, elec = 0, slot = 0, side = 0, word = 0;
  var vocab = 0.0, tokens = 0, len = 0, seqUp = 0, seqPairs = 0;
  double? lastNum;
  for (var r = from; r < to; r++) {
    if (s.cells[r].every((c) => c.empty)) continue;
    p.rows++;
    final c = s.at(r, col);
    if (c.empty) continue;
    p.filled++;
    values.add(c.value.toUpperCase());
    len += c.value.length;
    if (c.num) {
      num++;
      if (lastNum != null) {
        seqPairs++;
        if (c.numValue! > lastNum) seqUp++;
      }
      lastNum = c.numValue;
    }
    if (c.ref) {
      ref++;
      tokens += c.refCount;
      vocab += c.refVocab;
      prefixes.addAll(c.prefixes);
    }
    if (c.code) code++;
    if (c.codeList) codeList++;
    if (c.text) text++;
    if (c.elec) elec++;
    if (c.slot) slot++;
    if (c.side) side++;
    if (c.word) word++;
    skeletons[c.skeleton] = (skeletons[c.skeleton] ?? 0) + 1;
  }
  final f = p.filled;
  if (f == 0) return p;
  p.distinct = values.length;
  p.num = num / f;
  p.ref = ref / f;
  p.code = code / f;
  p.codeList = codeList / f;
  p.text = text / f;
  p.elec = elec / f;
  p.slot = slot / f;
  p.side = side / f;
  p.word = word / f;
  p.refVocab = ref == 0 ? 0 : vocab / ref;
  p.refPrefixes = prefixes.length;
  p.avgTokens = ref == 0 ? 0 : tokens / ref;
  p.avgLen = len / f;
  p.skeleton = skeletons.values.fold(0, math.max) / f;
  p.sequence = seqPairs == 0 ? 0 : seqUp / seqPairs;
  return p;
}

double _refsScore(ColumnProfile p) {
  if (p.ref < 0.5 || p.filled == 0) return 0;
  final multi = _clamp((p.avgTokens - 1) / 2);
  final diverse = _clamp((p.refPrefixes - 1) / 3);
  return p.ref * (0.45 + 0.25 * p.refVocab + 0.15 * multi + 0.15 * diverse) * (0.4 + 0.6 * math.sqrt(p.fill));
}

double _partNoScore(ColumnProfile p) {
  if (p.code < 0.5 || p.filled == 0) return 0;
  final uniq = _clamp((p.uniq - 0.15) / 0.5);
  // Designator-looking codes (AO3400 vs R12) are part numbers only when the
  // column is not clearly a designator list.
  final refPenalty = p.ref > 0.8 && p.refVocab > 0.6 ? 0.5 : 1.0;
  return p.code * uniq * (0.75 + 0.25 * p.skeleton) * math.sqrt(p.fill) * refPenalty * (1 - 0.5 * p.text);
}

double _descScore(ColumnProfile p) {
  if (p.filled == 0 || p.num > 0.8) return 0;
  final s = 0.3 * p.text + 0.4 * p.elec + 0.15 * _clamp(p.avgLen / 14) + 0.25 * p.word;
  final notCode = p.code > 0.85 && p.elec < 0.3 ? 0.3 : 1.0;
  final notRef = p.ref > 0.7 ? 0.2 : 1.0;
  return s * notCode * notRef * math.sqrt(p.fill);
}

double _slotScore(ColumnProfile p) {
  if (p.filled == 0 || p.slot < 0.6 || p.avgLen > 14) return 0;
  return p.slot * (0.4 + 0.6 * _clamp(p.uniq / 0.6)) * math.sqrt(p.fill) * (p.ref > 0.8 && p.avgTokens > 1.2 ? 0.3 : 1);
}

/// Share of rows where a numeric column equals the designator count.
double _qtyMatch(_Sheet s, int col, int refCol, int from, int to) {
  var rows = 0, hit = 0;
  for (var r = from; r < to; r++) {
    final q = s.at(r, col), refs = s.at(r, refCol);
    if (q.empty || refs.empty || q.numValue == null) continue;
    rows++;
    if ((q.numValue! - refs.refCount).abs() < 1e-6) hit++;
  }
  return rows == 0 ? 0 : hit / rows;
}

/// Share of rows where two columns hold the same value.
double _sameValues(_Sheet s, int a, int b, int from, int to) {
  var rows = 0, same = 0;
  for (var r = from; r < to; r++) {
    final x = s.at(r, a), y = s.at(r, b);
    if (x.empty || y.empty) continue;
    rows++;
    if (x.value.toUpperCase() == y.value.toUpperCase()) same++;
  }
  return rows == 0 ? 0 : same / rows;
}

class _Pick {
  _Pick(this.role, this.score);

  final ColumnRole role;
  final double score;
}

/// Assigns roles for a table whose data starts at [from].
(Map<int, _Pick>, double) _assign(_Sheet s, TableKind kind, int header, int from, int to) {
  final profiles = [for (var c = 0; c < s.width; c++) _profile(s, c, from, to)];
  String head(int c) => header >= 0 ? s.at(header, c).value : '';
  double hint(int c, ColumnRole r) => _hinted(head(c), r) ? 0.12 : 0;
  final out = <int, _Pick>{};
  bool free(int c) => !out.containsKey(c);

  int? best(ColumnRole role, double Function(int c) score, {double min = 0.15}) {
    int? bestCol;
    var bestScore = min;
    for (var c = 0; c < s.width; c++) {
      if (!free(c)) continue;
      final v = score(c);
      if (v <= 0) continue;
      final total = v + hint(c, role);
      if (total > bestScore) {
        bestScore = total;
        bestCol = c;
      }
    }
    if (bestCol != null) out[bestCol] = _Pick(role, _clamp(bestScore));
    return bestCol;
  }

  final refs = best(ColumnRole.refs, (c) => _refsScore(profiles[c]), min: 0.25);
  final pn = best(ColumnRole.partNo, (c) => _partNoScore(profiles[c]), min: 0.2);
  final qty = best(ColumnRole.qty, (c) {
    final p = profiles[c];
    if (p.num < 0.7 || p.filled == 0) return 0;
    if (refs != null) {
      final m = _qtyMatch(s, c, refs, from, to);
      if (m > 0.2) return 0.4 + 0.6 * m;
    }
    // No designator agreement: small, non-sequential numbers.
    return 0.35 * p.num * (1 - p.sequence) * math.sqrt(p.fill);
  }, min: 0.12);

  if (kind == TableKind.bom && pn != null) {
    best(ColumnRole.alt, (c) {
      final p = profiles[c];
      final codes = p.code + p.codeList;
      if (codes < 0.7 || p.fill > 0.9) return 0;
      if (_sameValues(s, c, pn, from, to) > 0.3) return 0;
      return 0.3 + 0.4 * codes * (1 - p.fill);
    }, min: 0.3);
  }
  if (kind == TableKind.station) {
    if (pn != null) {
      best(ColumnRole.related, (c) {
        final p = profiles[c];
        if (p.code < 0.6) return 0;
        final same = _sameValues(s, c, pn, from, to);
        return same >= 0.3 ? 0.3 + 0.5 * same : 0;
      }, min: 0.35);
    }
    best(ColumnRole.side, (c) {
      final p = profiles[c];
      return p.side >= 0.85 && p.distinct <= 4 && p.fill >= 0.5 ? p.side * 0.8 : 0;
    }, min: 0.4);
    best(ColumnRole.slot, (c) => _slotScore(profiles[c]), min: 0.25);
  }
  // Up to two description columns (name and specification).
  final d1 = best(ColumnRole.desc, (c) => _descScore(profiles[c]), min: 0.12);
  if (d1 != null) {
    final first = out[d1]!.score;
    best(ColumnRole.desc, (c) {
      final v = _descScore(profiles[c]);
      return v >= first * 0.45 ? v : 0;
    }, min: 0.12);
  }

  double sc(int? c) => c == null ? 0 : out[c]!.score;
  var total = 1.4 * sc(refs) + 1.4 * sc(pn) + 0.5 * sc(qty);
  for (final e in out.entries) {
    if (e.value.role == ColumnRole.desc) total += 0.25 * e.value.score;
    if (e.value.role == ColumnRole.slot) total += 0.3 * e.value.score;
  }
  // A table with both key columns beats any table missing one.
  if (refs != null && pn != null) total += 1;
  return (out, total);
}

/// A header row is text that does not look like the data under it.
double _headerness(_Sheet s, int header, Map<int, _Pick> roles) {
  if (header < 0) return 0;
  final row = s.cells[header];
  final filled = row.where((c) => !c.empty).length;
  if (filled < 2) return -1;
  var label = 0, checked = 0;
  for (final e in roles.entries) {
    final c = s.at(header, e.key);
    checked++;
    if (c.empty) continue;
    final dataLike = switch (e.value.role) {
      ColumnRole.refs => c.ref,
      ColumnRole.partNo || ColumnRole.alt || ColumnRole.related => c.code,
      ColumnRole.qty => c.num,
      ColumnRole.slot => c.slot,
      ColumnRole.side => c.side,
      _ => c.elec,
    };
    if (!dataLike) label++;
  }
  return checked == 0 ? 0 : label / checked;
}

/// Recognises the table in [sheets]. Returns null when no sheet holds a
/// part-number column and a designator column.
TableLayout? detectTable(List<Grid> sheets, TableKind kind, {int scanRows = 40, int sampleRows = 600}) {
  TableLayout? best;
  for (final grid in sheets) {
    if (grid.rows.isEmpty) continue;
    final s = _Sheet(grid, scanRows + sampleRows);
    var bestHeader = -2;
    var bestScore = double.negativeInfinity;
    for (var h = -1; h < scanRows && h < s.cells.length - 1; h++) {
      if (h >= 0 && s.cells[h].where((c) => !c.empty).length < 2) continue;
      final to = math.min(s.cells.length, h + 1 + sampleRows);
      final (roles, score) = _assign(s, kind, h, h + 1, to);
      final head = _headerness(s, h, roles);
      if (head < 0) continue;
      final total = score + 0.6 * head - (h < 0 ? 0.05 : 0);
      if (total > bestScore + 1e-9) {
        bestScore = total;
        bestHeader = h;
      }
    }
    if (bestHeader < -1) continue;
    final full = _Sheet(grid, grid.rows.length);
    final (roles, _) = _assign(full, kind, bestHeader, bestHeader + 1, full.cells.length);
    final layout = _layout(full, kind, bestHeader, roles, bestScore);
    if (!layout.usable) continue;
    if (best == null || bestScore > best.score) best = layout;
  }
  return best;
}

TableLayout _layout(_Sheet s, TableKind kind, int header, Map<int, _Pick> roles, double score) {
  final columns = <ColumnInfo>[];
  for (var c = 0; c < s.width; c++) {
    final samples = <String>[];
    for (var r = header + 1; r < s.cells.length && samples.length < 3; r++) {
      final v = s.at(r, c).value;
      if (v.isNotEmpty && !samples.contains(v)) samples.add(v.length > 40 ? '${v.substring(0, 40)}…' : v);
    }
    final pick = roles[c];
    final h = header >= 0 ? s.at(header, c).value : '';
    if (pick == null && h.isEmpty && samples.isEmpty) continue;
    columns.add(ColumnInfo(
      index: c,
      header: h,
      role: pick?.role ?? ColumnRole.other,
      confidence: pick?.score ?? 0,
      samples: samples,
      profile: _profile(s, c, header + 1, s.cells.length),
    ));
  }
  return TableLayout(kind: kind, sheet: s.grid, headerRow: header, columns: columns, score: score);
}

Set<String> _values(TableLayout l, int col) => {
      for (var r = l.headerRow + 1; r < l.sheet.rows.length; r++)
        if (l.sheet.cell(r, col).trim().isNotEmpty) l.sheet.cell(r, col).trim().toUpperCase(),
    };

/// Two tables about the same parts must share part numbers. When another
/// pair of code-like columns shares clearly more values than the recognised
/// part-number columns, that pair becomes the part-number columns (an MPN
/// column was picked over the internal part number, say). Columns the user
/// set by hand are kept.
(TableLayout, TableLayout) alignPartColumns(TableLayout x, TableLayout y) {
  final px = x.info(ColumnRole.partNo), py = y.info(ColumnRole.partNo);
  if (px == null || py == null || px.manual || py.manual) return (x, y);
  List<int> candidates(TableLayout l) => [
        for (final c in l.columns)
          if (c.role == ColumnRole.partNo || ((c.role == ColumnRole.other || c.role == ColumnRole.desc) && c.profile.code >= 0.5 && c.profile.fill >= 0.3)) c.index,
      ];
  double overlap(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    return a.intersection(b).length / math.min(a.length, b.length);
  }

  final vx = {for (final c in candidates(x)) c: _values(x, c)};
  final vy = {for (final c in candidates(y)) c: _values(y, c)};
  final current = overlap(vx[px.index]!, vy[py.index]!);
  var best = (px.index, py.index, current);
  for (final a in vx.entries) {
    for (final b in vy.entries) {
      final o = overlap(a.value, b.value);
      if (o > best.$3) best = (a.key, b.key, o);
    }
  }
  if (best.$3 < 0.3 || best.$3 < current + 0.2) return (x, y);
  return (
    best.$1 == px.index ? x : x.withRole(best.$1, ColumnRole.partNo, manual: false),
    best.$2 == py.index ? y : y.withRole(best.$2, ColumnRole.partNo, manual: false),
  );
}
