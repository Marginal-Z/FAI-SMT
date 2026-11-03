/// Excel report of a comparison: every part with both sides side by side,
/// differing cells filled, plus the AI analysis when there is one.
library;

import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'ai_check.dart';
import 'bom.dart';
import 'bom_compare.dart';

String _stamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// [t] translates the report's text keys (`rep_*`, `status_*`).
Uint8List exportCompareWorkbook(CompareReport report, String Function(String key) t, {AiResult? ai, String singleName = '', String aName = '', String bName = ''}) {
  final book = Excel.createExcel();
  final defaultSheet = book.getDefaultSheet();
  final sheetName = t('rep_sheet');
  final sheet = book[sheetName];
  if (defaultSheet != null && defaultSheet != sheetName) book.delete(defaultSheet);

  final head = CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString('#E5E7EB'), horizontalAlign: HorizontalAlign.Center);
  final diffFill = CellStyle(backgroundColorHex: ExcelColor.fromHexString('#FFE3A3'));
  final aiFill = CellStyle(backgroundColorHex: ExcelColor.fromHexString('#E4D7FB'));
  final statusFill = {
    DiffStatus.same: ExcelColor.fromHexString('#D9F2E1'),
    DiffStatus.different: ExcelColor.fromHexString('#FDE2E1'),
    DiffStatus.onlySingle: ExcelColor.fromHexString('#FFE7C2'),
    DiffStatus.onlyMerged: ExcelColor.fromHexString('#DCE8FA'),
  };

  // Source files.
  var row = 0;
  void line(List<String> cells) {
    // An empty list appends nothing, so a blank line gets one empty cell.
    sheet.appendRow([for (final c in cells.isEmpty ? const [''] : cells) TextCellValue(c)]);
    row++;
  }

  line([t('rep_single'), singleName]);
  line([t('rep_a'), aName]);
  if (bName.isNotEmpty) line([t('rep_b'), bName]);
  line([t('rep_time'), _stamp(report.at)]);
  line([]);

  final others = report.compared.entries.toList();
  final headers = [
    '#',
    t('rep_part_no'),
    t('rep_result'),
    t('rep_source'),
    t('rep_desc_single'),
    t('rep_desc_merged'),
    t('rep_qty_single'),
    t('rep_qty_merged'),
    t('rep_refs_single'),
    t('rep_refs_merged'),
    t('rep_missing'),
    t('rep_extra'),
    for (final o in others) ...['${o.value} (${t('rep_single_short')})', '${o.value} (A+B)'],
    t('rep_ai'),
  ];
  final headRow = row;
  line(headers);
  for (var c = 0; c < headers.length; c++) {
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: headRow)).cellStyle = head;
  }

  var n = 0;
  for (final r in report.rows) {
    n++;
    final aiNotes = ai?.forPart(r.partNo).map((f) => f.message).join('; ') ?? '';
    final cells = <CellValue>[
      IntCellValue(n),
      TextCellValue(r.partNo),
      TextCellValue(t('status_${r.status.name}')),
      TextCellValue(r.sources.join('+')),
      TextCellValue(r.single?.description ?? ''),
      TextCellValue(r.merged?.description ?? ''),
      TextCellValue(formatQuantity(r.single?.quantity)),
      TextCellValue(formatQuantity(r.merged?.quantity)),
      TextCellValue(r.single?.refs.join(',') ?? ''),
      TextCellValue(r.merged?.refs.join(',') ?? ''),
      TextCellValue(r.missingRefs.join(',')),
      TextCellValue(r.extraRefs.join(',')),
      for (final o in others) ...[TextCellValue(r.single?.extra[o.key] ?? ''), TextCellValue(r.merged?.extra[o.key] ?? '')],
      TextCellValue(aiNotes),
    ];
    sheet.appendRow(cells);
    void fill(int col, CellStyle style) => sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row)).cellStyle = style;
    fill(2, CellStyle(backgroundColorHex: statusFill[r.status]!));
    // Differing fields: both sides of the field are filled.
    for (final f in r.differences) {
      final col = switch (f.key) {
        'description' => 4,
        'quantity' => 6,
        'refs' => 8,
        _ => 12 + 2 * others.indexWhere((o) => 'col:${o.key}' == f.key),
      };
      if (col < 4) continue;
      fill(col, diffFill);
      fill(col + 1, diffFill);
    }
    if (r.missingRefs.isNotEmpty) fill(10, diffFill);
    if (r.extraRefs.isNotEmpty) fill(11, diffFill);
    if (aiNotes.isNotEmpty) fill(headers.length - 1, aiFill);
    row++;
  }
  const widths = [6.0, 22.0, 10.0, 8.0, 36.0, 36.0, 8.0, 8.0, 30.0, 30.0, 18.0, 18.0];
  for (var c = 0; c < widths.length; c++) {
    sheet.setColumnWidth(c, widths[c]);
  }
  for (var c = 12; c < headers.length; c++) {
    sheet.setColumnWidth(c, c == headers.length - 1 ? 50 : 18);
  }

  if (ai != null) {
    final s = book[t('rep_ai_sheet')];
    s.appendRow([TextCellValue(t('rep_ai_model')), TextCellValue(ai.model)]);
    s.appendRow([TextCellValue(t('rep_time')), TextCellValue(_stamp(ai.at))]);
    s.appendRow([TextCellValue(t('rep_ai_summary')), TextCellValue(ai.summary)]);
    s.appendRow([TextCellValue('')]);
    final h = [t('rep_part_no'), t('rep_ai_field'), t('rep_ai_severity'), t('rep_ai_single'), t('rep_ai_merged'), t('rep_ai_message')];
    s.appendRow([for (final x in h) TextCellValue(x)]);
    for (var c = 0; c < h.length; c++) {
      s.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 4)).cellStyle = head;
    }
    for (final f in ai.findings) {
      s.appendRow([
        TextCellValue(f.partNo),
        TextCellValue(f.field),
        TextCellValue(t('ai_sev_${f.severity.name}')),
        TextCellValue(f.singleValue),
        TextCellValue(f.mergedValue),
        TextCellValue(f.message),
      ]);
    }
    for (final (c, w) in [(0, 22.0), (1, 14.0), (2, 8.0), (3, 30.0), (4, 30.0), (5, 70.0)]) {
      s.setColumnWidth(c, w);
    }
  }
  return Uint8List.fromList(book.encode()!);
}
