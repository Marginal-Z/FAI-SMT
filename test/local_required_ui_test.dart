import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/main.dart';
import 'package:smt_fai/ui/widgets.dart';

import 'support/local_models.dart';

void main() {
  for (final width in [390.0, 800.0, 1440.0]) {
    testWidgets(
      'compact imports, mandatory analysis and reminder panel at $width',
      (tester) async {
        final dir = Directory.systemTemp.createTempSync('local-required-ui-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final model = FakeLocalModels()
          ..pending = Completer<Map<String, dynamic>>();
        final state = localState(dir.path, model);
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(SmtFaiApp(state: state, touch: width < 840));
        await tester.pumpAndSettle();
        for (final role in ['single', 'a', 'b']) {
          final size = tester.getSize(
            find.byKey(ValueKey('import-card-$role')),
          );
          expect(
            size.height,
            inInclusiveRange(44, 50),
            reason: '$role at $width',
          );
        }
        expect(find.text('本地 AI 分析（必需）'), findsOneWidget);
        expect(
          tester
              .widget<DropdownSelect<String>>(
                find.byKey(const ValueKey('local-model-choice')),
              )
              .onChanged,
          isNull,
        );
        expect(
          find.byKey(const ValueKey('direction-reminders-panel')),
          findsOneWidget,
        );
        state.runCheckNow();
        await tester.pump(const Duration(milliseconds: 100));
        expect(state.report, isNull);
        expect(state.canExportReport, isFalse);
        expect(find.text('PASS'), findsNothing);
        expect(model.prompts, hasLength(1));
        model.pending!.complete(model.answer(model.prompts.single));
        await tester.pumpAndSettle();
        expect(state.canExportReport, isTrue);
        expect(state.report!.localModel.rows, 2);
        final panel = find.byKey(const ValueKey('direction-reminders-panel'));
        final expand = find.byKey(const ValueKey('direction-expand'));
        if (expand.evaluate().isEmpty && width < 600) {
          await tester.scrollUntilVisible(
            panel,
            200,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await tester.ensureVisible(expand);
        await tester.tap(expand);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('direction-details-list')),
            matching: find.textContaining('P1001'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('direction-details-list')),
            matching: find.textContaining('D1'),
          ),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('direction-filter')),
        );
        await tester.tap(find.byKey(const ValueKey('direction-filter')));
        await tester.pumpAndSettle();
        expect(state.reasonFilter, 'orientation');
        expect(state.visibleRows().map((r) => r.partNo), ['P1001']);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
