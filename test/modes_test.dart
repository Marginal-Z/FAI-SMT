// The three check modes driven through the app state, with a local fake
// cloud: HYBRID completes, CLOUD_FULL shows nothing until the cloud has
// answered and nothing at all when it cannot.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/app_state.dart';
import 'package:smt_fai/core/bom_compare.dart';
import 'package:smt_fai/core/cloud/provider.dart';
import 'package:smt_fai/core/settings.dart';
import 'package:smt_fai/services/key_store.dart';

import 'support/fake_llm_server.dart';
import 'support/local_models.dart';
import 'package:smt_fai/core/local_ai/model_store.dart';

Future<AppState> _state(FakeLlmServer server, CheckMode mode) async {
  final state = AppState(
    AppSettings(checkMode: mode, cloud: ProviderConfig(kind: ProviderKind.custom, baseUrl: server.url, minIntervalMs: 0, maxRetries: 0)),
    Directory.systemTemp.path,
    keys: MemoryKeyStore(),
    localModelsFactory: (_, _) async => FakeLocalModels(),
  );
  state.modelStatus[state.localAnalysisModel.id] = const ModelStatus(ModelState.ready);
  await state.setCloudKey('k');
  Uint8List read(String n) => Uint8List.fromList(File('samples/demo/$n').readAsBytesSync());
  state.load(InputKind.single, 'demo_A_BOM.xlsx', read('demo_A_BOM.xlsx'));
  state.load(InputKind.a, 'demo_B_BOM.xlsx', read('demo_B_BOM.xlsx'));
  state.load(InputKind.b, 'demo_C_BOM.xlsx', read('demo_C_BOM.xlsx'));
  return state;
}

Future<void> _settle(AppState s) async {
  for (var i = 0; i < 300 && s.cloudRunning; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late FakeLlmServer server;
  setUp(() async => server = await FakeLlmServer.start());
  tearDown(() => server.close());

  test('HYBRID: local result, then the cloud for the unsettled lines', () async {
    server.fallback = (body) {
      final items = jsonDecode(((body['messages'] as List).last as Map)['content'] as String) as List;
      return FakeReply.openai({
        'answers': [for (final it in items) {'id': (it as Map)['id'], 'same': 'unsure', 'reason': '无法判断'}],
      });
    };
    final s = await _state(server, CheckMode.hybrid);
    s.runCheckNow();
    await _settle(s);
    expect(s.cloudRun!.complete, isTrue);
    expect(s.report!.complete, isTrue);
    // Unsure answers change nothing: the local results stand.
    expect(s.report!.count(CheckStatus.pass), 19);
    expect(s.report!.rows.where((r) => r.reasons.contains('cloud_unsure')), isNotEmpty);
  });

  test('CLOUD_FULL with the cloud down: no result, an error, never finished', () async {
    server.fallback = (_) => const FakeReply(503, {'error': 'down'});
    final s = await _state(server, CheckMode.cloudFull);
    s.runCheckNow();
    expect(s.report, isNull);
    await _settle(s);
    expect(s.report, isNull);
    expect(s.cloudError, 'err_cloud_server');
    expect(s.statusKey, 'status_cloud_failed');
  });

  test('LOCAL never calls the cloud', () async {
    final s = await _state(server, CheckMode.local);
    s.settings.aiEnabled = true;
    s.runCheckNow();
    await _settle(s);
    expect(server.requests, isEmpty);
    await settleLocal(s);
    await s.runAi();
    expect(server.requests, isEmpty);
    expect(s.report!.complete, isTrue);
  });

  test('HYBRID with no unsettled rows finishes without a cloud request', () async {
    final s = await _state(server, CheckMode.hybrid);
    final bytes = File('samples/demo/demo_A_BOM.xlsx').readAsBytesSync();
    s.load(InputKind.a, 'same.xlsx', bytes);
    s.unload(InputKind.b);
    s.runCheckNow();
    await _settle(s);
    expect(s.report!.complete, isTrue);
    expect(s.report!.pending, isFalse);
    expect(s.canExportReport, isTrue);
    expect(server.requests, isEmpty);
  });
}
