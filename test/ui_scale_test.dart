import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/app_state.dart';
import 'package:smt_fai/core/settings.dart';
import 'package:smt_fai/main.dart';
import 'package:smt_fai/ui/widgets.dart';

void main() {
  for (final scale in [0.8, 1.5]) {
    testWidgets('taps reach their targets at ${(scale * 100).round()} %', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = AppState(AppSettings(uiScale: scale), Directory.systemTemp.path);
      state.load(InputKind.single, 'demo_A_BOM.xlsx', Uint8List.fromList(File('samples/demo/demo_A_BOM.xlsx').readAsBytesSync()));
      await tester.pumpWidget(SmtFaiApp(state: state, touch: true));
      await tester.pumpAndSettle();
      expect(state.single, isNotNull);
      final clear = find.byWidgetPredicate((w) => w is Hoverable && w.tooltip == '清空');
      await tester.ensureVisible(clear.first);
      await tester.pumpAndSettle();
      await tester.tap(clear.first);
      await tester.pumpAndSettle();
      expect(state.single, isNull);
    });
  }
}
