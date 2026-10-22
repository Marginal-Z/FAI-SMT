// Renders every ribbon glyph on dark and light backgrounds for review.
//
//   flutter test tool/glyph_sheet_test.dart --update-goldens
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/ui/glyphs.dart';
import 'package:smt_fai/ui/theme.dart';

void main() {
  testWidgets('glyph sheet', (tester) async {
    tester.view.physicalSize = const Size(1000, 520);
    tester.view.devicePixelRatio = 1;
    Widget sheet(AppColors c) => AppTheme(
          colors: c,
          child: Container(
            color: c.ribbon,
            padding: const EdgeInsets.all(16),
            child: Wrap(spacing: 22, runSpacing: 18, children: [
              for (final g in Glyph.values)
                Column(mainAxisSize: MainAxisSize.min, children: [
                  GlyphIcon(g, size: 48),
                  const SizedBox(height: 6),
                  GlyphIcon(g, size: 26),
                ]),
            ]),
          ),
        );
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Column(children: [
        Expanded(child: sheet(AppColors.darkTheme)),
        Expanded(child: sheet(AppColors.lightTheme)),
      ]),
    ));
    await expectLater(find.byType(Column).first, matchesGoldenFile('screens/glyphs.png'));
  });
}
