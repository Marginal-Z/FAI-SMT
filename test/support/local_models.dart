import 'dart:async';
import 'dart:convert';

import 'package:smt_fai/app_state.dart';
import 'package:smt_fai/core/bom.dart';
import 'package:smt_fai/core/local_ai/local_ai.dart';
import 'package:smt_fai/core/local_ai/model_store.dart';
import 'package:smt_fai/core/settings.dart';
import 'package:smt_fai/core/table_reader.dart';

class FakeLocalModels implements LocalModels {
  int calls = 0, embeddings = 0, disposals = 0;
  Object? failure;
  Completer<Map<String, dynamic>>? pending;
  final prompts = <List<Map<String, dynamic>>>[];
  Map<String, dynamic> Function(List<Map<String, dynamic>>)? respond;
  @override
  String get languageModel => 'test language model';
  Map<String, dynamic> answer(List<Map<String, dynamic>> rows) => {
    'rows': [
      for (final row in rows)
        {'id': row['id'], 'verdict': 'pass', 'reason': '已逐项比对'},
    ],
  };
  @override
  Future<Map<String, dynamic>> structured({
    required String system,
    required String user,
    required Map<String, dynamic> schema,
    int maxTokens = 600,
  }) async {
    calls++;
    if (failure != null) throw failure!;
    if ((schema['properties'] as Map).containsKey('ok')) return {'ok': true};
    final rows = (jsonDecode(user)['rows'] as List)
        .cast<Map<String, dynamic>>();
    prompts.add(rows);
    return pending?.future ?? respond?.call(rows) ?? answer(rows);
  }

  @override
  Future<List<List<double>>> embed(List<String> texts) async {
    embeddings++;
    return [
      for (final _ in texts) [1, 0],
    ];
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

BomDocument localDoc(String id, {int count = 2, bool conflict = false}) =>
    readBom([
      Grid('s', [
        ['料号', '描述', '用量', '位号'],
        for (var i = 1; i <= count; i++)
          [
            'P${1000 + i}',
            i == 1 ? 'LED red 0603' : 'Chip resistor 10k 0603',
            conflict && i == 1 ? '2' : '1',
            conflict && i == 1
                ? 'D1,D2'
                : i == 1
                ? 'D1'
                : 'R$i',
          ],
      ]),
    ], id: id);

AppState localState(
  String dir,
  FakeLocalModels model, {
  bool ready = true,
  int count = 2,
  bool conflict = false,
}) {
  final state = AppState(
    AppSettings(tourDone: true, localAiEnabled: false),
    dir,
    localModelsFactory: (_, spec) async {
      if (spec.role != LocalModelRole.language) {
        throw StateError('Expected language model');
      }
      return model;
    },
  );
  if (ready) {
    state.modelStatus[state.localAnalysisModel.id] = const ModelStatus(
      ModelState.ready,
    );
  }
  state.single = LoadedFile('A.csv', localDoc('S', count: count));
  state.bomA = LoadedFile(
    'B.csv',
    localDoc('A', count: count, conflict: conflict),
  );
  return state;
}

Future<void> settleLocal(AppState state) async {
  for (var i = 0; i < 1000 && state.localBusy; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
