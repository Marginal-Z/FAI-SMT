import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/core/history.dart';
import 'package:smt_fai/core/local_ai/usage.dart';
import 'package:smt_fai/core/report.dart';
import 'package:smt_fai/l10n/strings.dart';

import 'support/local_models.dart';

void main() {
  test(
    'Excel and history preserve the per-row local AI explanation and usage',
    () async {
      final dir = Directory.systemTemp.createTempSync('local-report-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final state = localState(dir.path, FakeLocalModels())..runCheckNow();
      await settleLocal(state);
      final report = state.report!;
      final usage = report.localModel;
      expect(LocalModelUsage.fromJson(usage.toJson()).toJson(), usage.toJson());
      final book = buildCompareWorkbook(report, Strings('zh').t);
      final sheet = book.sheets.first;
      final header = List.generate(
        sheet.rowCount,
        (i) => i,
      ).firstWhere((i) => sheet.value(i, 0) == '#');
      final localCol = List.generate(80, (i) => i).firstWhere(
        (i) => sheet.value(header, i) == Strings('zh').t('rep_local_note'),
      );
      for (var i = 0; i < report.rows.length; i++) {
        expect(sheet.value(header + i + 1, localCol), report.rows[i].localNote);
        final line = HistoryLine.fromJson(
          HistoryLine.of(report.rows[i]).toJson(),
        );
        expect(line.localNote, report.rows[i].localNote);
      }
      final cells = [
        for (var r = 0; r < header; r++)
          for (var c = 0; c < 8; c++) '${sheet.value(r, c) ?? ''}',
      ];
      expect(cells.any((v) => v.contains('已分析 2/2 项')), isTrue);
      expect(cells.any((v) => v.contains(usage.model)), isTrue);
    },
  );

  test(
    'old history usage remains an embedding record without invented analysis',
    () {
      final old = LocalModelUsage.fromJson({
        'state': 'done',
        'texts': 4,
        'paired': 2,
      });
      expect(old.kind, 'embedding');
      expect(old.rows, 0);
      expect(old.calls, 0);
      expect(HistoryLine.fromJson({'p': 'R1', 's': 'pass'}).localNote, isEmpty);
    },
  );
}
