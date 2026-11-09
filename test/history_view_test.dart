// Check history in the app: a finished check is kept, listed, opened and
// checked again from its stored files; the check settings page responds.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/app_state.dart';
import 'package:smt_fai/core/bom_compare.dart';
import 'package:smt_fai/core/history.dart';
import 'package:smt_fai/core/settings.dart';
import 'package:smt_fai/main.dart';
import 'package:smt_fai/core/local_ai/model_store.dart';
import 'support/local_models.dart';

void main() {
  testWidgets('a check is kept, listed and loaded again', (tester) async {
    final dir = Directory.systemTemp.createTempSync('smtfai-hview');
    addTearDown(() => dir.deleteSync(recursive: true));
    final state = (await tester.runAsync(() async => AppState(AppSettings(tourDone: true, language: 'zh'), dir.path, history: HistoryStore('${dir.path}/history'), localModelsFactory: (_, _) async => FakeLocalModels())))!;
    state.modelStatus[state.localAnalysisModel.id] = const ModelStatus(ModelState.ready);
    Uint8List read(String n) => Uint8List.fromList(File('samples/demo/$n').readAsBytesSync());
    state.load(InputKind.single, 'demo_A_BOM.xlsx', read('demo_A_BOM.xlsx'));
    state.load(InputKind.a, 'demo_B_BOM.xlsx', read('demo_B_BOM.xlsx'));
    // Writing the entry is real file work, outside the test clock.
    await tester.runAsync(() async {
      state.runCheckNow();
      await settleLocal(state);
      for (var i = 0; i < 300 && state.historyEntries.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    final ng = state.report!.count(CheckStatus.ng);
    expect(state.historyEntries, hasLength(1), reason: '${state.historyError} / ${state.localErrorDetail}');
    expect(state.historyEntries.single.counts['ng'], ng);
    expect(state.historyEntries.single.files.map((f) => f.role), ['A', 'B']);

    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    state.openSettings(SettingsSection.history);
    await tester.runAsync(() => tester.pumpWidget(SmtFaiApp(state: state)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(find.textContaining('demo_A_BOM.xlsx'), findsWidgets);

    // Open the entry and load it again.
    await tester.tap(find.textContaining('A: demo_A_BOM.xlsx'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(find.text('重新载入并核对'), findsOneWidget);
    state.unload(InputKind.single);
    await tester.runAsync(() => state.reopenHistory(state.historyEntries.single));
    await tester.runAsync(() => settleLocal(state));
    await tester.pump();
    expect(state.single?.name, 'demo_A_BOM.xlsx');
    expect(state.report!.count(CheckStatus.ng), ng);
    expect(state.settingsOpen, isFalse);
  });

  testWidgets('the check settings page switches fields off', (tester) async {
    final state = AppState(AppSettings(tourDone: true, language: 'zh'), Directory.systemTemp.createTempSync('smtfai-set').path);
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    state.openSettings(SettingsSection.checking);
    await tester.pumpWidget(SmtFaiApp(state: state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('用量').first);
    await tester.pumpAndSettle();
    expect(state.settings.compareSkip, {'quantity'});
    await tester.tap(find.text('NG').first);
    await tester.pumpAndSettle();
    expect(state.settings.reportStatuses, {'ng'});
  });
}
