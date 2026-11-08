// Phone layout: the page, settings pages, result cards, the detail sheet,
// menus, the AI switch and the tour must respond to taps without errors.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/app_state.dart';
import 'package:smt_fai/core/bom_compare.dart';
import 'package:smt_fai/core/settings.dart';
import 'package:smt_fai/main.dart';
import 'package:smt_fai/ui/widgets.dart';

Finder _tip(String t) => find.byWidgetPredicate((w) => w is Hoverable && w.tooltip == t);

AppState _loaded({bool check = true}) {
  final state = AppState(AppSettings(tourDone: true), Directory.systemTemp.path);
  Uint8List read(String n) => Uint8List.fromList(File('samples/demo/$n').readAsBytesSync());
  state.load(InputKind.single, 'demo_A_BOM.xlsx', read('demo_A_BOM.xlsx'));
  state.load(InputKind.a, 'demo_B_BOM.xlsx', read('demo_B_BOM.xlsx'));
  state.load(InputKind.b, 'demo_C_BOM.xlsx', read('demo_C_BOM.xlsx'));
  if (check) state.runCheckNow();
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
    testWidgets('settings pages and back respond (${size.width.round()} wide)', (tester) async {
      final state = _loaded();
      await _phone(tester, state, size: size);
      await _tapText(tester, '设置');
      expect(state.settingsOpen, isTrue);
      for (final page in ['外观', 'AI 核对', '使用说明', '关于']) {
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
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('check page: stat cards, rows, sheet and menus respond', (tester) async {
    final state = _loaded();
    await _phone(tester, state);
    await _tapText(tester, 'NG');
    expect(state.filter, CheckStatus.ng);
    final row = state.visibleRows().first;
    await _tapText(tester, row.partNo);
    expect(state.selected, isNotNull);
    await tester.tap(_tip('关闭').first, warnIfMissed: false);
    await tester.pumpAndSettle();
    if (state.selected != null) state.select(null);
    await tester.pumpAndSettle();
    // The result menu opens and closes.
    await _tapText(tester, 'NG');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI switch opens the AI settings when no API is set', (tester) async {
    final state = _loaded();
    await _phone(tester, state);
    await _tapText(tester, 'AI 核对');
    expect(state.settingsOpen, isTrue);
    expect(state.settingsSection, SettingsSection.ai);
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
