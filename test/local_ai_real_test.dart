// The real local models, where they are on this machine (never on CI):
// set SMT_FAI_MODELS to their folder, or keep them in
// ~/.cache/smt-fai-dev/models.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/app_state.dart';
import 'package:smt_fai/core/bom_compare.dart';
import 'package:smt_fai/core/settings.dart';
import 'package:smt_fai/core/local_ai/local_ai.dart';
import 'package:smt_fai/core/local_ai/model_store.dart';

String get modelDir => Platform.environment['SMT_FAI_MODELS'] ?? '${Platform.environment['HOME']}/.cache/smt-fai-dev/models';

double _dot(List<double> a, List<double> b) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}

void main() {
  bool has(LocalModelSpec m) => File('$modelDir/${m.file}').existsSync();
  final present = has(embeddingModels.first) && has(modelFor(LocalModelRole.language));
  final skip = present ? null : 'local models not present';
  late LlamaLocalModels ai;

  setUpAll(() {
    if (!present) return;
    ai = LlamaLocalModels(embeddingPath: '$modelDir/${embeddingModels.first.file}', languagePath: '$modelDir/${modelFor(LocalModelRole.language).file}');
  });
  tearDownAll(() async {
    if (present) await ai.dispose();
  });

  // Every embedding model offered, where it is on disk.
  for (final m in embeddingModels) {
    test('vectors (${m.name}): the same part in two languages is closer than another part', () async {
      final e = LlamaLocalModels(embeddingPath: '$modelDir/${m.file}', languagePath: '', embeddingPrefix: m.prefix);
      try {
        final v = await e.embed(['贴片电阻 10K ±1% 0402', 'Chip resistor 10kΩ 1% 0402', '贴片电容 100nF 16V 0402']);
        expect(v, hasLength(3));
        expect(_dot(v[0], v[0]), closeTo(1, 1e-3));
        expect(_dot(v[0], v[1]), greaterThan(_dot(v[0], v[2])));
      } finally {
        await e.dispose();
      }
    }, skip: has(m) ? null : 'not present', timeout: const Timeout(Duration(minutes: 5)));
  }

  test('structured answer follows the schema', () async {
    final r = await ai.structured(
      system: 'Classify the electronic component.',
      user: 'MLCC 100nF 16V X7R 0402',
      schema: const {
        'type': 'object',
        'properties': {
          'kind': {'type': 'string', 'enum': ['resistor', 'capacitor', 'inductor', 'other']},
        },
        'required': ['kind'],
        'additionalProperties': false,
      },
      maxTokens: 40,
    );
    // Answer quality is measured by tool/bench_local_ai.dart; here only
    // that the reply keeps to the schema.
    expect(['resistor', 'capacitor', 'inductor', 'other'], contains(r['kind']));
    expect(r.keys, ['kind']);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 5)));

  test('the check uses the local model and stays complete', () async {
    final state = AppState(AppSettings(localAiEnabled: true), Directory.systemTemp.path, models: ModelStore('${Directory.systemTemp.path}/smt-fai-test-models', bundledDir: modelDir));
    await state.refreshModels();
    expect(state.localModelsReady, isTrue);
    Uint8List read(String n) => Uint8List.fromList(File('samples/demo/$n').readAsBytesSync());
    state.load(InputKind.single, 'demo_A_BOM.xlsx', read('demo_A_BOM.xlsx'));
    state.load(InputKind.a, 'demo_B_BOM.xlsx', read('demo_B_BOM.xlsx'));
    state.runCheckNow();
    for (var i = 0; i < 600 && state.localStatus == LocalStatus.running; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(state.localStatus, LocalStatus.done);
    expect(state.report!.complete, isTrue);
    // A model suggestion never makes a line PASS.
    expect(state.report!.rows.where((r) => r.basis.kinds.contains('semantic')).every((r) => r.status != CheckStatus.pass), isTrue);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 5)));

  test('a missing model is an error, not a silent fallback', () async {
    final missing = LlamaLocalModels(embeddingPath: '/nonexistent/e.gguf', languagePath: '/nonexistent/l.gguf');
    await expectLater(missing.embed(['x']), throwsA(isA<LocalAiException>().having((e) => e.code, 'code', 'load_failed')));
    await missing.dispose();
  }, skip: skip);
}
