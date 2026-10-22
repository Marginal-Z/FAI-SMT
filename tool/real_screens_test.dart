// Renders the main window with the real sample files under samples/ (not in
// git) to tool/screens_real/*.png (also not in git).
//
//   flutter test tool/real_screens_test.dart --update-goldens
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

  Future<void> shot(WidgetTester tester, AppState state, String name, {Size size = const Size(1600, 940), bool touch = false}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(SmtFaiApp(state: state, touch: touch));
    await tester.pumpAndSettle();
    await expectLater(find.byType(SmtFaiApp), matchesGoldenFile('screens_real/$name.png'));
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
}
