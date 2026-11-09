import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/core/local_ai/local_ai.dart';
import 'package:smt_fai/core/local_ai/model_store.dart';

void main() {
  test('same-length bundled corruption is rejected before native loading', () async {
    final dir = Directory.systemTemp.createTempSync('model-integrity-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final spec = LocalModelSpec(id: 'test', role: LocalModelRole.embedding, file: 'test.gguf', bytes: 4, sha256: sha256.convert([1,2,3,4]).toString(), urls: {}, name: 'test', license: 'test');
    await File('${dir.path}/test.gguf').writeAsBytes([4,3,2,1]);
    final store = ModelStore('${dir.path}/downloads', bundledDir: dir.path);
    expect((await store.status(spec)).state, ModelState.ready);
    await expectLater(LlamaLocalModels.open(store, embedding: spec), throwsA(isA<LocalAiException>().having((e) => e.code, 'code', 'model_hash')));
  });
}
