/// Parsers for the T100 BOM, station lists and coordinate files.
library;

import 'columns.dart';
import 'models.dart';
import 'refdes.dart';
import 'smart_table.dart';
import 'table_reader.dart';

class ParseException implements Exception {
  ParseException(this.code, [this.detail = '']);

  /// Localisation key, e.g. `parse_no_header`.
  final String code;
  final String detail;

  @override
  String toString() => 'ParseException($code) $detail';
}

double? parseNumber(String s) {
  final m = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(s.replaceAll(',', ''));
  return m == null ? null : double.tryParse(m.group(0)!);
}

Map<String, String> _headerNames(ColumnMap map) => {
      for (final e in map.columns.entries)
        e.key: map.headerRow >= 0 ? map.sheet.cell(map.headerRow, e.value) : '#${e.value + 1}'
    };

/// BOM. The columns are recognised from their contents ([detectTable]), or
/// taken from [layout] when the user has adjusted them. Rows without a part
/// number but with designators continue the previous line (long 插件位置
/// cells are often wrapped onto several rows), and repeated part numbers are
/// merged.
ParseResult<BomItem> parseBom(List<Grid> sheets, {TableLayout? layout}) {
  final found = layout ?? detectTable(sheets, TableKind.bom);
  if (found == null || !found.usable) throw ParseException('parse_no_header_bom');
  final map = found.toColumnMap();
  final others = found.otherColumns;
  final byPn = <String, BomItem>{};
  final issues = <ParseIssue>[];
  BomItem? last;
  var rowNo = map.headerRow + 1;
  for (final row in map.dataRows) {
    rowNo++;
    final pn = map.get(row, 'partNo').toUpperCase();
    final refs = splitRefs(map.get(row, 'refs'));
    final alts = map['alt'] == null
        ? const <String>[]
        : map.get(row, 'alt').split(RegExp(r'[,，;；、\s]+')).map((s) => s.trim().toUpperCase()).where((s) => s.isNotEmpty);
    if (pn.isEmpty) {
      if (last != null && (refs.isNotEmpty || alts.isNotEmpty)) {
        last.refs.addAll(refs);
        for (final a in alts) {
          if (!last.alternates.contains(a)) last.alternates.add(a);
        }
      }
      continue;
    }
    final qtyText = map.get(row, 'qty');
    final qty = qtyText.isEmpty ? null : parseNumber(qtyText);
    if (qtyText.isNotEmpty && qty == null) {
      issues.add(ParseIssue('parse_bad_qty', row: rowNo, detail: qtyText));
    }
    final existing = byPn[pn];
    if (existing != null) {
      existing.refs.addAll(refs);
      if (qty != null) existing.qty = (existing.qty ?? 0) + qty;
      for (final a in alts) {
        if (!existing.alternates.contains(a)) existing.alternates.add(a);
      }
      last = existing;
      continue;
    }
    final item = BomItem(
      partNo: pn,
      name: unwrapText(map.get(row, 'name')),
      spec: unwrapText(map.get(row, 'spec')),
      qty: qty,
      refs: refs,
      alternates: alts.toList(),
      sourceRow: rowNo,
      extras: {
        for (final e in others.entries)
          if (e.key < row.length && row[e.key].trim().isNotEmpty) e.value: unwrapText(row[e.key]),
      },
    );
    byPn[pn] = item;
    last = item;
  }
  return ParseResult(byPn.values.toList(), issues: issues, columns: _headerNames(map), layout: found);
}

/// Station list for one side / line, its columns recognised from their
/// contents (or taken from [layout]).
///
/// * A row with a part number but no slot and no designators lists an
///   alternate of the row above (how the line's station tool writes 替代料).
/// * A row without a part number continues the previous row's designators.
/// * `关联料号` different from `料号` means the row loads an alternate of it.
/// * When the list has a side column (TOP / BOT, A / B 面), each row takes
///   its side from it; otherwise every row is on [side].
ParseResult<StationItem> parseStation(List<Grid> sheets, StationSide side, {TableLayout? layout}) {
  final found = layout ?? detectTable(sheets, TableKind.station);
  if (found == null || !found.usable) throw ParseException('parse_no_header_station');
  final map = found.toColumnMap();
  final items = <StationItem>[];
  final issues = <ParseIssue>[];
  var rowNo = map.headerRow + 1;
  for (final row in map.dataRows) {
    rowNo++;
    final pn = map.get(row, 'partNo').toUpperCase();
    final refs = splitRefs(map.get(row, 'refs'));
    final slot = map.get(row, 'slot').replaceAll(RegExp(r'\s+'), '');
    if (pn.isEmpty) {
      if (items.isNotEmpty && refs.isNotEmpty) items.last.refs.addAll(refs);
      continue;
    }
    if (slot.isEmpty && refs.isEmpty && items.isNotEmpty) {
      final main = items.last;
      if (pn != main.partNo && !main.alternates.contains(pn)) main.alternates.add(pn);
      continue;
    }
    final qtyText = map.get(row, 'qty');
    final qty = qtyText.isEmpty ? null : parseNumber(qtyText);
    if (qty != null && refs.isNotEmpty && qty != refs.length) {
      issues.add(ParseIssue('parse_station_qty', row: rowNo, detail: '$pn ($qtyText / ${refs.length})'));
    }
    final related = map.get(row, 'related').toUpperCase();
    final rowSide = switch (parseSide(map.get(row, 'side'))) {
      BoardSide.top => StationSide.a,
      BoardSide.bottom => StationSide.b,
      BoardSide.unknown => side,
    };
    items.add(StationItem(
      partNo: pn,
      side: rowSide,
      slot: slot,
      desc: unwrapText([map.get(row, 'desc'), map.get(row, 'desc2')].where((e) => e.isNotEmpty).join(' ')),
      qty: qty,
      refs: refs,
      relatedTo: related == pn ? '' : related,
      sourceRow: rowNo,
    ));
  }
  return ParseResult(items, issues: issues, columns: _headerNames(map), layout: found);
}

enum CoordUnit { auto, mm, mil, inch }

const _toMm = {CoordUnit.mm: 1.0, CoordUnit.mil: 0.0254, CoordUnit.inch: 25.4};

/// Original pick & place / coordinate file. Values are converted to mm.
ParseResult<Placement> parseCoordinates(List<Grid> sheets,
    {CoordUnit unit = CoordUnit.auto}) {
  var map = detectColumns(sheets, Fields.coords);
  map ??= _headerlessCoords(sheets);
  if (map == null) throw ParseException('parse_no_header_coord');

  var resolved = unit;
  if (resolved == CoordUnit.auto) resolved = _guessUnit(map);
  final factor = _toMm[resolved]!;

  final out = <Placement>[];
  final issues = <ParseIssue>[];
  final seen = <String>{};
  var rowNo = map.headerRow + 1;
  for (final row in map.dataRows) {
    rowNo++;
    final ref = normalizeRef(map.get(row, 'ref'));
    if (ref.isEmpty) continue;
    final x = parseNumber(map.get(row, 'x'));
    final y = parseNumber(map.get(row, 'y'));
    if (x == null || y == null) {
      issues.add(ParseIssue('parse_bad_xy', row: rowNo, detail: ref));
      continue;
    }
    if (!seen.add(ref)) {
      issues.add(ParseIssue('parse_dup_ref', row: rowNo, detail: ref));
      continue;
    }
    out.add(Placement(
      ref: ref,
      x: x * factor,
      y: y * factor,
      rotation: parseNumber(map.get(row, 'rot')) ?? 0,
      side: parseSide(map.get(row, 'layer')),
      value: map.get(row, 'value'),
      footprint: map.get(row, 'footprint'),
      smd: _parseSmd(map.get(row, 'smd')),
      partNo: map.get(row, 'partNo'),
      description: map.get(row, 'spec'),
    ));
  }
  return ParseResult(out,
      issues: issues,
      columns: {..._headerNames(map), 'unit': resolved.name});
}

bool? _parseSmd(String s) {
  final v = s.trim().toUpperCase();
  if (v.isEmpty) return null;
  if (const {'YES', 'Y', '1', 'TRUE', 'SMD', 'SMT', '是'}.contains(v)) return true;
  if (const {'NO', 'N', '0', 'FALSE', 'DIP', 'THT', 'TH', '否'}.contains(v)) return false;
  return null;
}

BoardSide parseSide(String s) {
  final v = s.trim().toLowerCase();
  if (v.isEmpty) return BoardSide.unknown;
  const top = {'t', 'top', 'toplayer', 'top layer', 'front', 'f', 'a', '顶层', '正面', 'a面', '1', 'no'};
  const bottom = {'b', 'bot', 'bottom', 'bottomlayer', 'bottom layer', 'back', 'b面', '底层', '背面', '2', 'yes', 'mirror'};
  if (top.contains(v)) return BoardSide.top;
  if (bottom.contains(v)) return BoardSide.bottom;
  if (v.startsWith('top')) return BoardSide.top;
  if (v.startsWith('bot')) return BoardSide.bottom;
  return BoardSide.unknown;
}

CoordUnit _guessUnit(ColumnMap map) {
  final header = map.headerRow >= 0
      ? map.sheet.rows[map.headerRow].join(' ').toLowerCase()
      : '';
  // Look at the preamble too: Altium writes "Units used in this file : mm".
  final preamble = map.sheet.rows
      .take(map.headerRow < 0 ? 0 : map.headerRow)
      .map((r) => r.join(' ').toLowerCase())
      .join(' ');
  final firstValues = map.dataRows.take(5).map((r) => map.get(r, 'x').toLowerCase()).join(' ');
  final text = '$header $preamble $firstValues';
  if (text.contains('mil')) return CoordUnit.mil;
  if (RegExp(r'\binch\b|\bin\)').hasMatch(text)) return CoordUnit.inch;
  return CoordUnit.mm;
}

/// Fallback for files with no header: `REF X Y [ROT] [SIDE] ...`.
ColumnMap? _headerlessCoords(List<Grid> sheets) {
  for (final sheet in sheets) {
    final rows = sheet.rows.where((r) => r.length >= 3).take(10).toList();
    if (rows.isEmpty) continue;
    final ok = rows.every((r) =>
        RegExp(r'^[A-Za-z0-9_]+$').hasMatch(r[0]) &&
        parseNumber(r[1]) != null &&
        parseNumber(r[2]) != null);
    if (!ok) continue;
    final cols = {'ref': 0, 'x': 1, 'y': 2};
    final width = rows.first.length;
    if (width > 3) cols['rot'] = 3;
    if (width > 4) cols['layer'] = 4;
    return ColumnMap(-1, cols, sheet);
  }
  return null;
}
