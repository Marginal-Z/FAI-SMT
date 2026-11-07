/// Excel report of a comparison: every part with both sides side by side,
/// differing cells filled, plus the AI analysis when there is one.
library;

import 'dart:typed_data';

import 'ai_check.dart';
import 'bom.dart';
import 'bom_compare.dart';
import 'params.dart';
import 'xlsx_writer.dart';

String _stamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// [t] translates the report's text keys (`rep_*`, `status_*`).
Uint8List exportCompareWorkbook(CompareReport report, String Function(String key) t, {AiResult? ai, String singleName = '', String aName = '', String bName = ''}) =>
    buildCompareWorkbook(report, t, ai: ai, singleName: singleName, aName: aName, bName: bName).encode();

/// The report before encoding, so its cells and fills can be inspected.
XlsxWriter buildCompareWorkbook(CompareReport report, String Function(String key) t, {AiResult? ai, String singleName = '', String aName = '', String bName = ''}) {
  final book = XlsxWriter();
  final sheet = book.addSheet(t('rep_sheet'));

  const head = XlsxStyle(bold: true, fill: 'E5E7EB', center: true);
  const diffFill = XlsxStyle(fill: 'FFE3A3');
  const aiFill = XlsxStyle(fill: 'D5F0EE');
  const statusFill = {
    CheckStatus.pass: XlsxStyle(fill: 'D9F2E1'),
    CheckStatus.ng: XlsxStyle(fill: 'FDE2E1'),
    CheckStatus.review: XlsxStyle(fill: 'FFE7C2'),
    CheckStatus.unmatched: XlsxStyle(fill: 'DCE8FA'),
    CheckStatus.substitute: XlsxStyle(fill: 'D5F0EE'),
  };

  // Source files.
  sheet.appendRow([t('rep_single'), singleName]);
  sheet.appendRow([t('rep_a'), aName]);
  if (bName.isNotEmpty) sheet.appendRow([t('rep_b'), bName]);
  sheet.appendRow([t('rep_time'), _stamp(report.at)]);
  sheet.appendRow([t('rep_mode'), t('mode_${report.mode}'), if (report.models.isNotEmpty) '${t('rep_models')}: ${report.models.join(', ')}']);
  // An incomplete check says so above the table.
  sheet.appendRow([t('rep_complete'), report.complete ? t('rep_complete_yes') : t('rep_complete_no').replaceAll('{n}', '${report.uncovered.length}')]);
  if (!report.complete) sheet.style(sheet.rowCount - 1, 1, const XlsxStyle(bold: true, fill: 'FDE2E1'));
  sheet.appendRow([]);

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
    t('rep_src_single'),
    t('rep_src_merged'),
    t('rep_basis'),
    t('rep_reasons'),
    t('rep_risk'),
    t('rep_params_single'),
    t('rep_params_merged'),
    t('rep_cloud_note'),
    t('rep_ai'),
  ];
  final headRow = sheet.rowCount;
  sheet.appendRow(headers);
  for (var c = 0; c < headers.length; c++) {
    sheet.style(headRow, c, head);
  }

  var n = 0;
  for (final r in report.rows) {
    n++;
    final row = sheet.rowCount;
    final aiNotes = ai?.forPart(r.partNo).map((f) => f.message).join('; ') ?? '';
    sheet.appendRow([
      n,
      r.partNo,
      t('status_${r.status.name}'),
      r.sources.join('+'),
      r.single?.description ?? '',
      r.merged?.description ?? '',
      formatQuantity(r.single?.quantity),
      formatQuantity(r.merged?.quantity),
      r.single?.refs.join(',') ?? '',
      r.merged?.refs.join(',') ?? '',
      r.missingRefs.join(','),
      r.extraRefs.join(','),
      for (final o in others) ...[r.single?.extra[o.key] ?? '', r.merged?.extra[o.key] ?? ''],
      r.single?.recordIds.join(', ') ?? '',
      r.merged?.recordIds.join(', ') ?? '',
      [for (final k in r.basis.kinds) t('basis_$k'), if (r.basis.kinds.isNotEmpty) '${(r.basis.confidence * 100).round()}%'].join(' · '),
      [for (final k in r.reasons) t('reason_$k')].join('; '),
      t('risk_${riskOf(r).name}'),
      normalisedParams(r.single?.description ?? ''),
      normalisedParams(r.merged?.description ?? ''),
      r.cloudNote,
      aiNotes,
    ]);
    sheet.style(row, 2, statusFill[r.status]!);
    // Differing fields: both sides of the field are filled.
    for (final f in r.differences) {
      final col = switch (f.key) {
        'description' => 4,
        'quantity' => 6,
        'refs' => 8,
        _ => 12 + 2 * others.indexWhere((o) => 'col:${o.key}' == f.key),
      };
      if (col < 4) continue;
      sheet.style(row, col, diffFill);
      sheet.style(row, col + 1, diffFill);
    }
    if (r.missingRefs.isNotEmpty) sheet.style(row, 10, diffFill);
    if (r.extraRefs.isNotEmpty) sheet.style(row, 11, diffFill);
    if (aiNotes.isNotEmpty) sheet.style(row, headers.length - 1, aiFill);
  }
  const widths = [6.0, 22.0, 10.0, 8.0, 36.0, 36.0, 8.0, 8.0, 30.0, 30.0, 18.0, 18.0];
  for (var c = 0; c < widths.length; c++) {
    sheet.setWidth(c, widths[c]);
  }
  for (var c = 12; c < headers.length; c++) {
    sheet.setWidth(c, c == headers.length - 1 ? 50 : (c >= headers.length - 9 ? 26 : 18));
  }

  // Summary: counts by result, risk and reason.
  final sum = book.addSheet(t('rep_summary_sheet'));
  sum.appendRow([t('rep_result'), t('rep_count')]);
  sum.style(0, 0, head);
  sum.style(0, 1, head);
  for (final st in CheckStatus.values) {
    sum.appendRow([t('status_${st.name}'), report.count(st)]);
  }
  sum.appendRow([]);
  final rh = sum.rowCount;
  sum.appendRow([t('rep_risk'), t('rep_count')]);
  sum.style(rh, 0, head);
  sum.style(rh, 1, head);
  for (final k in Risk.values) {
    sum.appendRow([t('risk_${k.name}'), report.countRisk(k)]);
  }
  sum.appendRow([]);
  final reh = sum.rowCount;
  sum.appendRow([t('rep_reasons'), t('rep_count')]);
  sum.style(reh, 0, head);
  sum.style(reh, 1, head);
  for (final e in (report.reasonCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))) {
    sum.appendRow([t('reason_${e.key}'), e.value]);
  }
  sum.setWidth(0, 44);
  sum.setWidth(1, 10);

  if (ai != null) {
    final s = book.addSheet(t('rep_ai_sheet'));
    s.appendRow([t('rep_ai_model'), ai.model]);
    s.appendRow([t('rep_time'), _stamp(ai.at)]);
    s.appendRow([t('rep_ai_summary'), ai.summary]);
    s.appendRow([]);
    final h = [t('rep_part_no'), t('rep_ai_field'), t('rep_ai_severity'), t('rep_ai_single'), t('rep_ai_merged'), t('rep_ai_message')];
    final hr = s.rowCount;
    s.appendRow(h);
    for (var c = 0; c < h.length; c++) {
      s.style(hr, c, head);
    }
    for (final f in ai.findings) {
      s.appendRow([f.partNo, f.field, t('ai_sev_${f.severity.name}'), f.singleValue, f.mergedValue, f.message]);
    }
    for (final (c, w) in [(0, 22.0), (1, 14.0), (2, 8.0), (3, 30.0), (4, 30.0), (5, 70.0)]) {
      s.setWidth(c, w);
    }
  }
  return book;
}
