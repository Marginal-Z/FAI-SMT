/// Rules the user enters: exclusions, alternates and ignored designators,
/// all empty until filled in and saved.
library;

import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../core/settings.dart';
import '../l10n/strings.dart';
import 'glyphs.dart';
import 'design.dart';
import 'theme.dart';
import 'widgets.dart';

List<String> _lines(String text) => text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

class RulesPage extends StatefulWidget {
  const RulesPage({super.key, required this.state});

  final AppState state;

  @override
  State<RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends State<RulesPage> {
  final _keywords = TextEditingController();
  final _prefixes = TextEditingController();
  final _ignore = TextEditingController();
  final _subs = TextEditingController();
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _fill(widget.state.settings.rules);
  }

  void _fill(CheckRules r) {
    _keywords.text = r.excludeKeywords.join('\n');
    _prefixes.text = r.excludePrefixes.join('\n');
    _ignore.text = r.ignoreRefPatterns.join('\n');
    _subs.text = r.substitutes.entries.map((e) => '${e.key}=${e.value.join(',')}').join('\n');
  }

  @override
  void dispose() {
    for (final c in [_keywords, _prefixes, _ignore, _subs]) {
      c.dispose();
    }
    super.dispose();
  }

  CheckRules _collect() {
    final subs = <String, List<String>>{};
    for (final line in _lines(_subs.text)) {
      final i = line.indexOf('=');
      if (i <= 0) continue;
      final main = line.substring(0, i).trim().toUpperCase();
      final alts = line.substring(i + 1).split(RegExp(r'[,，;；\s]+')).map((e) => e.trim().toUpperCase()).where((e) => e.isNotEmpty).toList();
      if (alts.isNotEmpty) subs.putIfAbsent(main, () => []).addAll(alts);
    }
    return CheckRules(
      excludeKeywords: _lines(_keywords.text),
      excludePrefixes: _lines(_prefixes.text),
      ignoreRefPatterns: _lines(_ignore.text),
      substitutes: subs,
    );
  }

  void _save() {
    widget.state.updateRules(_collect());
    setState(() => _saved = true);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final section = widget.state.rulesSection;

    Widget field(String label, Widget input) => Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(label, style: TextStyle(color: c.textDim, fontSize: 12.5, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            input,
          ]),
        );

    final body = switch (section) {
      RulesSection.exclusion => [
          field(s.t('rules_keywords'), TextInput(controller: _keywords, maxLines: 8, hint: s.t('rules_keywords_hint'))),
          if (widget.state.settings.rules.excludeKeywords.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Text(s.t('rules_keywords_empty'), style: TextStyle(color: c.textFaint, fontSize: 12)),
            ),
          field(s.t('rules_prefixes'), TextInput(controller: _prefixes, maxLines: 4, mono: true)),
        ],
      RulesSection.alternates => [
          field(s.t('rules_subs'), TextInput(controller: _subs, maxLines: 14, mono: true, hint: 'K1101-AAAA=K1101-BBBB,K1101-CCCC')),
          Text(s.t('rules_subs_note'), style: TextStyle(color: c.textFaint, fontSize: 12)),
        ],
      RulesSection.general => [
          field(s.t('rules_ignore_refs'), TextInput(controller: _ignore, maxLines: 6, mono: true, hint: s.t('rules_ignore_hint'))),
          Text(s.t('rules_user_only'), style: TextStyle(color: c.textFaint, fontSize: 12)),
        ],
    };
    final (glyph, title) = switch (section) {
      RulesSection.exclusion => (Glyph.exclusion, s.t('btn_exclusion')),
      RulesSection.alternates => (Glyph.alternates, s.t('btn_substitutes')),
      RulesSection.general => (Glyph.general, s.t('btn_general')),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: s.t('set_rules'),
          subtitle: _saved ? s.t('rules_saved') : s.t('page_rules_sub'),
          trailing: [
            Segmented<RulesSection>(
              value: section,
              options: [
                (RulesSection.exclusion, s.t('btn_exclusion')),
                (RulesSection.alternates, s.t('btn_substitutes')),
                (RulesSection.general, s.t('btn_general')),
              ],
              onChanged: widget.state.openRules,
            ),
            FlatButton(label: s.t('rules_reset'), compact: true, onTap: () => setState(() => _fill(CheckRules()))),
            FlatButton(label: s.t('dlg_save'), compact: true, primary: true, onTap: _save),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: 24 + bottomInset(context)),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: SurfaceCard(
                  padding: const EdgeInsets.fromLTRB(28, 22, 28, 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        GlyphIcon(glyph, size: 22, color: c.accent),
                        const SizedBox(width: 10),
                        Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
                      ]),
                      const SizedBox(height: 16),
                      const HDivider(),
                      const SizedBox(height: 16),
                      ...body,
                    ]),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
