// Renders the main window with the real sample files under samples/ (not in
// git) to tool/screens_real/*.png (also not in git).
//
//   flutter test tool/real_screens_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/app_state.dart';
import 'package:smt_fai/core/bom_compare.dart';
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

  AppState realState({bool dark = false}) {
    final state = AppState(AppSettings(theme: dark ? ThemePref.dark : ThemePref.light, tourDone: true), Directory.systemTemp.path);
    void load(InputKind k, String dir, [String suffix = '']) {
      final f = Directory('samples/$dir').listSync().whereType<File>().firstWhere((f) => f.path.endsWith('$suffix.xlsx'));
      state.load(k, f.uri.pathSegments.last, f.readAsBytesSync());
    }

    load(InputKind.single, 'BOM');
    load(InputKind.a, 'station', '-A');
    load(InputKind.b, 'station', '-B');
    state.runCheckNow();
    return state;
  }

  Future<void> shot(
    WidgetTester tester,
    AppState state,
    String name, {
    Size size = const Size(1440, 1060),
    bool touch = false,
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
    await expectLater(find.byType(SmtFaiApp), matchesGoldenFile('screens_real/$name.png'));
    debugDisableShadows = true;
  }

  testWidgets('real check', (tester) async {
    await shot(tester, realState(), 'check_light');
  });

  testWidgets('real differences', (tester) async {
    final s = realState(dark: true);
    s.setFilter(DiffStatus.different);
    final diff = s.visibleRows();
    if (diff.isNotEmpty) s.select(diff.first);
    await shot(tester, s, 'diff_dark');
  });

  testWidgets('real phone', (tester) async {
    await shot(tester, realState(), 'phone', size: const Size(390, 844), touch: true);
  });
}
