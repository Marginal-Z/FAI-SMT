import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/app_state.dart';
import 'package:smt_fai/core/bom.dart';
import 'package:smt_fai/core/bom_compare.dart';
import 'package:smt_fai/core/local_ai/model_store.dart';
import 'package:smt_fai/core/settings.dart';

void main() {
  final modelDir = Platform.environment['SMT_FAI_MODELS'];
  test('real GGUF self-test and BOM inference leave verifiable evidence', () async {
    final dir = Directory.systemTemp.createTempSync('real-model-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final spec = embeddingModels.firstWhere((m) => m.id == 'granite-embedding-107m-q8');
    final s = AppState(AppSettings(localAiEnabled: true, embeddingModel: spec.id), dir.path, models: ModelStore('${dir.path}/models', bundledDir: modelDir));
    await s.refreshModels();
    expect(s.localModelsReady, isTrue);
    await s.testLocalModel();
    expect(s.localTestKey, 'local_test_ok', reason: s.localTestDetail);
    BomDocument doc(String id) => BomDocument(id: id, file: '$id.csv', sheet: 's', headerRow: 0,
      columns: [BomColumn(0, 'PN', BomRole.partNo), BomColumn(1, 'Description', BomRole.description)], warnings: [],
      records: [BomRecord(id: '$id:1', sources: [SourceRef('$id.csv', 's', 2)], cells: [], partNo: '${id}1001', description: '贴片电阻', quantity: null, refs: [], extra: {}, kind: ItemKind.resistor)]);
    s.single = LoadedFile('S.csv', doc('S'));
    s.bomA = LoadedFile('A.csv', doc('A'));
    s.runCheckNow();
    for (var i = 0; i < 1800 && s.localBusy; i++) { await Future<void>.delayed(const Duration(milliseconds: 100)); }
    expect(s.localStatus, LocalStatus.done, reason: s.localError);
    expect(s.report!.localModel.texts, 2);
    expect(s.report!.localModel.paired, 1);
    expect(s.report!.rows.single.status, CheckStatus.review);
    expect(s.report!.models, [spec.name]);
    // ignore: avoid_print
    print('REAL_INFERENCE model=${spec.id} selfTestMs=${s.localTestMillis} checkMs=${s.localMillis} texts=${s.localTexts} paired=${s.localPaired}');
  }, skip: modelDir == null ? 'Set SMT_FAI_MODELS to run actual GGUF inference' : false, timeout: const Timeout(Duration(minutes: 5)));
}
