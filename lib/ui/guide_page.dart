/// Settings → User guide: how to use each module, shortcuts and common
/// questions, plus a button to replay the guided tour.
library;

import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../l10n/strings.dart';
import 'glyphs.dart';
import 'theme.dart';
import 'widgets.dart';

const _sections = [
  (Glyph.play, 'quick'),
  (Glyph.modFiles, 'files'),
  (Glyph.modCheck, 'check'),
  (Glyph.modCad, 'cad'),
  (Glyph.modBoard, 'board'),
  (Glyph.library, 'library'),
  (Glyph.settings, 'settings'),
  (Glyph.tip, 'keys'),
  (Glyph.help, 'faq'),
];

class GuidePage extends StatelessWidget {
  const GuidePage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.t('set_guide'),
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text),
                        ),
                        const SizedBox(height: 4),
                        Text(s.t('guide_intro'), style: TextStyle(fontSize: 12.5, color: c.textDim)),
                      ],
                    ),
                  ),
                  FlatButton(label: s.t('guide_tour'), primary: true, onTap: state.startTour),
                ],
              ),
              const SizedBox(height: 16),
              for (final (glyph, key) in _sections) ...[
                SurfaceCard(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: c.accent.withValues(alpha: c.dark ? 0.18 : 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: GlyphIcon(glyph, size: 17, filled: true, color: c.accent),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            s.t('guide_${key}_title'),
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      for (final line in s.t('guide_${key}_body').split('\n')) _Line(text: line),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One line of guide text: "• " bullets and "1. " steps get a hanging indent.
class _Line extends StatelessWidget {
  const _Line({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final style = TextStyle(fontSize: 13, color: c.text, height: 1.6);
    final step = RegExp(r'^(\d+)\. ').firstMatch(text);
    if (text.startsWith('• ') || step != null) {
      final marker = step != null ? '${step.group(1)}.' : '•';
      final body = step != null ? text.substring(step.end) : text.substring(2);
      return Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 20,
              child: Text(
                marker,
                style: style.copyWith(color: c.accent, fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(child: Text(body, style: style)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: style.copyWith(color: c.textDim)),
    );
  }
}
