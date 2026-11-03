/// User actions that need dialogs or the file system.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../core/report.dart';
import '../l10n/strings.dart';
import 'widgets.dart';

const _tableExts = ['xlsx', 'xlsm', 'xls', 'csv', 'txt'];

Future<void> showError(BuildContext context, Object e) {
  final s = Strings.of(context);
  final text = e is UserMessage ? s.t(e.key, e.args) : '$e';
  return showMessage(context, title: s.t('msg_error'), message: text, ok: s.t('dlg_ok'), error: true);
}

String inputTitle(Strings s, InputKind kind) => switch (kind) {
  InputKind.single => s.t('in_single'),
  InputKind.a => s.t('in_a'),
  InputKind.b => s.t('in_b'),
};

Future<void> importFile(BuildContext context, AppState state, InputKind kind) async {
  final s = Strings.of(context);
  try {
    final file = await FilePicker.pickFile(dialogTitle: inputTitle(s, kind), type: FileType.custom, allowedExtensions: _tableExts);
    if (file == null) return;
    final bytes = await file.xFile.readAsBytes();
    state.load(kind, file.name, bytes);
  } catch (e) {
    if (context.mounted) await showError(context, e);
  }
}

/// Desktop platforms accept files dropped onto the import cards.
bool get dropSupported => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Loads a file dropped onto an import card, checking its extension first.
Future<void> loadDropped(BuildContext context, AppState state, InputKind kind, String name, Uint8List bytes) async {
  final ext = name.split('.').last.toLowerCase();
  try {
    if (!_tableExts.contains(ext)) throw UserMessage('msg_bad_drop', {'ext': '.$ext', 'allowed': _tableExts.map((e) => '.$e').join(' / ')});
    state.load(kind, name, bytes);
  } catch (e) {
    if (context.mounted) await showError(context, e);
  }
}

void runCheck(BuildContext context, AppState state) {
  try {
    state.closeSettings();
    state.runCheckNow();
  } catch (e) {
    showError(context, e);
  }
}

Future<void> exportReport(BuildContext context, AppState state) async {
  final s = Strings.of(context);
  final report = state.report;
  if (report == null) {
    await showError(context, UserMessage('msg_need_check'));
    return;
  }
  final bytes = exportCompareWorkbook(
    report,
    (k) => s.t(k),
    ai: state.ai,
    singleName: state.single?.name ?? '',
    aName: state.bomA?.name ?? '',
    bName: state.bomB?.name ?? '',
  );
  if (!context.mounted) return;
  await _save(context, '${state.exportBaseName}_BOM核对.xlsx', bytes, ['xlsx']);
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
