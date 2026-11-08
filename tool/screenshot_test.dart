// Renders the main window with the demo data to PNG files for visual review.
//
//   flutter test tool/screenshot_test.dart --update-goldens
//
// Output: tool/screens/*.png. Uses system Noto fonts (Linux).
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/app_state.dart';
import 'package:smt_fai/core/ai_check.dart';
import 'package:smt_fai/core/bom_compare.dart';
import 'package:smt_fai/core/cloud/provider.dart';
import 'package:smt_fai/core/local_ai/model_store.dart';
import 'package:smt_fai/core/history.dart';
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

  AppState demoState({String lang = 'zh', bool dark = true, bool check = true, bool ai = false}) {
    final state = AppState(AppSettings(language: lang, theme: dark ? ThemePref.dark : ThemePref.light, tourDone: true), Directory.systemTemp.path);
    Uint8List read(String n) => Uint8List.fromList(File('samples/demo/$n').readAsBytesSync());
    state.load(InputKind.single, 'demo_A_BOM.xlsx', read('demo_A_BOM.xlsx'));
    state.load(InputKind.a, 'demo_B_BOM.xlsx', read('demo_B_BOM.xlsx'));
    state.load(InputKind.b, 'demo_C_BOM.xlsx', read('demo_C_BOM.xlsx'));
    if (check) state.runCheckNow();
    if (ai) {
      // A sample analysis, as a model would return it.
      state.settings.aiEnabled = true;
      state.settings.cloud = ProviderConfig(model: 'gpt-4o-mini');
      state.cloudKey = 'demo';
      state.ai = AiResult(
        summary: '共 28 个料号：19 个 PASS，5 个 NG，1 个需复核（HDMI 座料号不同且未登记替代），1 个认可替代料（绿色 LED）。主要问题：K1103-0106K0-001A 电容耐压 6.3V 与 10V 不一致；K1103-0220P0-001A 缺少位号 C21；K1102-1049K9-001A 多出 R32；K1104-2R2M00-001A 用量 3 与位号数 2 不符。建议先确认电容耐压与缺失位号。',
        findings: [
          AiFinding(partNo: 'K1103-0106K0-001A', field: 'description', side: 'both', severity: AiSeverity.error, message: '耐压不同：A-BOM 为 6.3V，B+C 为 10V，不是等价写法。', singleValue: '10uF 6.3V X5R 0603', mergedValue: '10uF 10V X5R 0603'),
          AiFinding(partNo: 'K1103-0220P0-001A', field: 'refs', side: 'merged', severity: AiSeverity.error, message: 'B+C 缺少位号 C21，贴片时会漏件。', singleValue: 'C20,C21', mergedValue: 'C20'),
          AiFinding(partNo: 'K1104-2R2M00-001A', field: 'quantity', side: 'merged', severity: AiSeverity.warning, message: 'B-BOM 用量 3 与位号 L1、L2 数量不符。', singleValue: '2', mergedValue: '3'),
          AiFinding(partNo: 'K1109-MOS340-001A', field: '品牌', side: 'both', severity: AiSeverity.info, message: 'AOS 与 Alpha&Omega 为同一厂商的不同写法，建议统一。', singleValue: 'AOS', mergedValue: 'Alpha&Omega'),
        ],
        model: 'gpt-4o-mini',
        at: DateTime(2026, 11, 3, 10, 30),
      );
      state.aiStatus = AiStatus.done;
    }
    return state;
  }

  CompareRow row(AppState s, String pn) => s.report!.rows.firstWhere((r) => r.partNo == pn);

  Future<void> shot(
    WidgetTester tester,
    AppState state,
    String name, {
    Size size = const Size(1600, 940),
    bool touch = false,
    int zoomSteps = 0,
    Offset zoomAt = const Offset(800, 560),
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
    await expectLater(find.byType(SmtFaiApp), matchesGoldenFile('screens/$name.png'));
    debugDisableShadows = true;
  }

  for (final dark in [false, true]) {
    final tag = dark ? 'dark' : 'light';
    testWidgets('empty $tag', (tester) async {
      final s = AppState(AppSettings(theme: dark ? ThemePref.dark : ThemePref.light, tourDone: true), Directory.systemTemp.path);
      await shot(tester, s, 'empty_$tag', size: const Size(1600, 940));
    });
    testWidgets('loaded $tag', (tester) async {
      final s = demoState(dark: dark, check: false);
      await shot(tester, s, 'loaded_$tag');
    });
    testWidgets('check $tag', (tester) async {
      final s = demoState(dark: dark);
      await shot(tester, s, 'check_$tag');
    });
    testWidgets('check selected $tag', (tester) async {
      final s = demoState(dark: dark);
      s.setFilter(CheckStatus.ng);
      s.select(row(s, 'K1103-0106K0-001A'));
      await shot(tester, s, 'check_selected_$tag');
    });
    testWidgets('check ai $tag', (tester) async {
      final s = demoState(dark: dark, ai: true);
      await shot(tester, s, 'check_ai_$tag');
    });
    testWidgets('settings ai $tag', (tester) async {
      final s = demoState(dark: dark);
      s.openSettings(SettingsSection.ai);
      await shot(tester, s, 'settings_ai_$tag');
    });
  }

  testWidgets('check en', (tester) async {
    final s = demoState(lang: 'en', dark: false, ai: true);
    s.select(row(s, 'K1103-0220P0-001A'));
    await shot(tester, s, 'check_en_light');
  });

  testWidgets('check th', (tester) async {
    final s = demoState(lang: 'th', dark: false);
    await shot(tester, s, 'check_th_light');
  });

  for (final dark in [false, true]) {
    testWidgets('settings local models ${dark ? 'dark' : 'light'}', (tester) async {
      final s = demoState(dark: dark);
      s.openSettings(SettingsSection.localAi);
      s.modelStatus[embeddingModels.first.id] = const ModelStatus(ModelState.ready, progress: 1);
      s.modelStatus[embeddingModels[1].id] = const ModelStatus(ModelState.downloading, progress: 0.42);
      await shot(tester, s, 'settings_local_${dark ? 'dark' : 'light'}');
    });
  }

  testWidgets('settings checking', (tester) async {
    final s = demoState(dark: false);
    s.settings.compareSkip.add('others');
    s.settings.reportStatuses.addAll(['ng', 'review']);
    s.openSettings(SettingsSection.checking);
    await shot(tester, s, 'settings_checking_light');
  });

  testWidgets('history', (tester) async {
    final dir = Directory.systemTemp.createTempSync('smtfai-shots');
    addTearDown(() => dir.deleteSync(recursive: true));
    final s = AppState(AppSettings(theme: ThemePref.light, tourDone: true), dir.path, history: HistoryStore('${dir.path}/history'));
    Uint8List read(String n) => Uint8List.fromList(File('samples/demo/$n').readAsBytesSync());
    await tester.runAsync(() async {
      s.load(InputKind.single, 'demo_A_BOM.xlsx', read('demo_A_BOM.xlsx'));
      s.load(InputKind.a, 'demo_B_BOM.xlsx', read('demo_B_BOM.xlsx'));
      s.runCheckNow();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      s.load(InputKind.b, 'demo_C_BOM.xlsx', read('demo_C_BOM.xlsx'));
      s.runCheckNow();
      for (var i = 0; i < 100 && s.historyEntries.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    s.openSettings(SettingsSection.history);
    tester.view.physicalSize = const Size(1440, 1060);
    tester.view.devicePixelRatio = 1;
    await tester.runAsync(() => tester.pumpWidget(SmtFaiApp(state: s)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.textContaining('C: demo_C_BOM.xlsx'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.runAsync(() => precacheImage(const AssetImage('assets/icon/app_icon.png'), tester.element(find.byType(SmtFaiApp))));
    await tester.pump();
    await expectLater(find.byType(SmtFaiApp), matchesGoldenFile('screens/history_light.png'));
  });

  testWidgets('settings list', (tester) async {
    final s = demoState(dark: false);
    s.openSettings();
    await shot(tester, s, 'settings_list_light');
  });

  testWidgets('settings about', (tester) async {
    final s = demoState(dark: false);
    s.openSettings(SettingsSection.about);
    await shot(tester, s, 'settings_about_light');
  });

  testWidgets('settings appearance', (tester) async {
    final s = demoState();
    s.openSettings(SettingsSection.appearance);
    await shot(tester, s, 'settings_appearance_dark');
  });

  testWidgets('user guide', (tester) async {
    final s = demoState(dark: false);
    s.openSettings(SettingsSection.guide);
    await shot(tester, s, 'guide_light', size: const Size(1600, 1000));
  });

  testWidgets('tour', (tester) async {
    final s = demoState(dark: false);
    s.tourStep = 8;
    await shot(tester, s, 'tour_light', size: const Size(1600, 1000));
  });

  testWidgets('small window', (tester) async {
    final s = demoState(dark: false, ai: true);
    await shot(tester, s, 'small_light', size: const Size(1100, 760));
  });

  group('tablet', () {
    testWidgets('tablet landscape', (tester) async {
      final s = demoState(dark: false);
      s.select(row(s, 'K1103-0106K0-001A'));
      await shot(tester, s, 'tablet_landscape_light', size: const Size(1280, 800), touch: true);
    });
    testWidgets('tablet portrait', (tester) async {
      final s = demoState(ai: true);
      await shot(tester, s, 'tablet_portrait_dark', size: const Size(800, 1280), touch: true);
    });
    testWidgets('large tablet scaled up', (tester) async {
      final s = demoState(dark: false);
      s.settings.uiScale = 1.25;
      await shot(tester, s, 'tablet_scaled_light', size: const Size(1600, 1000), touch: true);
    });
  });

  // Phones: their own layout, not the desktop one scaled down.
  group('phone', () {
    const size = Size(390, 844);
    testWidgets('phone empty', (tester) async {
      final s = AppState(AppSettings(theme: ThemePref.light, tourDone: true), Directory.systemTemp.path);
      await shot(tester, s, 'phone_empty', size: size, touch: true);
    });
    testWidgets('phone check', (tester) async {
      final s = demoState(dark: false, ai: true);
      await shot(tester, s, 'phone_check', size: size, touch: true);
    });
    testWidgets('phone check selected', (tester) async {
      final s = demoState(dark: false);
      s.setFilter(CheckStatus.ng);
      s.select(row(s, 'K1103-0106K0-001A'));
      await shot(tester, s, 'phone_check_selected', size: size, touch: true);
    });
    testWidgets('phone settings ai', (tester) async {
      final s = demoState(dark: false);
      s.openSettings(SettingsSection.ai);
      await shot(tester, s, 'phone_settings_ai', size: size, touch: true);
    });
    testWidgets('phone settings list', (tester) async {
      final s = demoState(dark: false);
      s.openSettings();
      await shot(tester, s, 'phone_settings_list', size: size, touch: true);
    });
  });

  group('industrial', () {
    testWidgets('industrial check', (tester) async {
      final s = demoState(dark: false, ai: true);
      s.settings.themeStyle = ThemeStyle.industrial;
      s.select(row(s, 'K1103-0106K0-001A'));
      await shot(tester, s, 'industrial_check');
    });
    testWidgets('industrial dark', (tester) async {
      final s = demoState(ai: true);
      s.settings.themeStyle = ThemeStyle.industrial;
      await shot(tester, s, 'industrial_check_dark');
    });
    testWidgets('industrial phone', (tester) async {
      final s = demoState(dark: false);
      s.settings.themeStyle = ThemeStyle.industrial;
      await shot(tester, s, 'industrial_phone', size: const Size(390, 844), touch: true);
    });
  });

  // Screens for the website (light, Chinese, demo data only).
  group('site', () {
    const size = Size(1440, 900);
    testWidgets('site check', (tester) async {
      final s = demoState(dark: false);
      s.select(row(s, 'K1103-0106K0-001A'));
      await shot(tester, s, 'site_check', size: size);
    });
    testWidgets('site check dark', (tester) async {
      final s = demoState(ai: true);
      await shot(tester, s, 'site_check_dark', size: size);
    });
    testWidgets('site ai', (tester) async {
      final s = demoState(dark: false, ai: true);
      await shot(tester, s, 'site_ai', size: size);
    });
    testWidgets('site files', (tester) async {
      final s = demoState(dark: false, check: false);
      await shot(tester, s, 'site_files', size: size);
    });
    testWidgets('site settings ai', (tester) async {
      final s = demoState(dark: false);
      s.openSettings(SettingsSection.ai);
      await shot(tester, s, 'site_settings_ai', size: size);
    });
  });
}
