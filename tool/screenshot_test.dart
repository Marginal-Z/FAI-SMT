// Renders the main window with the demo data to PNG files for visual review.
//
//   flutter test tool/screenshot_test.dart --update-goldens
//
// Output: tool/screens/*.png. Uses system Noto fonts (Linux).
import 'dart:io';

import 'package:flutter/gestures.dart';
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
    await _font('FluentSystemIcons-Regular', ['assets/fonts/FluentSystemIcons-Regular.ttf']);
    await _font('FluentSystemIcons-Filled', ['assets/fonts/FluentSystemIcons-Filled.ttf']);
  });

  AppState demoState({String lang = 'zh', bool dark = true}) {
    final state = AppState(AppSettings(language: lang, theme: dark ? ThemePref.dark : ThemePref.light), Directory.systemTemp.path);
    List<int> read(String n) => File('samples/demo/$n').readAsBytesSync();
    state.load(InputKind.bom, 'demo_T100_BOM.xlsx', Uint8List.fromList(read('demo_T100_BOM.xlsx')));
    state.load(InputKind.stationA, 'demo_station_A.xlsx', Uint8List.fromList(read('demo_station_A.xlsx')));
    state.load(InputKind.stationB, 'demo_station_B.xlsx', Uint8List.fromList(read('demo_station_B.xlsx')));
    state.load(InputKind.coords, 'demo_coordinates.csv', Uint8List.fromList(read('demo_coordinates.csv')));
    state.runCheckNow();
    state.setModule(Module.check);
    return state;
  }

  Future<void> shot(WidgetTester tester, AppState state, String name,
      {Size size = const Size(1600, 940), bool touch = false, int zoomSteps = 0, Offset zoomAt = const Offset(800, 560)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(SmtFaiApp(state: state, touch: touch));
    await tester.pumpAndSettle();
    for (var i = 0; i < zoomSteps; i++) {
      tester.binding.handlePointerEvent(PointerScrollEvent(position: zoomAt, scrollDelta: const Offset(0, -50)));
      await tester.pump();
    }
    await expectLater(find.byType(SmtFaiApp), matchesGoldenFile('screens/$name.png'));
  }

  testWidgets('files page dark', (tester) async {
    final s = demoState();
    s.setModule(Module.files);
    await shot(tester, s, 'files_zh_dark');
  });

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

  testWidgets('rules th light', (tester) async {
    final s = demoState(lang: 'th', dark: false);
    s.openRules(RulesSection.exclusion);
    await shot(tester, s, 'rules_th_light');
  });

  testWidgets('board view', (tester) async {
    final s = demoState();
    s.setModule(Module.board);
    await shot(tester, s, 'board_zh_dark');
  });

  testWidgets('cad view', (tester) async {
    final s = demoState(dark: false);
    s.setModule(Module.cad);
    await shot(tester, s, 'cad_zh_light');
  });

  testWidgets('files page light empty', (tester) async {
    final s = AppState(AppSettings(theme: ThemePref.light), Directory.systemTemp.path);
    s.load(InputKind.bom, 'demo_T100_BOM.xlsx', File('samples/demo/demo_T100_BOM.xlsx').readAsBytesSync());
    await shot(tester, s, 'files_zh_light');
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

  testWidgets('tablet portrait files', (tester) async {
    final s = demoState(dark: false);
    s.setModule(Module.files);
    await shot(tester, s, 'tablet_portrait_files_light', size: const Size(800, 1280), touch: true);
  });

  testWidgets('assembly zoomed', (tester) async {
    final s = demoState();
    s.setModule(Module.board);
    await shot(tester, s, 'board_zoom_dark', zoomSteps: 9, zoomAt: const Offset(560, 520));
  });

  testWidgets('assembly mirrored rotated light', (tester) async {
    final s = demoState(dark: false);
    s.setModule(Module.board);
    s.toggleBoardMirror();
    s.rotateBoard(1);
    s.setBoardColoring(BoardColoring.status);
    await shot(tester, s, 'board_mirror_light');
  });

  testWidgets('discrepancies', (tester) async {
    final s = demoState();
    s.setCheckView(CheckPageView.discrepancies);
    await shot(tester, s, 'discrepancies_zh_dark');
  });

  testWidgets('settings', (tester) async {
    final s = demoState(dark: false);
    s.openSettings(SettingsSection.update);
    await shot(tester, s, 'settings_zh_light');
  });

  testWidgets('settings appearance', (tester) async {
    final s = demoState();
    s.openSettings();
    await shot(tester, s, 'settings_appearance_dark');
  });

  testWidgets('board full screen', (tester) async {
    final s = demoState();
    s.setModule(Module.board);
    s.setBoardFullscreen(true);
    await shot(tester, s, 'board_fullscreen_dark');
  });

  testWidgets('board from generated CAD file', (tester) async {
    final s = demoState(dark: false);
    final bytes = s.cad!.encode();
    s.load(InputKind.boardCad, 'demo_FAI.xlsx', bytes);
    s.setModule(Module.board);
    await shot(tester, s, 'board_cadfile_light', zoomSteps: 6, zoomAt: const Offset(700, 520));
  });

  testWidgets('cad page', (tester) async {
    final s = demoState();
    s.setModule(Module.cad);
    await shot(tester, s, 'cad_zh_dark');
  });

  testWidgets('settings board colours', (tester) async {
    final s = demoState(dark: false);
    s.openSettings(SettingsSection.board);
    await shot(tester, s, 'settings_colors_light');
  });

  testWidgets('board green pcb', (tester) async {
    final s = demoState(dark: false);
    s.setModule(Module.board);
    s.setBoardBackground(BoardBackground.green);
    await shot(tester, s, 'board_green_light', zoomSteps: 5, zoomAt: const Offset(560, 560));
  });

  testWidgets('board black pcb', (tester) async {
    final s = demoState();
    s.setModule(Module.board);
    s.setBoardBackground(BoardBackground.black);
    await shot(tester, s, 'board_black_dark');
  });
}
