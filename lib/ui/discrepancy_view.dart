/// Discrepancy list: every inconsistency with severity, source, problem and
/// an explanation of cause and effect.
library;

import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../core/discrepancies.dart';
import '../l10n/strings.dart';
import 'check_view.dart';
import 'icons.dart';
import 'theme.dart';
import 'widgets.dart';

String sourceLabel(Strings s, Source src) => s.t('src_${src.name}');

String severityLabel(Strings s, Severity v) => s.t('sev_${v.name}');

/// Problem text; designator lists are shown as chips, so `{refs}` is dropped
/// from the sentence when chips are present.
String problemText(Strings s, Discrepancy d) {
  final args = {...d.args};
  if (d.refs.length > 1) args['refs'] = '';
  return s.t(d.code, args).replaceAll(RegExp(r'[:：]\s*$'), '');
}

class DiscrepancyView extends StatefulWidget {
  const DiscrepancyView({super.key, required this.state, required this.items});

  final AppState state;
  final List<Discrepancy> items;

  @override
  State<DiscrepancyView> createState() => _DiscrepancyViewState();
}

class _DiscrepancyViewState extends State<DiscrepancyView> {
  Severity? _filter;
  final _search = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final items = widget.items;
    int count(Severity? v) => v == null ? items.length : items.where((d) => d.severity == v).length;
    final q = _search.text.trim().toUpperCase();
    final shown = items.where((d) {
      if (_filter != null && d.severity != _filter) return false;
      if (q.isEmpty) return true;
      return d.subject.toUpperCase().contains(q) || d.refs.contains(q) || problemText(s, d).toUpperCase().contains(q);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: c.window,
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final (v, color) in [
                (null, c.textDim),
                (Severity.error, c.ng),
                (Severity.warning, c.substitute),
                (Severity.info, c.accent),
              ])
                FilterPill(
                  label: v == null ? s.t('sev_all') : severityLabel(s, v),
                  color: color,
                  count: count(v),
                  active: _filter == v,
                  onTap: () => setState(() => _filter = v),
                ),
              const SizedBox(width: 8),
              SizedBox(
                width: 300,
                child: TextInput(
                  controller: _search,
                  hint: s.t('search_hint'),
                  prefix: Ic.magnifyingGlass,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? EmptyState(icon: Ic.checkCircle, text: s.t(items.isEmpty ? 'empty_discrepancies' : 'empty_filter'))
              : Container(
                  color: c.window,
                  child: ThinScrollbar(
                    controller: _scroll,
                    child: ListView.separated(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => _DiscrepancyCard(d: shown[i]),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _DiscrepancyCard extends StatelessWidget {
  const _DiscrepancyCard({required this.d});

  final Discrepancy d;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final color = switch (d.severity) {
      Severity.error => c.ng,
      Severity.warning => c.substitute,
      Severity.info => c.accent,
    };
    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: c.r(8),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(left: 0, top: 0, bottom: 0, width: 3, child: ColoredBox(color: color)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 11, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Tag(text: severityLabel(s, d.severity), color: color),
                    const SizedBox(width: 6),
                    _Tag(text: sourceLabel(s, d.source), color: c.textDim, outlined: true),
                    const SizedBox(width: 10),
                    if (d.subject.isNotEmpty)
                      Flexible(
                        child: Text(
                          d.subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.text),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  problemText(s, d),
                  style: TextStyle(fontSize: 13, color: c.text, fontWeight: FontWeight.w500),
                ),
                if (d.refs.length > 1) ...[
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final r in d.refs.take(80)) RefChip(text: r, color: color, soft: color.withValues(alpha: 0.1)),
                      if (d.refs.length > 80) Text('+${d.refs.length - 80}', style: TextStyle(fontSize: 12, color: c.textDim)),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                Text(s.t('why_${d.code}'), style: TextStyle(fontSize: 12.5, color: c.textDim, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color, this.outlined = false});

  final String text;
  final Color color;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: outlined ? c.panelAlt : color.withValues(alpha: 0.13),
        borderRadius: c.r(4),
        border: Border.all(color: outlined ? c.border : color.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
