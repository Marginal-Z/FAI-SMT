// The compare and AI pages load files, run, switch tabs, edit a row and
// respond to taps without errors, on a desktop window and a phone.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/app_state.dart';
import 'package:smt_fai/compare_session.dart';
import 'package:smt_fai/core/compare.dart';
import 'package:smt_fai/core/models.dart';
import 'package:smt_fai/core/settings.dart';
import 'package:smt_fai/main.dart';

Uint8List _read(String n) => Uint8List.fromList(File('samples/demo/$n').readAsBytesSync());

/// A second BOM with English headers in another order and a few changes.
Uint8List bomB() => Uint8List.fromList(utf8.encode([
      'Where,Item,Text,Usage',
      '"R1,R2,R3,R4,R5,R6",K1102-1020K0-001A,贴片电阻 10K ±1% 0402,6',
      '"C1,C2,C3,C4,C5,C6,C7",K1103-0104K0-001A,贴片电容 100nF 16V X7R 0402,7',
      'U5,K1101-1C302X-001A,贴片IC 主芯片 C302XS BGA128 Amlogic,1',
      'U9,K1101-WIFI02-001A,贴片模组 WiFi RTL8189FTV QFN,1',
    ].join('\n')));

AppState _state() => AppState(AppSettings(tourDone: true), Directory.systemTemp.path);

Future<void> _pump(WidgetTester tester, AppState state, Size size, {bool touch = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(SmtFaiApp(state: state, touch: touch));
  await tester.pumpAndSettle();
}

void main() {
  for (final (size, touch) in [(const Size(1500, 920), false), (const Size(390, 844), true)]) {
    testWidgets('BOM ↔ BOM: run, tabs, edit (${size.width.toInt()} wide)', (tester) async {
      final state = _state();
      final cmp = state.compare;
      cmp.load(CompareSlot.bomA, 'demo_T100_BOM.xlsx', _read('demo_T100_BOM.xlsx'));
      cmp.load(CompareSlot.bomB, 'b.csv', bomB());
      state.setModule(Module.compare);
      await _pump(tester, state, size, touch: touch);
      cmp.run();
      await tester.pumpAndSettle();
      final res = cmp.result!;
      expect(res.count(CheckCategory.ng), greaterThan(0));
      expect(res.rows.firstWhere((r) => r.cells['pnA'] == 'K1101-WIFI01-001A').reasons.map((e) => e.code), contains('cmp_pn_changed'));
      for (final t in [CompareTab.report, CompareTab.refs, CompareTab.columns, CompareTab.preview]) {
        cmp.setTab(t);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: t.name);
      }
      // Open the editor on the first row, change the note, save.
      final first = res.rows.first;
      await tester.tap(find.text(touch ? '1' : first.cells['pnA']!).first, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('保存'), findsWidgets);
      await tester.tap(find.text('保存').last, warnIfMissed: false);
      await tester.pumpAndSettle();
      cmp.setNote(first, 'ok');
      await tester.pumpAndSettle();
      expect(res.edited, 1);
      // Changing a column role re-runs the comparison and keeps the edit.
      final f = cmp.files[CompareSlot.bomB]!;
      final textCol = f.layout.columns.firstWhere((c) => c.header == 'Text').index;
      cmp.setRole(CompareSlot.bomB, textCol, f.layout.columns.firstWhere((c) => c.index == textCol).role);
      await tester.pumpAndSettle();
      expect(cmp.result!.rows.first.note, 'ok');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('BOM ↔ stations A+B and single list', (tester) async {
    final state = _state();
    final cmp = state.compare;
    cmp.setMode(CompareMode.bomStationAB);
    cmp.load(CompareSlot.bomA, 'demo_T100_BOM.xlsx', _read('demo_T100_BOM.xlsx'));
    cmp.load(CompareSlot.stationA, 'a.xlsx', _read('demo_station_A.xlsx'));
    cmp.load(CompareSlot.stationB, 'b.xlsx', _read('demo_station_B.xlsx'));
    state.setModule(Module.compare);
    await _pump(tester, state, const Size(1500, 920));
    cmp.run();
    await tester.pumpAndSettle();
    // Same engine as the BOM check page, so the same areas.
    state.load(InputKind.bom, 'demo_T100_BOM.xlsx', _read('demo_T100_BOM.xlsx'));
    state.load(InputKind.stationA, 'a.xlsx', _read('demo_station_A.xlsx'));
    state.load(InputKind.stationB, 'b.xlsx', _read('demo_station_B.xlsx'));
    state.runCheckNow();
    state.setModule(Module.compare);
    for (final cat in CheckCategory.values) {
      expect(cmp.result!.count(cat), state.report!.count(cat), reason: cat.name);
    }
    cmp.setMode(CompareMode.bomStation);
    cmp.load(CompareSlot.station, 'a.xlsx', _read('demo_station_A.xlsx'));
    cmp.run();
    await tester.pumpAndSettle();
    cmp.setTab(CompareTab.report);
    await tester.pumpAndSettle();
    expect(cmp.result!.mode, CompareMode.bomStation);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI page: files, unconfigured connection, never touches the local result', (tester) async {
    final state = _state();
    state.ai.addFile('demo_T100_BOM.xlsx', _read('demo_T100_BOM.xlsx'));
    state.setModule(Module.ai);
    await _pump(tester, state, const Size(1500, 920));
    expect(find.text('demo_T100_BOM.xlsx'), findsOneWidget);
    await tester.tap(find.text('开始 AI 核对'), warnIfMissed: false);
    await tester.pumpAndSettle();
    // No API key: an error message, no request.
    expect(find.textContaining('API Key'), findsWidgets);
    expect(state.ai.running, isFalse);
    expect(state.report, isNull);
    expect(state.compare.result, isNull);
    await tester.tap(find.text('确定').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    await _pump(tester, state, const Size(390, 844), touch: true);
    expect(tester.takeException(), isNull);
  });
}
