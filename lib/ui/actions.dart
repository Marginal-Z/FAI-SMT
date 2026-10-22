/// User actions that need dialogs or the file system.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../core/exporters.dart';
import '../core/models.dart';
import '../l10n/strings.dart';
import 'widgets.dart';

const _tableExts = ['xlsx', 'xlsm', 'xls', 'csv', 'txt'];
const _coordExts = ['csv', 'txt', 'xlsx', 'pos', 'mnt', 'xy', 'asc', 'rep', 'dat'];

Future<void> showError(BuildContext context, Object e) {
  final s = Strings.of(context);
  final text = e is UserMessage ? s.t(e.key, e.args) : '$e';
  return showMessage(context, title: s.t('msg_error'), message: text, ok: s.t('dlg_ok'), error: true);
}

Future<void> importFile(BuildContext context, AppState state, InputKind kind) async {
  final s = Strings.of(context);
  final title = switch (kind) {
    InputKind.bom => s.t('btn_bom'),
    InputKind.stationA => s.t('btn_station_a'),
    InputKind.stationB => s.t('btn_station_b'),
    InputKind.coords => s.t('btn_coord'),
  };
  try {
    final file = await FilePicker.pickFile(
      dialogTitle: title,
      type: FileType.custom,
      allowedExtensions: kind == InputKind.coords ? _coordExts : _tableExts,
    );
    if (file == null) return;
    final bytes = await file.xFile.readAsBytes();
    state.load(kind, file.name, bytes);
  } catch (e) {
    if (context.mounted) await showError(context, e);
  }
}

void runCheck(BuildContext context, AppState state) {
  try {
    state.runCheckNow();
    state.setModule(Module.check);
  } catch (e) {
    showError(context, e);
  }
}

ExportLabels exportLabels(Strings s) => ExportLabels(
      sheetCheck: s.t('ws_check'),
      sheetMerged: s.lang == 'zh' ? '合并清单' : s.lang == 'th' ? 'รายการรวม' : 'Merged List',
      checkHeaders: [
        s.t('col_no'), s.t('col_pn'), s.t('col_desc'), s.t('col_bom_qty'), s.t('col_smt_qty'),
        s.t('col_bom_refs'), s.t('col_smt_refs'), s.t('col_smt_pn'), s.t('col_side'), s.t('col_slot'),
        s.t('col_result'), s.t('col_reason'),
      ],
      mergedHeaders: [
        s.t('col_ref'), s.t('col_bom_pn'), s.t('col_smt_pn'), s.t('col_desc'), s.t('col_side'),
        s.t('col_slot'), s.t('col_result'),
      ],
      category: (c) => categoryLabel(s, c),
      reason: (r) => s.t(r.code, r.args),
      side: (side) => switch (side) {
            StationSide.a => s.t('side_a'),
            StationSide.b => s.t('side_b'),
            null => '',
          },
    );

String categoryLabel(Strings s, CheckCategory c) => switch (c) {
      CheckCategory.pass => s.t('res_pass'),
      CheckCategory.ng => s.t('res_ng'),
      CheckCategory.excluded => s.t('res_excluded'),
      CheckCategory.substitute => s.t('res_substitute'),
    };

Future<void> exportReport(BuildContext context, AppState state) async {
  final s = Strings.of(context);
  final report = state.report;
  if (report == null) {
    await showError(context, UserMessage('msg_need_check'));
    return;
  }
  final bytes = exportCheckWorkbook(report, exportLabels(s));
  if (!context.mounted) return;
  await _save(context, '${state.exportBaseName}_check.xlsx', bytes, ['xlsx']);
}

Future<void> exportCad(BuildContext context, AppState state) async {
  final s = Strings.of(context);
  if (state.report == null) {
    await showError(context, UserMessage('msg_need_check'));
    return;
  }
  if (state.coords == null) {
    await showError(context, UserMessage('msg_need_coord'));
    return;
  }
  final ng = state.report!.count(CheckCategory.ng);
  if (ng > 0) {
    final go = await showMessage(context,
        title: s.t('msg_warning'),
        message: s.t('msg_ng_confirm', {'n': ng}),
        ok: s.t('dlg_continue'),
        cancel: s.t('dlg_cancel'));
    if (!go || !context.mounted) return;
  }
  final cad = state.cad!;
  final t = state.settings.cad;
  await _save(context, '${state.exportBaseName}_FAI.${t.fileExtension}', cad.encode(), [t.fileExtension]);
}

Future<void> _save(BuildContext context, String name, Uint8List bytes, List<String> exts) async {
  final s = Strings.of(context);
  try {
    final uri = await FilePicker.saveFile(
      fileName: name,
      bytes: bytes,
      dialogTitle: s.t('dlg_save'),
      type: FileType.custom,
      allowedExtensions: exts,
    );
    if (uri == null) return;
    // Some desktop back-ends only return the chosen path; make sure the bytes land.
    if (uri.scheme == 'file') {
      final f = File(uri.toFilePath());
      if (!await f.exists() || await f.length() != bytes.length) {
        await f.writeAsBytes(bytes, flush: true);
      }
    }
    if (!context.mounted) return;
    final path = uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
    await showMessage(context, title: s.t('dlg_save'), message: s.t('msg_saved', {'path': path}), ok: s.t('dlg_ok'));
  } catch (e) {
    if (context.mounted) await showError(context, e);
  }
}
