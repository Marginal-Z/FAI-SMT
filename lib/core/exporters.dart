/// Exports: check report workbook and the FAI CAD coordinate file.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:fast_gbk/fast_gbk.dart';

import 'models.dart';
import 'parsers.dart';
import 'refdes.dart';
import 'settings.dart';

/// Localised labels the exporters need; supplied by the UI layer.
class ExportLabels {
  ExportLabels({
    required this.sheetCheck,
    required this.sheetMerged,
    required this.checkHeaders,
    required this.mergedHeaders,
    required this.category,
    required this.reason,
    required this.side,
  });

  final String sheetCheck;
  final String sheetMerged;

  /// No., part no., description, BOM qty, SMT qty, BOM refs, SMT refs,
  /// loaded part numbers, side, slot, result, reason.
  final List<String> checkHeaders;

  /// Ref, BOM part no., SMT part no., description, side, slot, result.
  final List<String> mergedHeaders;
  final String Function(CheckCategory) category;
  final String Function(Reason) reason;
  final String Function(StationSide?) side;
}

/// [extraSheets] maps a sheet name to rows whose first row is the header.
Uint8List exportCheckWorkbook(CheckReport report, ExportLabels l, {Map<String, List<List<String>>> extraSheets = const {}}) {
  final book = Excel.createExcel();
  final defaultSheet = book.getDefaultSheet();
  final check = book[l.sheetCheck];
  final merged = book[l.sheetMerged];
  if (defaultSheet != null && defaultSheet != l.sheetCheck && defaultSheet != l.sheetMerged) {
    book.delete(defaultSheet);
  }

  final head = CellStyle(
    bold: true,
    backgroundColorHex: ExcelColor.fromHexString('#E5E7EB'),
    horizontalAlign: HorizontalAlign.Center,
  );
  final fills = {
    CheckCategory.pass: ExcelColor.fromHexString('#DCFCE7'),
    CheckCategory.ng: ExcelColor.fromHexString('#FEE2E2'),
    CheckCategory.excluded: ExcelColor.fromHexString('#F3F4F6'),
    CheckCategory.substitute: ExcelColor.fromHexString('#FEF3C7'),
  };

  check.appendRow([for (final h in l.checkHeaders) TextCellValue(h)]);
  for (var c = 0; c < l.checkHeaders.length; c++) {
    check.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).cellStyle = head;
  }
  var i = 0;
  for (final r in report.rows) {
    i++;
    check.appendRow([
      IntCellValue(i),
      TextCellValue(r.partNo),
      TextCellValue(r.description),
      r.bomQty == null ? TextCellValue('') : DoubleCellValue(r.bomQty!),
      r.smtQty == null ? TextCellValue('') : IntCellValue(r.smtQty!),
      TextCellValue(r.bomRefs.map((m) => m.ref).join(',')),
      TextCellValue(r.smtRefs.map((m) => m.ref).join(',')),
      TextCellValue(r.smtPartNos.join(',')),
      TextCellValue((r.sides.toList()..sort((a, b) => a.index - b.index)).map(l.side).join('/')),
      TextCellValue(r.slots.join(',')),
      TextCellValue(l.category(r.category)),
      TextCellValue(r.reasons.map(l.reason).join('; ')),
    ]);
    final style = CellStyle(backgroundColorHex: fills[r.category]!);
    check.cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: i)).cellStyle = style;
  }
  const widths = [6.0, 22.0, 40.0, 9.0, 9.0, 36.0, 36.0, 22.0, 8.0, 12.0, 10.0, 60.0];
  for (var c = 0; c < widths.length; c++) {
    check.setColumnWidth(c, widths[c]);
  }

  merged.appendRow([for (final h in l.mergedHeaders) TextCellValue(h)]);
  for (var c = 0; c < l.mergedHeaders.length; c++) {
    merged.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).cellStyle = head;
  }
  for (final m in report.merged) {
    merged.appendRow([
      TextCellValue(m.ref),
      TextCellValue(m.bomPartNo),
      TextCellValue(m.smtPartNo),
      TextCellValue(m.description),
      TextCellValue(l.side(m.side)),
      TextCellValue(m.slot),
      TextCellValue(l.category(m.category)),
    ]);
  }
  const mw = [12.0, 22.0, 22.0, 44.0, 8.0, 12.0, 10.0];
  for (var c = 0; c < mw.length; c++) {
    merged.setColumnWidth(c, mw[c]);
  }
  for (final e in extraSheets.entries) {
    final sheet = book[e.key];
    for (var i = 0; i < e.value.length; i++) {
      sheet.appendRow([for (final v in e.value[i]) TextCellValue(v)]);
      if (i == 0) {
        for (var col = 0; col < e.value[i].length; col++) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0)).cellStyle = head;
        }
      }
    }
    const widths = [8.0, 14.0, 20.0, 60.0, 70.0, 40.0];
    for (var col = 0; col < widths.length; col++) {
      sheet.setColumnWidth(col, widths[col]);
    }
  }
  book.setDefaultSheet(l.sheetCheck);
  return Uint8List.fromList(book.encode()!);
}

class CadRow {
  CadRow(this.placement, this.merged, this.side);

  final Placement placement;
  final MergedRef? merged;
  final BoardSide side;
}

class CadResult {
  CadResult(this.rows, this.header, this.cells, this.template,
      {required this.noCoordRefs,
      required this.notInBomRefs,
      required this.unknownSide,
      this.sideMismatch = const []});

  final List<CadRow> rows;

  /// Header labels, or null when the template writes no header.
  final List<String>? header;

  /// One list per row; numbers stay numeric so the workbook keeps them as such.
  final List<List<Object>> cells;
  final CadTemplate template;

  /// BOM / station designators with no coordinate.
  final List<String> noCoordRefs;

  /// Coordinate designators not found in the merged list.
  final List<String> notInBomRefs;

  /// Rows written without a known side.
  final List<String> unknownSide;

  /// Coordinate layer disagrees with the station side (A = top, B = bottom).
  final List<String> sideMismatch;

  String _fmt(Object v) => v is double ? v.toStringAsFixed(template.decimals) : '$v';

  /// Delimited text rendering (CRLF line ends).
  String get text {
    final d = template.delimiter;
    String clean(String s) => s.replaceAll(d, ' ');
    final buf = StringBuffer();
    if (header != null) buf.write('${header!.join(d)}\r\n');
    for (final row in cells) {
      buf.write('${row.map((v) => clean(_fmt(v))).join(d)}\r\n');
    }
    return buf.toString();
  }

  /// Plain-text preview lines, columns padded for reading.
  List<String> previewLines({int limit = 5000}) {
    if (template.format == CadFormat.text) {
      return text.split('\r\n').where((l) => l.isNotEmpty).take(limit).toList();
    }
    final table = <List<String>>[?header, ...cells.take(limit).map((r) => r.map(_fmt).toList())];
    if (table.isEmpty) return const [];
    final widths = List<int>.filled(table.first.length, 0);
    for (final r in table) {
      for (var i = 0; i < r.length && i < widths.length; i++) {
        final w = _displayWidth(r[i]);
        if (w > widths[i]) widths[i] = w;
      }
    }
    return [
      for (final r in table)
        [for (var i = 0; i < r.length; i++) i == r.length - 1 ? r[i] : r[i] + ' ' * (widths[i] - _displayWidth(r[i]))].join('  ')
    ];
  }

  /// The file to save, in the template's format and encoding.
  Uint8List encode() {
    if (template.format == CadFormat.text) {
      return switch (template.encoding) {
        'gbk' => Uint8List.fromList(gbk.encode(text)),
        'utf8bom' => Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(text)]),
        _ => Uint8List.fromList(utf8.encode(text)),
      };
    }
    final book = Excel.createExcel();
    final defaultSheet = book.getDefaultSheet();
    final sheet = book['CAD'];
    if (defaultSheet != null && defaultSheet != 'CAD') book.delete(defaultSheet);
    if (header != null) sheet.appendRow([for (final h in header!) TextCellValue(h)]);
    for (final row in cells) {
      sheet.appendRow([
        for (final v in row)
          switch (v) {
            int() => IntCellValue(v),
            double() => DoubleCellValue(double.parse(v.toStringAsFixed(template.decimals))),
            _ => TextCellValue('$v'),
          }
      ]);
    }
    book.setDefaultSheet('CAD');
    return Uint8List.fromList(book.encode()!);
  }
}

/// CJK characters take two columns in a monospace preview.
int _displayWidth(String s) => s.runes.fold(0, (n, r) => n + (r >= 0x1100 ? 2 : 1));

/// Joins the merged list with the original coordinates according to [t].
CadResult buildCad(List<Placement> placements, CheckReport report, CadTemplate t, CheckRules rules) {
  final byRef = {for (final m in report.merged) m.ref: m};
  final rows = <CadRow>[];
  final notInBom = <String>[];
  final unknownSide = <String>[];
  final sideMismatch = <String>[];

  final ordered = [...placements]..sort((a, b) => compareRefs(a.ref, b.ref));
  for (final p in ordered) {
    if (rules.isIgnoredRef(p.ref)) continue;
    final m = byRef[p.ref];
    if (m == null) {
      notInBom.add(p.ref);
      if (!t.includeUnmatched) continue;
    }
    if (p.side != BoardSide.unknown && m?.side != null &&
        (p.side == BoardSide.top) != (m!.side == StationSide.a)) {
      sideMismatch.add(p.ref);
    }
    var side = p.side;
    if (side == BoardSide.unknown && t.sideFromStation && m?.side != null) {
      side = m!.side == StationSide.a ? BoardSide.top : BoardSide.bottom;
    }
    if (side == BoardSide.unknown) unknownSide.add(p.ref);
    rows.add(CadRow(p, m, side));
  }
  final coordRefs = {for (final p in placements) p.ref};
  final noCoord = sortedRefs(byRef.keys.where((r) => !coordRefs.contains(r)));

  final factor = switch (t.unit) {
    CoordUnit.mil => 1 / 0.0254,
    CoordUnit.inch => 1 / 25.4,
    _ => 1.0,
  };
  String clean(String s) => s.replaceAll(RegExp(r'[\r\n\t]'), ' ').trim();

  final cells = <List<Object>>[];
  for (final r in rows) {
    final p = r.placement;
    final m = r.merged;
    cells.add([
      for (final f in t.fields)
        switch (f) {
          CadField.ref => p.ref,
          CadField.x => p.x * factor,
          CadField.y => p.y * factor,
          CadField.rotation => _rot(p.rotation),
          CadField.side => switch (r.side) {
              BoardSide.top => t.topText,
              BoardSide.bottom => t.bottomText,
              BoardSide.unknown => '',
            },
          CadField.partNo => clean(m == null ? '' : (m.bomPartNo.isNotEmpty ? m.bomPartNo : m.smtPartNo)),
          CadField.loadedPartNo => clean(m == null ? '' : (m.smtPartNo.isNotEmpty ? m.smtPartNo : m.bomPartNo)),
          CadField.description => clean(m?.description ?? ''),
          CadField.value => clean(p.value),
          CadField.footprint => clean(p.footprint),
          CadField.slot => clean(m?.slot ?? ''),
          CadField.qty => 1,
        }
    ]);
  }
  return CadResult(rows, t.writeHeader ? t.fields.map(t.headerOf).toList() : null, cells, t,
      noCoordRefs: noCoord,
      notInBomRefs: notInBom,
      unknownSide: unknownSide,
      sideMismatch: sideMismatch);
}

/// Angle normalised to [0, 360); whole degrees stay integers.
Object _rot(double r) {
  var v = r % 360;
  if (v < 0) v += 360;
  return v == v.roundToDouble() ? v.toInt() : v;
}
