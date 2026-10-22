// Renders the main window with the demo data to PNG files for visual review.
//
//   flutter test tool/screenshot_test.dart --update-goldens
//
// Output: tool/screens/*.png. Uses system Noto fonts (Linux).
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/app_state.dart';
import 'package:smt_fai/core/models.dart';
import 'package:smt_fai/core/settings.dart';
import 'package:smt_fai/main.dart';

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    final bytes = File(f).readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

void main() {
  setUpAll(() async {
    await _font('Noto Sans', ['/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf', '/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf']);
    // Unregistered fallback names resolve to the test font (boxes), so the
    // first CJK fallback name must be a registered family.
    for (final f in ['Microsoft YaHei UI', 'Noto Sans CJK SC']) {
      await _font(f, ['/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc', '/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc']);
    }
    await _font('Noto Sans Thai', ['/usr/share/fonts/truetype/noto/NotoSansThai-Regular.ttf', '/usr/share/fonts/truetype/noto/NotoSansThai-Bold.ttf']);
    await _font('DejaVu Sans Mono', ['/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf']);
    await _font('PhosphorRegular', ['assets/fonts/Phosphor-Regular.ttf']);
    await _font('PhosphorBold', ['assets/fonts/Phosphor-Bold.ttf']);
  });

  AppState demoState({String lang = 'zh', bool dark = true}) {
    final state = AppState(AppSettings(language: lang, theme: dark ? ThemePref.dark : ThemePref.light), Directory.systemTemp.path);
    List<int> read(String n) => File('samples/demo/$n').readAsBytesSync();
    state.load(InputKind.bom, 'demo_T100_BOM.xlsx', Uint8List.fromList(read('demo_T100_BOM.xlsx')));
    state.load(InputKind.stationA, 'demo_station_A.xlsx', Uint8List.fromList(read('demo_station_A.xlsx')));
    state.load(InputKind.stationB, 'demo_station_B.xlsx', Uint8List.fromList(read('demo_station_B.xlsx')));
    state.load(InputKind.coords, 'demo_coordinates.csv', Uint8List.fromList(read('demo_coordinates.csv')));
    state.runCheckNow();
    return state;
  }

  Future<void> shot(WidgetTester tester, AppState state, String name, {Size size = const Size(1600, 940), bool touch = false}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(SmtFaiApp(state: state, touch: touch));
    await tester.pumpAndSettle();
    await expectLater(find.byType(SmtFaiApp), matchesGoldenFile('screens/$name.png'));
  }

  testWidgets('check view zh dark', (tester) async {
    final s = demoState();
    s.select(s.report!.rows.firstWhere((r) => r.category == CheckCategory.ng));
    await shot(tester, s, 'check_zh_dark');
  });

  testWidgets('check view NG filter en light', (tester) async {
    final s = demoState(lang: 'en', dark: false);
    s.setFilter(CheckCategory.ng);
    s.select(s.report!.rows.firstWhere((r) => r.category == CheckCategory.ng));
    await shot(tester, s, 'check_ng_en_light');
  });

  testWidgets('substitute th', (tester) async {
    final s = demoState(lang: 'th');
    s.setFilter(CheckCategory.substitute);
    s.setRibbonTab(3);
    await shot(tester, s, 'substitute_th_dark');
  });

  testWidgets('board view', (tester) async {
    final s = demoState();
    s.setWorkspace(Workspace.board);
    s.setFilter(CheckCategory.ng);
    await shot(tester, s, 'board_zh_dark');
  });

  testWidgets('cad view', (tester) async {
    final s = demoState(dark: false);
    s.setWorkspace(Workspace.cad);
    s.setRibbonTab(2);
    await shot(tester, s, 'cad_zh_light');
  });

  testWidgets('narrow window', (tester) async {
    final s = demoState();
    await shot(tester, s, 'narrow_zh_dark', size: const Size(1000, 640));
  });

  testWidgets('import guide light', (tester) async {
    final s = AppState(AppSettings(theme: ThemePref.light), Directory.systemTemp.path);
    s.load(InputKind.bom, 'demo_T100_BOM.xlsx', File('samples/demo/demo_T100_BOM.xlsx').readAsBytesSync());
    await shot(tester, s, 'guide_zh_light');
  });

  testWidgets('tablet landscape', (tester) async {
    final s = demoState(dark: false);
    s.select(s.report!.rows.firstWhere((r) => r.category == CheckCategory.ng));
    await shot(tester, s, 'tablet_landscape_light', size: const Size(1280, 800), touch: true);
  });

  testWidgets('tablet portrait', (tester) async {
    final s = demoState();
    s.setFilter(CheckCategory.ng);
    await shot(tester, s, 'tablet_portrait_dark', size: const Size(800, 1280), touch: true);
  });

  testWidgets('tablet portrait cad', (tester) async {
    final s = demoState(dark: false);
    s.setWorkspace(Workspace.cad);
    await shot(tester, s, 'tablet_portrait_cad_light', size: const Size(800, 1280), touch: true);
  });
}
