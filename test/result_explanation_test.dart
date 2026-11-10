import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/app_state.dart';
import 'package:smt_fai/core/bom.dart';
import 'package:smt_fai/core/bom_compare.dart';
import 'package:smt_fai/core/table_reader.dart';
import 'package:smt_fai/main.dart';

import 'support/local_models.dart';

void main() {
  for (final conflict in [false, true]) {
    testWidgets(
      'final verdict explains reference metadata and material conflict=$conflict',
      (tester) async {
        final dir = Directory.systemTemp.createTempSync('explanation-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final state = (await tester.runAsync(() async {
          final st = localState(dir.path, FakeLocalModels());
          BomDocument doc(String id, String old, String qty) => readBom([
            Grid('BOM', [
              ['料号', '描述', '用量', '位号', '旧料号'],
              ['K1201-AA4730-J10A', '贴片电阻 47K 0201 1/20W ±5%', qty, 'R1', old],
            ]),
          ], id: id);
          st.single = LoadedFile('A.csv', doc('S', '', '1'));
          st.bomA = LoadedFile(
            'B.csv',
            doc('A', 'OLD-47K', conflict ? '2' : '1'),
          );
          st.runCheckNow();
          await settleLocal(st);
          return st;
        }))!;
        tester.view.physicalSize = const Size(1366, 768);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(SmtFaiApp(state: state));
        await tester.pumpAndSettle();
        state.select(state.report!.rows.first);
        await tester.pumpAndSettle();
        final conclusion = find.byKey(const ValueKey('final-conclusion'));
        expect(conclusion, findsOneWidget);
        expect(
          find.descendant(
            of: conclusion,
            matching: find.text(conflict ? 'NG · 有差异' : 'PASS · 物料一致'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('reference-differences')),
          findsOneWidget,
        );
        expect(find.textContaining('不影响物料一致判定'), findsOneWidget);
        expect(find.textContaining('100%'), findsNothing);
        if (conflict) {
          expect(state.report!.rows.first.status, CheckStatus.ng);
          expect(
            find.descendant(
              of: conclusion,
              matching: find.textContaining('用量'),
            ),
            findsOneWidget,
          );
          expect(find.textContaining('AI 认为一致，但程序发现'), findsOneWidget);
        } else {
          expect(
            state.report!.rows.first.reasons,
            isNot(contains('local_ai_contradicted')),
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
