import 'dart:async';
import 'dart:convert';
import 'package:smt_fai/core/cloud/provider.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/app_state.dart';
import 'package:smt_fai/core/bom.dart';
import 'package:smt_fai/core/bom_compare.dart';
import 'package:smt_fai/core/local_ai/local_ai.dart';
import 'package:smt_fai/core/local_ai/model_store.dart';
import 'package:smt_fai/core/local_ai/semantic_match.dart';
import 'package:smt_fai/core/settings.dart';
import 'package:smt_fai/services/key_store.dart';

// Optional embedding behavior now belongs to HYBRID; local mode's
// mandatory language-model gate is exercised by local_required_test.dart.
class EmbeddingState extends AppState {
  EmbeddingState(super.settings, super.settingsDir, {super.models, super.keys, super.localModelsFactory}) {
    settings.checkMode = CheckMode.hybrid;
  }
  @override
  bool get cloudReady => true;
  @override
  CloudProvider get cloudProvider => CandidateCloud();
}

class CandidateCloud implements CloudProvider {
  @override
  String get name => 'test';
  @override
  String get model => 'candidate-test';
  @override
  Future<CloudReply> ask({required String system, required String user, required Map<String, dynamic> schema, int maxTokens = 4096, CloudCancel? cancel}) async {
    final items = jsonDecode(user) as List;
    return CloudReply({'answers': [for (final it in items) {'id': (it as Map)['id'], 'same': 'unsure', 'reason': 'Review'}]}, Usage(requests: 1), model);
  }
}

class FakeModels implements LocalModels {
  int calls = 0;
  int disposals = 0;
  Object? failure;
  Completer<List<List<double>>>? pending;
  @override
  String get languageModel => 'test';
  @override
  Future<List<List<double>>> embed(List<String> texts) async {
    calls++;
    if (failure != null) throw failure!;
    return pending?.future ??
        [
          for (final _ in texts) [2, 0],
        ];
  }

  @override
  Future<Map<String, dynamic>> structured({
    required String system,
    required String user,
    required Map<String, dynamic> schema,
    int maxTokens = 600,
  }) async => {};
  @override
  Future<void> dispose() async { disposals++; }
}

class ReadyStore extends ModelStore {
  ReadyStore(super.dir);
  @override
  Future<ModelStatus> status(LocalModelSpec spec) async => ModelStatus(spec.id == embeddingModels.first.id ? ModelState.ready : ModelState.missing);
}

BomDocument input(String id, List<String> names) => BomDocument(
  id: id,
  file: '$id.csv',
  sheet: 's',
  headerRow: 0,
  columns: [
    BomColumn(0, 'PN', BomRole.partNo),
    BomColumn(1, 'Description', BomRole.description),
  ],
  warnings: [],
  records: [
    for (var i = 0; i < names.length; i++)
      BomRecord(
        id: '$id:$i',
        sources: [SourceRef('$id.csv', 's', i + 2)],
        cells: [],
        partNo: names[i],
        description: 'opaque component',
        quantity: null,
        refs: [],
        extra: {},
      ),
  ],
);

Future<void> settle(AppState s) async {
  for (var i = 0; i < 500 && s.localBusy; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(s.localBusy, isFalse);
}

void main() {
  late Directory dir;
  late FakeModels fake;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('local-usage-');
    fake = FakeModels();
  });
  tearDown(() => dir.deleteSync(recursive: true));
  AppState state({bool enabled = true, bool ready = true, bool same = false}) {
    final s = EmbeddingState(
      AppSettings(localAiEnabled: enabled),
      dir.path,
      localModelsFactory: (_, _) async => fake,
    );
    if (ready) {
      s.modelStatus[s.activeEmbedding.id] = const ModelStatus(ModelState.ready);
    }
    s.single = LoadedFile('S.csv', input('S', ['P1001']));
    s.bomA = LoadedFile('A.csv', input('A', [same ? 'P1001' : 'Q1001']));
    return s;
  }
  test('startup restores enabled model availability without opening settings', () async {
    final s = state(same: true);
    final reopened = EmbeddingState(AppSettings.fromJson(s.settings.toJson()), dir.path, models: ReadyStore(dir.path), keys: MemoryKeyStore());
    expect(reopened.localModelsReady, isFalse);
    await reopened.initialize();
    expect(reopened.settings.localAiEnabled, isTrue);
    expect(reopened.localModelsReady, isTrue);
    reopened.single = s.single;
    reopened.bomA = s.bomA;
    reopened.runCheckNow();
    expect(reopened.localStatus, LocalStatus.notNeeded);
  });

  test(
    'disabled, unavailable and not-needed are distinct, with no inference',
    () {
      for (final (enabled, ready, same, status) in [
        (false, true, false, LocalStatus.disabled),
        (true, false, false, LocalStatus.unavailable),
        (true, true, true, LocalStatus.notNeeded),
      ]) {
        final s = state(enabled: enabled, ready: ready, same: same)
          ..runCheckNow();
        expect(s.localStatus, status);
        expect(s.report!.localModel.state, status.name);
        expect(s.report!.models, isEmpty);
      }
      expect(fake.calls, 0);
    },
  );
  test('one-sided unmatched does not claim the model ran', () {
    final s = state();
    s.bomA = LoadedFile('A.csv', input('A', []));
    s.runCheckNow();
    expect(s.localStatus, LocalStatus.notNeeded);
    expect(fake.calls, 0);
  });
  test('real call path records texts, pairs, model and final REVIEW', () async {
    final s = state()..runCheckNow();
    expect(s.report!.complete, isFalse);
    await settle(s);
    expect(fake.calls, 1);
    expect(s.localStatus, LocalStatus.done);
    expect(s.report!.localModel.texts, 2);
    expect(s.report!.localModel.paired, 1);
    expect(s.report!.models, [s.activeEmbedding.name, '${s.settings.cloud.kind.name} ${s.settings.cloud.modelName}']);
    expect(s.report!.rows.single.status, CheckStatus.review);
    expect(s.report!.complete, isTrue);
  });
  test(
    'unexpected runtime errors remain visible and keep rule results',
    () async {
      fake.failure = StateError('native failure');
      final s = state()..runCheckNow();
      await settle(s);
      expect(s.localStatus, LocalStatus.failed);
      expect(s.report!.localModel.state, 'failed');
      expect(s.report!.count(CheckStatus.unmatched), 2);
      expect(s.report!.models, isNot(contains(s.activeEmbedding.name)));
    },
  );
  test(
    'reloading during inference discards stale results and progress',
    () async {
      fake.pending = Completer();
      final s = state()..runCheckNow();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      s.clearAll();
      fake.pending!.complete([
        [1, 0],
        [1, 0],
      ]);
      await settle(s);
      expect(s.report, isNull);
      expect(s.localStatus, LocalStatus.idle);
      expect(s.localTexts, 0);
    },
  );
  test('self-test runs inference without claiming the BOM used it', () async {
    final s = state(same: true)..runCheckNow();
    await s.testLocalModel();
    expect(fake.calls, 1);
    expect(s.localTestKey, 'local_test_ok');
    expect(s.report!.localModel.state, 'notNeeded');
    expect(s.report!.models, isNot(contains(s.activeEmbedding.name)));
  });
  test('model selection changes the next engine and preserves recorded usage', () async {
    final opened = <String>[];
    final second = FakeModels();
    final s = EmbeddingState(AppSettings(localAiEnabled: true), dir.path,
      localModelsFactory: (_, spec) async {
        opened.add(spec.id);
        return opened.length == 1 ? fake : second;
      });
    for (final m in embeddingModels.take(2)) {
      s.modelStatus[m.id] = const ModelStatus(ModelState.ready);
    }
    s.single = LoadedFile('S.csv', input('S', ['P1001']));
    s.bomA = LoadedFile('A.csv', input('A', ['Q1001']));
    s.runCheckNow();
    await settle(s);
    final usage = s.report!.localModel.toJson();
    await s.setEmbeddingModel(embeddingModels[1]);
    expect(fake.disposals, 1);
    expect(s.report!.localModel.toJson(), usage);
    expect(s.activeEmbedding.id, embeddingModels[1].id);
    await s.testLocalModel();
    expect(opened, [embeddingModels[0].id, embeddingModels[1].id]);
    expect(second.calls, 1);
    final saved = await AppSettings.load(dir.path);
    expect(saved.embeddingModel, embeddingModels[1].id);
    expect(saved.localAiEnabled, isTrue);
  });
  test('busy inference rejects model and enable changes', () async {
    fake.pending = Completer<List<List<double>>>();
    final s = state();
    final original = s.activeEmbedding.id;
    final test = s.testLocalModel();
    await s.setEmbeddingModel(embeddingModels[1]);
    s.setLocalAiEnabled(false);
    expect(s.activeEmbedding.id, original);
    expect(s.settings.localAiEnabled, isTrue);
    fake.pending!.complete([[1, 0], [1, 0]]);
    await test;
    expect(s.localTestKey, 'local_test_ok');
  });
  test('rapid model and switch changes persist the latest valid settings', () async {
    final s = state();
    final saves = <Future<void>>[];
    for (var i = 0; i < 20; i++) {
      s.settings.embeddingModel = embeddingModels[i % embeddingModels.length].id;
      s.setLocalAiEnabled(i.isEven);
      saves.add(s.persist());
    }
    await Future.wait(saves);
    await s.setEmbeddingModel(embeddingModels[1]);
    s.setLocalAiEnabled(false);
    await s.persist();
    final saved = await AppSettings.load(dir.path);
    expect(saved.embeddingModel, embeddingModels[1].id);
    expect(saved.localAiEnabled, isFalse);
    expect(saved.tourDone, s.settings.tourDone);
  });
  test(
    'native vectors must have consistent finite, nonzero values and count',
    () {
      for (final vectors in <List<List<double>>>[
        [],
        [
          [0, 0],
        ],
        [
          [double.nan],
        ],
        [
          [1],
          [1, 2],
        ],
      ]) {
        expect(
          () => checkedVectors(vectors, vectors.isEmpty ? 1 : vectors.length),
          throwsA(isA<LocalAiException>()),
        );
      }
      expect(
        checkedVectors([
          [3, 4],
        ], 1).single,
        [0.6, 0.8],
      );
    },
  );
  test('reverse ambiguity cannot be accepted as a semantic pairing', () async {
    final first = compareBoms(
      input('S', ['P1001', 'P1002']),
      input('A', ['Q1001']),
      null,
    );
    expect(await semanticSuggestions(first, fake), isEmpty);
  });
}
