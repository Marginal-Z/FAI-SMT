import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/app_state.dart';
import 'package:smt_fai/core/local_ai/model_store.dart';
import 'package:smt_fai/core/settings.dart';
import 'package:smt_fai/main.dart';
import 'package:smt_fai/ui/widgets.dart';

// File persistence is covered by local_required_test; keep widget clocks isolated
// from real filesystem I/O while exercising the actual controls and state.
class ControlsState extends AppState {
  ControlsState(super.settings, super.settingsDir);
  @override
  Future<void> persist() async {}
}

void main() {
  for (final width in [390.0, 800.0, 1440.0]) {
    testWidgets('choose, enable and disable local model at width $width', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('model-controls-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final s = ControlsState(AppSettings(tourDone: true, checkMode: CheckMode.hybrid), dir.path);
      for (final m in embeddingModels.take(2)) {
        s.modelStatus[m.id] = const ModelStatus(ModelState.ready);
      }
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(SmtFaiApp(state: s, touch: width < 840));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('local-model-toggle'));
      final choice = find.byKey(const ValueKey('local-model-choice'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(s.settings.localAiEnabled, isTrue);
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      final option = find.textContaining(embeddingModels[1].name).last;
      expect(tester.getRect(option).bottom, lessThanOrEqualTo(1000));
      expect(tester.getRect(option).top, greaterThanOrEqualTo(0));
      await tester.tap(option);
      await tester.pump();
      await tester.runAsync(() async {
        for (var i = 0; i < 200 && s.localBusy; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pumpAndSettle();
      expect(s.localBusy, isFalse);
      expect(s.activeEmbedding.id, embeddingModels[1].id);
      expect(s.settings.localAiEnabled, isTrue);
      // The same choice also works with the keyboard; Escape leaves it unchanged.
      await tester.tap(choice);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(s.activeEmbedding.id, embeddingModels[1].id);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.runAsync(() async {
        for (var i = 0; i < 200 && s.localBusy; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pumpAndSettle();
      expect(s.activeEmbedding.id, embeddingModels[2].id);
      expect(s.localModelsReady, isFalse);
      expect(find.text('所选模型未就绪，请下载或更换模型。'), findsOneWidget);
      // A selected model becoming unavailable must never trap the preference ON.
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(s.settings.localAiEnabled, isFalse);
      expect(s.settingsOpen, isFalse);
      // No download is started merely by choosing an unavailable model.
      expect(s.modelStatus[embeddingModels[2].id], isNull);
      final dropdown = tester.widget<DropdownSelect<String>>(choice);
      expect(dropdown.onChanged, isNotNull);
      expect(tester.takeException(), isNull);
    });
  }
}
