// Renders the main window with the real sample files under samples/ (not in
// git) to tool/screens_real/*.png (also not in git).
//
//   flutter test tool/real_screens_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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
    for (final f in ['PingFang SC', 'Microsoft YaHei UI', 'Noto Sans CJK SC']) {
      await _font(f, ['/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc', '/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc']);
    }
    await _font('Noto Sans Thai', ['/usr/share/fonts/truetype/noto/NotoSansThai-Regular.ttf', '/usr/share/fonts/truetype/noto/NotoSansThai-Bold.ttf']);
    await _font('DejaVu Sans Mono', ['/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf']);
    await _font('Inter', ['assets/fonts/Inter-Regular.ttf', 'assets/fonts/Inter-Medium.ttf', 'assets/fonts/Inter-SemiBold.ttf', 'assets/fonts/Inter-Bold.ttf']);
    await _font('PhosphorRegular', ['assets/fonts/Phosphor-Regular.ttf']);
    await _font('PhosphorBold', ['assets/fonts/Phosphor-Bold.ttf']);
    await _font('FluentSystemIcons-Regular', ['assets/fonts/FluentSystemIcons-Regular.ttf']);
    await _font('FluentSystemIcons-Filled', ['assets/fonts/FluentSystemIcons-Filled.ttf']);
  });

  AppState demoState({String lang = 'zh', bool dark = true}) {
    final state = AppState(AppSettings(language: lang, theme: dark ? ThemePref.dark : ThemePref.light), Directory.systemTemp.path);
    void load(InputKind k, String dir, [String suffix = '']) {
      final f = Directory('samples/$dir').listSync().whereType<File>().firstWhere((f) => f.path.endsWith('$suffix.xlsx'));
      state.load(k, f.uri.pathSegments.last, f.readAsBytesSync());
    }

    load(InputKind.bom, 'BOM');
    load(InputKind.stationA, 'station', '-A');
    load(InputKind.stationB, 'station', '-B');
    load(InputKind.coords, 'coordinates');
    state.runCheckNow();
    state.setModule(Module.check);
    return state;
  }

  Future<void> shot(
    WidgetTester tester,
    AppState state,
    String name, {
    Size size = const Size(1440, 1060),
    bool touch = false,
    int zoomSteps = 0,
    Offset zoomAt = const Offset(720, 600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    // Real blurred shadows, as the app draws them.
    debugDisableShadows = false;
    await tester.pumpWidget(SmtFaiApp(state: state, touch: touch));
    await tester.pumpAndSettle();
    // Asset images decode outside the fake clock; load the logo first.
    await tester.runAsync(() => precacheImage(const AssetImage('assets/icon/app_icon.png'), tester.element(find.byType(SmtFaiApp))));
    await tester.pumpAndSettle();
    for (var i = 0; i < zoomSteps; i++) {
      tester.binding.handlePointerEvent(PointerScrollEvent(position: zoomAt, scrollDelta: const Offset(0, -50)));
      await tester.pump();
    }
    await expectLater(find.byType(SmtFaiApp), matchesGoldenFile('screens_real/$name.png'));
    debugDisableShadows = true;
  }

  testWidgets('real check', (tester) async {
    final s = demoState();
    await shot(tester, s, 'check');
  });

  testWidgets('real substitutes', (tester) async {
    final s = demoState(dark: false);
    s.setFilter(CheckCategory.substitute);
    s.select(s.report!.rows.firstWhere((r) => r.category == CheckCategory.substitute));
    await shot(tester, s, 'substitute');
  });

  testWidgets('real excluded', (tester) async {
    final s = demoState();
    s.setFilter(CheckCategory.excluded);
    await shot(tester, s, 'excluded');
  });

  testWidgets('real board', (tester) async {
    final s = demoState();
    s.setModule(Module.board);
    await shot(tester, s, 'board');
  });

  testWidgets('real cad', (tester) async {
    final s = demoState(dark: false);
    s.setModule(Module.cad);
    await shot(tester, s, 'cad');
  });

  testWidgets('real assembly zoom', (tester) async {
    final s = demoState();
    s.setModule(Module.board);
    await shot(tester, s, 'board_zoom', zoomSteps: 12, zoomAt: const Offset(800, 520));
  });

  testWidgets('real discrepancies', (tester) async {
    final s = demoState(dark: false);
    s.setCheckView(CheckPageView.discrepancies);
    await shot(tester, s, 'discrepancies');
  });

  testWidgets('real board green', (tester) async {
    final s = demoState(dark: false);
    s.setModule(Module.board);
    s.setBoardBackground(BoardBackground.green);
    await shot(tester, s, 'board_green');
  });

  testWidgets('real board 3d', (tester) async {
    final s = demoState(dark: false);
    s.setModule(Module.board);
    s.settings.board.depth = true;
    await shot(tester, s, 'board_3d');
  });

  testWidgets('real board fullscreen', (tester) async {
    final s = demoState(dark: false);
    s.setModule(Module.board);
    s.setBoardFullscreen(true);
    await shot(tester, s, 'board_fullscreen');
  });

  testWidgets('real board 3d zoom', (tester) async {
    final s = demoState();
    s.setModule(Module.board);
    s.settings.board.depth = true;
    await shot(tester, s, 'board_3d_zoom', zoomSteps: 12, zoomAt: const Offset(800, 520));
  });

  testWidgets('real ng confirmed', (tester) async {
    final s = demoState(dark: false);
    final ng = s.report!.rows.where((r) => r.category == CheckCategory.ng).toList();
    s.setConfirmed(ng, true);
    s.setConfirmNote(ng.first, '已与工程确认 4040 封装可用');
    s.select(ng.first);
    await shot(tester, s, 'ng_confirmed');
  });

  testWidgets('real board green zoom', (tester) async {
    final s = demoState(dark: false);
    s.setModule(Module.board);
    s.setBoardBackground(BoardBackground.green);
    await shot(tester, s, 'board_green_zoom', zoomSteps: 9, zoomAt: const Offset(780, 640));
  });

  testWidgets('real board green 3d zoom', (tester) async {
    final s = demoState(dark: false);
    s.setModule(Module.board);
    s.setBoardBackground(BoardBackground.green);
    s.settings.board.depth = true;
    await shot(tester, s, 'board_green_3d_zoom', zoomSteps: 9, zoomAt: const Offset(780, 640));
  });

  testWidgets('real board 3d bottom mirrored', (tester) async {
    final s = demoState();
    s.setModule(Module.board);
    s.settings.board.depth = true;
    s.setBoardSide(BoardSideFilter.bottom);
    s.toggleBoardMirror();
    await shot(tester, s, 'board_3d_bottom', zoomSteps: 6, zoomAt: const Offset(800, 560));
  });

  testWidgets('real board locate', (tester) async {
    final s = demoState(dark: false);
    s.setModule(Module.board);
    await shot(tester, s, 'board_locate_before');
    await tester.enterText(find.byType(EditableText), '10U3');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 250));
    await expectLater(find.byType(SmtFaiApp), matchesGoldenFile('screens_real/board_locate.png'));
    await tester.pumpAndSettle();
  });


  // Industrial style.
  for (final (name, mod, ng) in [('check', Module.check, false), ('check_ng', Module.check, true), ('cad', Module.cad, false), ('board', Module.board, false)]) {
    testWidgets('industrial $name', (tester) async {
      final s = demoState(dark: false);
      s.settings.themeStyle = ThemeStyle.industrial;
      s.setModule(mod);
      if (ng) {
        s.setFilter(CheckCategory.ng);
        s.select(s.report!.rows.firstWhere((r) => r.category == CheckCategory.ng));
      }
      await shot(tester, s, 'industrial_$name');
    });
  }
  testWidgets('industrial dark check', (tester) async {
    final s = demoState();
    s.settings.themeStyle = ThemeStyle.industrial;
    await shot(tester, s, 'industrial_check_dark');
  });

}
