// Phone layout: every page, tab, settings page, toolbar button, menu and
// dialog must respond to taps without errors.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/app_state.dart';
import 'package:smt_fai/core/settings.dart';
import 'package:smt_fai/main.dart';
import 'package:smt_fai/ui/widgets.dart';

Finder _tip(String t) => find.byWidgetPredicate((w) => w is Hoverable && w.tooltip == t);

AppState _loaded() {
  final state = AppState(AppSettings(tourDone: true), Directory.systemTemp.path);
  List<int> read(String n) => File('samples/demo/$n').readAsBytesSync();
  state.load(InputKind.bom, 'demo_T100_BOM.xlsx', Uint8List.fromList(read('demo_T100_BOM.xlsx')));
  state.load(InputKind.stationA, 'demo_station_A.xlsx', Uint8List.fromList(read('demo_station_A.xlsx')));
  state.load(InputKind.stationB, 'demo_station_B.xlsx', Uint8List.fromList(read('demo_station_B.xlsx')));
  state.load(InputKind.coords, 'demo_coordinates.csv', Uint8List.fromList(read('demo_coordinates.csv')));
  state.runCheckNow();
  return state;
}

Future<void> _phone(WidgetTester tester, AppState state, {Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(SmtFaiApp(state: state, touch: true));
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final f = find.text(text);
  expect(f, findsWidgets, reason: text);
  await tester.ensureVisible(f.first);
  await tester.pumpAndSettle();
  await tester.tap(f.first, warnIfMissed: false);
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [const Size(390, 844), const Size(800, 1280)]) {
    testWidgets('tabs, settings and back respond (${size.width.round()} wide)', (tester) async {
      final state = _loaded();
      await _phone(tester, state, size: size);
      for (final (label, mod) in [('CAD 坐标', Module.cad), ('PCB 导航图', Module.board), ('BOM 核对', Module.check)]) {
        await _tapText(tester, label);
        expect(state.module, mod);
        expect(state.settingsOpen, isFalse);
      }
      await _tapText(tester, '设置');
      expect(state.settingsOpen, isTrue);
      for (final page in ['外观', '导航图配色', '核对规则', '元件库', '使用说明', '关于']) {
        await _tapText(tester, page);
        expect(state.settingsSection, isNotNull, reason: page);
        // Back to the list.
        await tester.tap(find.text('设置').first, warnIfMissed: false);
        await tester.pumpAndSettle();
        if (state.settingsSection != null) state.setSettingsSection(null);
        await tester.pumpAndSettle();
      }
      await _tapText(tester, 'BOM 核对');
      expect(state.settingsOpen, isFalse);
    });
  }

  testWidgets('check page: rows, sheet, filters and menus respond', (tester) async {
    final state = _loaded();
    await _phone(tester, state);
    // Pick NG through the stat card, select a row, close the sheet.
    await _tapText(tester, 'NG');
    final row = state.report!.rows.firstWhere((r) => r.category.name == 'ng');
    await _tapText(tester, row.partNo);
    expect(state.selected, isNotNull);
    await tester.tap(_tip('关闭').first, warnIfMissed: false);
    await tester.pumpAndSettle();
    if (state.selected != null) state.select(null);
    await tester.pumpAndSettle();
    // A filter menu opens and closes.
    await _tapText(tester, '全部');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('CAD page and its format dialog respond', (tester) async {
    final state = _loaded();
    state.setModule(Module.cad);
    await _phone(tester, state);
    await _tapText(tester, 'mm');
    expect(state.settings.coordUnit.name, 'mm');
    expect(tester.takeException(), isNull);
  });

  testWidgets('PCB navigator tools respond', (tester) async {
    final state = _loaded();
    state.setModule(Module.board);
    await _phone(tester, state);
    final before = state.boardSide;
    await tester.tap(_tip('TOP 面').first, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(state.boardSide, isNot(before));
    expect(tester.takeException(), isNull);
  });

  testWidgets('first-run tour can be finished on a phone', (tester) async {
    final state = AppState(AppSettings(), Directory.systemTemp.path)..tourStep = 0;
    await _phone(tester, state);
    for (var i = 0; i < 40 && state.tourStep != null; i++) {
      Finder? f;
      for (final label in ['开始了解', '下一步', '开始使用']) {
        if (find.text(label).evaluate().isNotEmpty) f = find.text(label);
      }
      f ??= find.text('下一步');
      expect(f, findsWidgets, reason: 'step ${state.tourStep}');
      await tester.tap(f.last, warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
    }
    expect(state.tourStep, isNull);
    expect(state.settings.tourDone, isTrue);
  });

}
