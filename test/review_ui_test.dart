import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/app_state.dart';
import 'package:smt_fai/core/bom.dart';
import 'package:smt_fai/core/settings.dart';
import 'package:smt_fai/core/local_ai/model_store.dart';
import 'package:smt_fai/core/table_reader.dart';
import 'package:smt_fai/main.dart';

void main() {
  for (final width in [390.0, 800.0, 1440.0]) {
    testWidgets('model evidence and direction details fit width $width', (tester) async {
      final dir = Directory.systemTemp.createTempSync('review-ui-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final s = AppState(AppSettings(tourDone: true), dir.path);
      s.modelStatus[s.activeEmbedding.id] = const ModelStatus(ModelState.ready);
      BomDocument doc(String id) => readBom([Grid('s', [['料号', '描述', '用量', '位号'], ['P1001', 'LED red 0603', '1', 'D1']])], id: id);
      s.single = LoadedFile('A.csv', doc('S'));
      s.bomA = LoadedFile('B.csv', doc('A'));
      s.runCheckNow();
      s.select(s.report!.rows.single);
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(SmtFaiApp(state: s, touch: width < 840));
      await tester.pumpAndSettle();
      expect(find.text('方向核对提醒'), findsWidgets);
      expect(find.textContaining('二极管 / LED：'), findsOneWidget);
      expect(tester.takeException(), isNull);
      s.select(null);
      s.openSettings(SettingsSection.localAi);
      await tester.pumpAndSettle();
      expect(find.text('运行推理自检'), findsOneWidget);
      expect(find.textContaining('当前核对流程不调用可选语言模型'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
