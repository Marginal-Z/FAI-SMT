import 'dart:io';
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/core/bom_compare.dart';
import 'package:smt_fai/core/ai_check.dart';
import 'package:smt_fai/core/settings.dart';
import 'package:smt_fai/main.dart';

import 'support/local_models.dart';

void main() {
  for (final size in [
    const Size(1366, 768),
    const Size(1280, 720),
    const Size(1024, 768),
    const Size(800, 1000),
    const Size(390, 844),
    const Size(800, 600),
    const Size(960, 640),
  ]) {
    testWidgets('results stay visible and filters survive resize at $size', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('check-layout-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final state = (await tester.runAsync(() async {
        final value = localState(
          dir.path,
          FakeLocalModels(),
          count: 12,
          conflict: true,
        )..runCheckNow();
        if (size.width == 1024) {
          value.settings.language = 'en';
        }
        await settleLocal(value);
        return value;
      }))!;
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(SmtFaiApp(state: state, touch: size.width < 840));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (size.width >= 840) {
        final viewport = find.byKey(const ValueKey('check-results-viewport'));
        expect(tester.getSize(viewport).height, greaterThan(size.height * .7));
        final before = tester.getRect(viewport);
        final verdict = find
            .descendant(of: viewport, matching: find.textContaining('NG ·'))
            .first;
        expect(tester.getRect(verdict).right, lessThanOrEqualTo(before.right));
        await tester.tap(find.byKey(const ValueKey('workspace-directions')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('workspace-inspector')),
          findsOneWidget,
        );
        expect(tester.getRect(viewport).height, closeTo(before.height, 1));
        await tester.tap(find.byKey(const ValueKey('workspace-close')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('workspace-filter-ng')));
      } else {
        expect(
          find.byKey(const ValueKey('input-files-summary')),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('NG').first);
        await tester.tap(find.text('NG').first);
      }
      await tester.pumpAndSettle();
      expect(state.filter, CheckStatus.ng);
      tester.view.physicalSize = const Size(1440, 900);
      await tester.pumpAndSettle();
      expect(state.filter, CheckStatus.ng);
      expect(
        state.visibleRows().every((r) => r.status == CheckStatus.ng),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      state.select(state.visibleRows().first);
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(1280, 720);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'Detail drawer must fit a laptop viewport',
      );
      state.select(null);
      await tester.pumpAndSettle();
    });
  }
  testWidgets('phone keeps analysis progress and cancel above navigation', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('check-running-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final model = FakeLocalModels()
      ..pending = Completer<Map<String, dynamic>>();
    final state = localState(dir.path, model);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(SmtFaiApp(state: state, touch: true));
    await tester.pumpAndSettle();
    state.runCheckNow();
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.report, isNull);
    expect(state.canExportReport, isFalse);
    final cancel = find.text('取消');
    expect(cancel, findsOneWidget);
    expect(tester.getRect(cancel).bottom, lessThan(760));
    await tester.tap(cancel);
    model.pending!.complete(model.answer(model.prompts.single));
    await tester.pumpAndSettle();
    expect(state.report, isNull);
    expect(state.localBusy, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('translated verdict and AI mark fit the leading result column', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('check-long-verdict-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final state = (await tester.runAsync(() async {
      final value = localState(dir.path, FakeLocalModels())..runCheckNow();
      await settleLocal(value);
      return value;
    }))!;
    // A view fixture for a long translated verdict with a saved AI finding.
    final r = state.report!.rows.first;
    state.report!.rows[0] = CompareRow(
      partNo: r.partNo,
      status: CheckStatus.substitute,
      single: r.single,
      merged: r.merged,
      singleParts: r.singleParts,
      mergedParts: r.mergedParts,
      fields: r.fields,
      sources: r.sources,
      missingRefs: r.missingRefs,
      extraRefs: r.extraRefs,
      movedRefs: r.movedRefs,
      basis: r.basis,
      reasons: r.reasons,
      localNote: r.localNote,
    );
    state.settings.language = 'en';
    state.settings.checkMode = CheckMode.hybrid;
    state.ai = AiResult(
      summary: 'Fixture',
      findings: [
        AiFinding(
          partNo: r.partNo,
          field: 'description',
          side: 'both',
          severity: AiSeverity.info,
          message: 'Fixture',
        ),
      ],
      model: 'test',
      at: DateTime(2026),
    );
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(SmtFaiApp(state: state));
    await tester.pumpAndSettle();
    final viewport = find.byKey(const ValueKey('check-results-viewport'));
    final label = find.descendant(
      of: viewport,
      matching: find.text('Listed substitute'),
    );
    expect(label, findsOneWidget);
    expect(
      tester.getRect(label).right,
      lessThanOrEqualTo(tester.getRect(viewport).right),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'table scroll position returns after switching to compact cards',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('check-scroll-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final state = (await tester.runAsync(() async {
        final value = localState(dir.path, FakeLocalModels(), count: 60)
          ..runCheckNow();
        await settleLocal(value);
        return value;
      }))!;
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(SmtFaiApp(state: state));
      await tester.pumpAndSettle();
      final rows = find.byKey(const PageStorageKey('check-table-rows'));
      tester.widget<ListView>(rows).controller!.jumpTo(300);
      final columns = find.byKey(const PageStorageKey('check-table-columns'));
      tester.widget<SingleChildScrollView>(columns).controller!.jumpTo(100);
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(800, 600);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const PageStorageKey('check-card-rows')),
        findsOneWidget,
      );
      tester.view.physicalSize = const Size(1024, 768);
      await tester.pumpAndSettle();
      expect(tester.widget<ListView>(rows).controller!.offset, closeTo(300, 1));
      expect(
        tester.widget<SingleChildScrollView>(columns).controller!.offset,
        closeTo(100, 1),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
