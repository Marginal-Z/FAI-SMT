import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/app_state.dart';
import 'package:smt_fai/core/bom_compare.dart';
import 'package:smt_fai/core/local_ai/local_ai.dart';
import 'package:smt_fai/core/local_ai/model_store.dart';
import 'package:smt_fai/core/local_ai/semantic_match.dart';
import 'package:smt_fai/core/settings.dart';
import 'package:smt_fai/services/key_store.dart';

import 'support/local_models.dart';

class LanguageStore extends ModelStore {
  LanguageStore(super.dir);
  @override
  Future<ModelStatus> status(LocalModelSpec spec) async => ModelStatus(
    spec.role == LocalModelRole.language
        ? ModelState.ready
        : ModelState.missing,
  );
}

void main() {
  late Directory dir;
  late FakeLocalModels model;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('required-local-');
    model = FakeLocalModels();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('embeddings alone cannot produce local results', () {
    final s = localState(dir.path, model, ready: false);
    s.modelStatus[s.activeEmbedding.id] = const ModelStatus(ModelState.ready);
    expect(s.localModelsReady, isTrue);
    expect(
      () => s.runCheckNow(),
      throwsA(
        isA<UserMessage>().having(
          (e) => e.key,
          'key',
          'local_analysis_missing',
        ),
      ),
    );
    expect(s.report, isNull);
    expect(s.canExportReport, isFalse);
    expect(s.localStatus, LocalStatus.unavailable);
    expect(model.calls, 0);
  });
  test(
    'startup restores the language model; saved OFF cannot bypass it',
    () async {
      final s = AppState(
        AppSettings(localAiEnabled: false),
        dir.path,
        models: LanguageStore(dir.path),
        keys: MemoryKeyStore(),
        localModelsFactory: (_, _) async => model,
      );
      await s.initialize();
      expect(s.localAnalysisReady, isTrue);
      expect(s.localModelsReady, isFalse);
      s.single = LoadedFile('A.csv', localDoc('S'));
      s.bomA = LoadedFile('B.csv', localDoc('A'));
      s.runCheckNow();
      await settleLocal(s);
      expect(s.localStatus, LocalStatus.done);
      expect(s.report!.localModel.kind, 'analysis');
      expect(model.calls, greaterThan(0));
      expect(model.embeddings, 0);
      expect(s.canExportReport, isTrue);
    },
  );
  test(
    'even identical BOMs need language decisions for every PASS row',
    () async {
      final s = localState(dir.path, model, count: 9)..runCheckNow();
      expect(s.report, isNull);
      await settleLocal(s);
      expect(s.report!.count(CheckStatus.pass), 9);
      expect(model.prompts.expand((p) => p), hasLength(9));
      expect(model.calls, 3);
      expect(model.embeddings, 0);
      expect(
        s.report!.rows.every(
          (r) => r.localNote.isNotEmpty && r.basis.kinds.contains('local_ai'),
        ),
        isTrue,
      );
      expect(s.report!.localModel.rows, 9);
      expect(s.report!.localModel.total, 9);
      expect(s.report!.localModel.calls, 3);
      expect(s.report!.models, [s.localAnalysisModel.name]);
    },
  );
  test('pending analysis exposes neither results nor export', () async {
    model.pending = Completer<Map<String, dynamic>>();
    final s = localState(dir.path, model)..runCheckNow();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(s.localStatus, LocalStatus.running);
    expect(s.report, isNull);
    expect(s.canExportReport, isFalse);
    s.setCheckMode(CheckMode.cloudFull);
    expect(s.settings.checkMode, CheckMode.local);
    model.pending!.complete(model.answer(model.prompts.single));
    await settleLocal(s);
    expect(s.canExportReport, isTrue);
  });
  test('failed inference never falls back to rules-only output', () async {
    for (final failure in [
      LocalAiException('timeout'),
      StateError('runtime failed'),
    ]) {
      model.failure = failure;
      final s = localState(dir.path, model)..runCheckNow();
      await settleLocal(s);
      expect(s.localStatus, LocalStatus.failed);
      expect(s.report, isNull);
      expect(s.canExportReport, isFalse);
      expect(s.statusKey, 'status_local_required_failed');
      expect(s.localError, isNotEmpty);
    }
  });
  test(
    'missing, duplicate or foreign answers prevent the entire report',
    () async {
      for (final kind in ['missing', 'duplicate', 'foreign']) {
        model = FakeLocalModels()
          ..respond = (rows) => {
            'rows': kind == 'missing'
                ? []
                : [
                    for (final _ in rows)
                      {
                        'id': kind == 'foreign' ? 'outside' : rows.first['id'],
                        'verdict': 'pass',
                        'reason': 'invalid',
                      },
                    if (kind == 'duplicate')
                      {
                        'id': rows.first['id'],
                        'verdict': 'pass',
                        'reason': 'duplicate',
                      },
                  ],
          };
        final s = localState(dir.path, model)..runCheckNow();
        await settleLocal(s);
        expect(s.report, isNull);
        expect(s.localError, 'local_err_incomplete');
      }
    },
  );
  test('bad batches split; each completed item is counted once', () async {
    model.respond = (rows) =>
        rows.length > 1 ? {'rows': []} : model.answer(rows);
    final s = localState(dir.path, model, count: 3)..runCheckNow();
    await settleLocal(s);
    expect(s.report!.complete, isTrue);
    expect(s.localRows, 3);
    expect(s.localCalls, 5);
    expect(s.canExportReport, isTrue);
  });
  test(
    'model PASS cannot override measured quantity and ref conflicts',
    () async {
      final s = localState(dir.path, model, conflict: true)..runCheckNow();
      await settleLocal(s);
      final row = s.report!.rows.firstWhere((r) => r.partNo == 'P1001');
      expect(row.status, CheckStatus.ng);
      expect(row.reasons, contains('local_ai_contradicted'));
    },
  );
  test('the model can independently stop an otherwise PASS row', () async {
    model.respond = (rows) => {
      'rows': [
        for (final r in rows)
          {'id': r['id'], 'verdict': 'review', 'reason': '型号信息不足'},
      ],
    };
    final s = localState(dir.path, model)..runCheckNow();
    await settleLocal(s);
    expect(s.report!.count(CheckStatus.pass), 0);
    expect(s.report!.count(CheckStatus.review), 2);
    expect(s.report!.rows.first.localNote, '型号信息不足');
  });
  test('reload and cancellation discard stale model output', () async {
    for (final cancel in [false, true]) {
      model = FakeLocalModels()..pending = Completer<Map<String, dynamic>>();
      final s = localState(dir.path, model)..runCheckNow();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (cancel) {
        s.cancelLocalAnalysis();
      } else {
        s.clearAll();
      }
      model.pending!.complete(model.answer(model.prompts.single));
      await settleLocal(s);
      expect(s.report, isNull);
      expect(s.canExportReport, isFalse);
      expect(s.localStatus, LocalStatus.idle);
    }
  });
  test('language self-test performs structured inference without publishing BOM results', () async {
    final s = localState(dir.path, model);
    await s.testLocalModel();
    expect(model.calls, 1);
    expect(model.embeddings, 0);
    expect(s.localTestKey, 'local_test_ok');
    expect(s.report, isNull);
    expect(s.canExportReport, isFalse);
    s.runCheckNow();
    await settleLocal(s);
    final recorded = s.report!.localModel.toJson();
    await s.testLocalModel();
    expect(s.report!.localModel.toJson(), recorded);
  });
  test('rapid hybrid preference writes preserve the final choice', () async {
    final s = localState(dir.path, model);
    s.settings.checkMode = CheckMode.hybrid;
    final saves = <Future<void>>[];
    for (var i = 0; i < 20; i++) {
      s.settings.embeddingModel =
          embeddingModels[i % embeddingModels.length].id;
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
  });
  test('invalid vectors remain rejected for optional hybrid candidates', () {
    for (final v in <List<List<double>>>[
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
        () => checkedVectors(v, v.isEmpty ? 1 : v.length),
        throwsA(isA<LocalAiException>()),
      );
    }
  });
}
