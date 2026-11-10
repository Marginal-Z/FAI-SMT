import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/app_state.dart';
import 'package:smt_fai/core/bom.dart';
import 'package:smt_fai/core/local_ai/model_store.dart';
import 'package:smt_fai/core/settings.dart';
import 'package:smt_fai/core/table_reader.dart';

void main() {
  final modelDir = Platform.environment['SMT_FAI_MODELS'];
  final language = modelFor(LocalModelRole.language);
  final present =
      modelDir != null && File('$modelDir/${language.file}').existsSync();
  test(
    'real language GGUF is required before local results can be published',
    () async {
      final dir = Directory.systemTemp.createTempSync('real-language-');
      addTearDown(() => dir.deleteSync(recursive: true));
      // No localModelsFactory: this test loads the actual GGUF/native engine.
      final state = AppState(
        AppSettings(localAiEnabled: false),
        dir.path,
        models: ModelStore('${dir.path}/models', bundledDir: modelDir),
      );
      await state.refreshModels();
      expect(state.localAnalysisReady, isTrue);
      await state.testLocalModel();
      expect(
        state.localTestKey,
        'local_test_ok',
        reason: state.localTestDetail,
      );
      BomDocument doc(String id) => readBom([
        Grid('s', [
          ['料号', '描述', '用量', '位号', '旧料号'],
          ['P1001', 'LED red 0603', '1', 'D1', id == 'S' ? '' : 'OLD-LED'],
          [
            'P1002',
            'Chip resistor 10k 0603',
            '1',
            'R1',
            id == 'S' ? '' : 'OLD-10K',
          ],
        ]),
      ], id: id);
      state.single = LoadedFile('A.csv', doc('S'));
      state.bomA = LoadedFile('B.csv', doc('A'));
      state.runCheckNow();
      expect(state.report, isNull);
      expect(state.canExportReport, isFalse);
      for (var i = 0; i < 3000 && state.localBusy; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(
        state.localStatus,
        LocalStatus.done,
        reason: state.localErrorDetail,
      );
      expect(state.report!.localModel.kind, 'analysis');
      expect(state.report!.localModel.rows, 2);
      expect(state.report!.localModel.total, 2);
      expect(state.report!.localModel.calls, greaterThan(0));
      expect(state.report!.rows.every((r) => r.localNote.isNotEmpty), isTrue);
      expect(
        state.report!.rows.every(
          (r) =>
              r.referenceDifferences.length == 1 && !r.reasons.contains('col'),
        ),
        isTrue,
      );
      expect(state.canExportReport, isTrue);
      expect(state.report!.models, [language.name]);
      // ignore: avoid_print
      print(
        'REAL_LANGUAGE model=${language.id} selfTestMs=${state.localTestMillis} analysisMs=${state.localMillis} rows=${state.localRows} calls=${state.localCalls}',
      );
    },
    skip: present
        ? false
        : 'Set SMT_FAI_MODELS to a directory containing the language GGUF',
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
