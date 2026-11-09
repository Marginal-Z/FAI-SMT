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

/// Column groups of the report table that can be left out; the number,
/// part number and result are always there.
const reportColumnGroups = ['source', 'description', 'quantity', 'refs', 'refs_diff', 'others', 'rows', 'basis', 'reasons', 'risk', 'params',
  'orientation', 'local_ai', 'cloud', 'ai'];

/// What the report holds: column groups left out ([reportColumnGroups]) and
/// which results are listed (all when empty).
class ReportOptions {
  const ReportOptions({this.hidden = const {}, this.statuses = const {}});

  final Set<String> hidden;
  final Set<CheckStatus> statuses;

  bool shows(String group) => !hidden.contains(group);
}

class _Col {
  const _Col(this.group, this.header, this.width, this.value, {this.diff, this.fill});

  final String group;
  final String header;
  final double width;
  final Object? Function(CompareRow r) value;

  /// The field whose difference fills this cell.
  final String? diff;

  /// Fills the cell when true.
  final bool Function(CompareRow r)? fill;
}

/// [t] translates the report's text keys (`rep_*`, `status_*`).
Uint8List exportCompareWorkbook(CompareReport report, String Function(String key) t, {AiResult? ai, String singleName = '', String aName = '', String bName = '', ReportOptions options = const ReportOptions()}) =>
    buildCompareWorkbook(report, t, ai: ai, singleName: singleName, aName: aName, bName: bName, options: options).encode();

/// The report before encoding, so its cells and fills can be inspected.
XlsxWriter buildCompareWorkbook(CompareReport report, String Function(String key) t, {AiResult? ai, String singleName = '', String aName = '', String bName = '', ReportOptions options = const ReportOptions()}) {
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
  final usage = report.localModel;
  sheet.appendRow([
    t('local_usage_title'),
    t('local_state_${usage.state}'),
    usage.model,
    usage.kind == 'analysis'
      ? t('local_analysis_counts').replaceAll('{n}', '${usage.rows}').replaceAll('{all}', '${usage.total}').replaceAll('{b}', '${usage.calls}').replaceAll('{ms}', '${usage.millis}')
      : t('local_usage_counts').replaceAll('{n}', '${usage.texts}').replaceAll('{p}', '${usage.paired}').replaceAll('{ms}', '${usage.millis}'),
    if (usage.error.isNotEmpty) t(usage.error),
  ]);
  // An incomplete check says so above the table.
  sheet.appendRow([t('rep_complete'),
    report.pending
        ? t('rep_pending')
        : report.complete ? t('rep_complete_yes') : t('rep_complete_no').replaceAll('{n}', '${report.uncovered.length}')]);
  if (!report.complete) sheet.style(sheet.rowCount - 1, 1, const XlsxStyle(bold: true, fill: 'FDE2E1'));
  if (report.skipped.isNotEmpty) sheet.appendRow([t('rep_skipped'), [for (final k in report.skipped) t('cmpf_$k')].join(', ')]);
  if (options.statuses.isNotEmpty) sheet.appendRow([t('rep_listed'), [for (final st in options.statuses) t('status_${st.name}')].join(', ')]);
  sheet.appendRow([]);

  String aiNotes(CompareRow r) => ai?.forPart(r.partNo).map((f) => f.message).join('; ') ?? '';
  final others = report.compared.entries.toList();
  final cols = <_Col>[
    _Col('', '#', 6, (r) => null),
    _Col('', t('rep_part_no'), 22, (r) => r.partNo),
    _Col('', t('rep_result'), 10, (r) => t('status_${r.status.name}')),
    _Col('source', t('rep_source'), 8, (r) => r.sourceNames.join('+')),
    _Col('description', t('rep_desc_single'), 36, (r) => r.single?.description ?? '', diff: 'description'),
    _Col('description', t('rep_desc_merged'), 36, (r) => r.merged?.description ?? '', diff: 'description'),
    _Col('quantity', t('rep_qty_single'), 8, (r) => formatQuantity(r.single?.quantity), diff: 'quantity'),
    _Col('quantity', t('rep_qty_merged'), 8, (r) => formatQuantity(r.merged?.quantity), diff: 'quantity'),
    _Col('refs', t('rep_refs_single'), 30, (r) => r.single?.refs.join(',') ?? '', diff: 'refs'),
    _Col('refs', t('rep_refs_merged'), 30, (r) => r.merged?.refs.join(',') ?? '', diff: 'refs'),
    _Col('refs_diff', t('rep_missing'), 18, (r) => r.missingRefs.join(','), fill: (r) => r.missingRefs.isNotEmpty),
    _Col('refs_diff', t('rep_extra'), 18, (r) => r.extraRefs.join(','), fill: (r) => r.extraRefs.isNotEmpty),
    for (final o in others) ...[
      _Col('others', '${o.value} (${t('rep_single_short')})', 18, (r) => r.single?.extra[o.key] ?? '', diff: 'col:${o.key}'),
      _Col('others', '${o.value} (${t('side_merged')})', 18, (r) => r.merged?.extra[o.key] ?? '', diff: 'col:${o.key}'),
    ],
    _Col('rows', t('rep_src_single'), 26, (r) => r.single?.recordIds.join(', ') ?? ''),
    _Col('rows', t('rep_src_merged'), 26, (r) => r.merged?.recordIds.join(', ') ?? ''),
    _Col('basis', t('rep_basis'), 26, (r) => [for (final k in r.basis.kinds) t('basis_$k'), if (r.basis.kinds.isNotEmpty) '${(r.basis.confidence * 100).round()}%'].join(' · ')),
    _Col('reasons', t('rep_reasons'), 26, (r) => [for (final k in r.reasons) t('reason_$k')].join('; ')),
    _Col('risk', t('rep_risk'), 10, (r) => t('risk_${riskOf(r).name}')),
    _Col('params', t('rep_params_single'), 26, (r) => normalisedParams(r.single?.description ?? '')),
    _Col('params', t('rep_params_merged'), 26, (r) => normalisedParams(r.merged?.description ?? '')),
    _Col(
      'reasons',
      t('input_integrity'),
      50,
      (r) => r.fields
          .where((f) => f.key.startsWith('input:'))
          .map((f) => '${f.single}${f.merged}')
          .join('\n'),
    ),
    _Col(
      'orientation',
      t('orientation_title'),
      56,
      (r) => r.orientation
          .map(
            (h) =>
                '${t('orientation_${h.code}')}\n${h.evidence}\n${h.refs.isEmpty ? t('orientation_no_refs') : h.refs.join(', ')}',
          )
          .join('\n'),
      fill: (r) => r.orientation.isNotEmpty,
    ),
    _Col('local_ai', t('rep_local_note'), 30, (r) => r.localNote),
    _Col('cloud', t('rep_cloud_note'), 26, (r) => r.cloudNote),
    _Col('ai', t('rep_ai'), 50, aiNotes, fill: (r) => aiNotes(r).isNotEmpty),
  ].where((c) => c.group.isEmpty || options.shows(c.group)).toList();

  final headRow = sheet.rowCount;
  sheet.appendRow([for (final c in cols) c.header]);
  for (var c = 0; c < cols.length; c++) {
    sheet.style(headRow, c, head);
    sheet.setWidth(c, cols[c].width);
  }

  var n = 0;
  for (final r in report.rows) {
    if (options.statuses.isNotEmpty && !options.statuses.contains(r.status)) continue;
    n++;
    final row = sheet.rowCount;
    sheet.appendRow([for (final c in cols) c.header == '#' && c.group.isEmpty ? n : c.value(r)]);
    sheet.style(row, 2, statusFill[r.status]!);
    // Differing fields: both sides of the field are filled.
    final differs = {for (final f in r.differences) f.key};
    for (var c = 0; c < cols.length; c++) {
      final col = cols[c];
      if ((col.diff != null && differs.contains(col.diff)) || (col.fill?.call(r) ?? false)) sheet.style(row, c, col.group == 'ai' ? aiFill : diffFill);
    }
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
  sum.appendRow([]);
  sum.appendRow([
    t('orientation_title'),
    report.rows.where((r) => r.orientation.isNotEmpty).length,
  ]);
  sum.appendRow([t('orientation_scope')]);

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
