/// BOM check page: the three import cards and the actions, one statistic
/// card per result (doubling as the filter), the AI analysis, search, the
/// part-by-part table with the differing cells filled, and the selected
/// part's field-by-field comparison.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../core/ai_check.dart';
import '../core/bom.dart';
import '../core/bom_compare.dart';
import '../core/refdes.dart';
import '../l10n/strings.dart';
import 'design.dart';
import 'import_bar.dart';
import 'lucide.dart';
import 'theme.dart';
import 'tour.dart';
import 'widgets.dart';

/// Tint behind AI findings.
Color aiTint(AppColors c) => c.dark ? const Color(0x3326B5B0) : const Color(0xFFDDF3F2);
Color aiText(AppColors c) => c.dark ? const Color(0xFF7FDCD6) : const Color(0xFF0B6E69);

Color _statusTint(AppColors c, DiffStatus s) => switch (s) {
  DiffStatus.same => c.okTint,
  DiffStatus.different => c.ngTint,
  DiffStatus.onlySingle => c.warnTint,
  DiffStatus.onlyMerged => c.blueTint,
};

Color _statusText(AppColors c, DiffStatus s) => switch (s) {
  DiffStatus.same => c.okTx,
  DiffStatus.different => c.ngTx,
  DiffStatus.onlySingle => c.warnTx,
  DiffStatus.onlyMerged => c.blueTx,
};

Color _statusSolid(AppColors c, DiffStatus s) => switch (s) {
  DiffStatus.same => c.okSolid,
  DiffStatus.different => c.ngSolid,
  DiffStatus.onlySingle => c.warnSolid,
  DiffStatus.onlyMerged => c.blue,
};

String statusLabel(Strings s, DiffStatus d) => s.t('status_${d.name}');

/// Field named by an AI finding: the standard fields translated, other
/// columns by their header.
String aiFieldLabel(Strings s, String field) => switch (field) {
  'description' => s.t('f_desc'),
  'quantity' => s.t('f_qty'),
  'refs' => s.t('f_refs'),
  'partNo' => s.t('f_part_no'),
  _ => field,
};

/// Label of a compared field.
String fieldLabel(Strings s, FieldCompare f) => switch (f.key) {
  'description' => s.t('f_desc'),
  'quantity' => s.t('f_qty'),
  'refs' => s.t('f_refs'),
  _ => f.header.isEmpty ? f.key.substring(4) : f.header,
};

/// [text] with the [spans] on a coloured background.
class HighlightText extends StatelessWidget {
  const HighlightText(this.text, this.spans, {super.key, required this.color, this.style, this.maxLines});

  final String text;
  final List<Span> spans;
  final Color color;
  final TextStyle? style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    if (spans.isEmpty || text.isEmpty) {
      return Text(text.isEmpty ? '—' : text, style: base, maxLines: maxLines, overflow: maxLines == null ? null : TextOverflow.ellipsis);
    }
    final sorted = [...spans]..sort((a, b) => a.$1 - b.$1);
    final parts = <TextSpan>[];
    var at = 0;
    for (final (s, e) in sorted) {
      final start = math.max(s, at), end = math.min(e, text.length);
      if (start >= end) continue;
      if (start > at) parts.add(TextSpan(text: text.substring(at, start)));
      parts.add(TextSpan(text: text.substring(start, end), style: TextStyle(backgroundColor: color, fontWeight: FontWeight.w700)));
      at = end;
    }
    if (at < text.length) parts.add(TextSpan(text: text.substring(at)));
    return Text.rich(TextSpan(children: parts), style: base, maxLines: maxLines, overflow: maxLines == null ? null : TextOverflow.ellipsis);
  }
}

class CheckView extends StatefulWidget {
  const CheckView({super.key, required this.state, this.cards = false});

  final AppState state;

  /// Narrow screens: rows as cards instead of table columns.
  final bool cards;

  @override
  State<CheckView> createState() => _CheckViewState();
}

class _CheckViewState extends State<CheckView> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _hScroll = ScrollController();
  final _page = ScrollController();

  /// Only parts the AI check flagged.
  bool _aiOnly = false;

  @override
  void initState() {
    super.initState();
    _search.text = widget.state.search;
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    _hScroll.dispose();
    _page.dispose();
    super.dispose();
  }

  void _setFilter(DiffStatus? f) {
    setState(() => _aiOnly = false);
    widget.state.setFilter(widget.state.filter == f ? null : f);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final report = state.report;
    final phone = isPhoneLayout(context);
    final narrow = widget.cards;
    final pad = EdgeInsets.fromLTRB(narrow ? 16 : 24, phone ? 4 : 6, narrow ? 16 : 24, 0);
    final imports = ImportBar(state: state);

    if (report == null) {
      final hint = DCard(
        radius: 24,
        child: EmptyState(icon: Lucide.clipboardCheck, text: s.t(state.ready ? 'empty_ready' : 'empty_check_import')),
      );
      if (phone) {
        return ListView(
          padding: EdgeInsets.fromLTRB(pad.left, pad.top, pad.right, bottomInset(context) + 12),
          children: [imports, const SizedBox(height: 14), SizedBox(height: 260, child: hint)],
        );
      }
      return Padding(
        padding: pad,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [imports, const SizedBox(height: 16), Expanded(child: hint), const SizedBox(height: 16)],
        ),
      );
    }
    if (_search.text != state.search) _search.text = state.search;

    final total = report.rows.length;
    final aiParts = state.aiParts;
    final statCards = <Widget>[
      for (final (st, icon) in [
        (DiffStatus.same, Lucide.check),
        (DiffStatus.different, Lucide.x),
        (DiffStatus.onlySingle, Lucide.minus),
        (DiffStatus.onlyMerged, Lucide.plus),
      ])
        _StatCard(
          label: statusLabel(s, st),
          icon: icon,
          value: report.count(st),
          total: total,
          tint: _statusTint(c, st),
          fg: _statusText(c, st),
          bar: _statusSolid(c, st),
          selected: !_aiOnly && state.filter == st,
          onTap: () => _setFilter(st),
        ),
      _StatCard(
        label: s.t('ai_findings'),
        icon: Lucide.sparkles,
        value: state.ai?.findings.length ?? 0,
        tint: aiTint(c),
        fg: aiText(c),
        bar: aiText(c),
        selected: _aiOnly,
        dim: state.ai == null,
        onTap: () {
          if (state.ai == null) return;
          state.setFilter(null);
          setState(() => _aiOnly = !_aiOnly);
        },
      ),
    ];
    final gap = phone ? 14.0 : 16.0;
    final stats = phone
        ? SizedBox(
            key: tourTargets.checkCards,
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: statCards.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) => SizedBox(width: 150, child: statCards[i]),
            ),
          )
        : IntrinsicHeight(
            key: tourTargets.checkCards,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < statCards.length; i++) ...[if (i > 0) const SizedBox(width: 12), Expanded(child: statCards[i])],
              ],
            ),
          );
    final wideTop = !phone && MediaQuery.sizeOf(context).width >= 1130;
    final top = wideTop
        ? Padding(
            padding: EdgeInsets.only(bottom: gap),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        KeyedSubtree(key: tourTargets.fileChecks, child: ImportCardsRow(state: state)),
                        const SizedBox(height: 12),
                        stats,
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(width: 236, child: ImportActions(state: state)),
                ],
              ),
            ),
          )
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [imports, SizedBox(height: gap), stats, SizedBox(height: gap)]);

    var visible = state.visibleRows();
    if (_aiOnly) visible = visible.where((r) => aiParts.contains(r.partNo)).toList();

    final search = PillSearch(controller: _search, hint: s.t('search_hint'), onChanged: state.setSearch);
    final count = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: s.t('count_prefix')),
          TextSpan(
            text: '${visible.length}',
            style: TextStyle(fontWeight: FontWeight.w600, color: c.tx, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          TextSpan(text: s.t('count_suffix')),
        ],
      ),
      style: TextStyle(fontSize: 14, color: c.tx2),
    );
    final resultSelect = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(s.t('f_result'), style: TextStyle(fontSize: 14, color: c.tx2)),
        const SizedBox(width: 10),
        DropdownSelect<DiffStatus?>(
          value: _aiOnly ? null : state.filter,
          width: 128,
          options: [(null, s.t('opt_all')), for (final d in DiffStatus.values) (d, statusLabel(s, d))],
          onChanged: (v) {
            setState(() => _aiOnly = false);
            state.setFilter(v);
          },
        ),
      ],
    );
    final columnsNote = _ColumnsNote(report: report);
    final filters = KeyedSubtree(
      key: tourTargets.checkFilters,
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: 12),
                Row(children: [resultSelect, const Spacer(), count]),
              ],
            )
          : Row(
              children: [
                SizedBox(width: 320, child: search),
                const SizedBox(width: 16),
                resultSelect,
                const SizedBox(width: 16),
                Expanded(child: columnsNote),
                const SizedBox(width: 16),
                count,
              ],
            ),
    );

    final aiPanel = _AiPanel(state: state);
    final showAi = state.settings.aiEnabled && state.aiStatus != AiStatus.idle;

    if (phone) return _phonePage(context, [top, if (showAi) ...[aiPanel, const SizedBox(height: 12)], filters, const SizedBox(height: 12)], visible, pad);

    final table = visible.isEmpty
        ? DCard(
            child: Center(
              child: Text(s.t('no_rows'), style: TextStyle(fontSize: 15, color: c.tx2)),
            ),
          )
        : narrow
        ? DCard(
            clip: true,
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: visible.length,
              itemBuilder: (context, i) => _RowCard(state: state, row: visible[i]),
            ),
          )
        : DCard(
            clip: true,
            child: LayoutBuilder(
              builder: (context, box) {
                final width = math.max(box.maxWidth, 980.0);
                return ThinScrollbar(
                  controller: _hScroll,
                  horizontal: true,
                  child: SingleChildScrollView(
                    controller: _hScroll,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: width,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Padding(padding: EdgeInsets.fromLTRB(12, 10, 12, 0), child: _HeaderRow()),
                          Expanded(
                            child: ThinScrollbar(
                              controller: _scroll,
                              child: ListView.builder(
                                controller: _scroll,
                                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                                itemCount: visible.length,
                                itemBuilder: (context, i) => _ResultRow(state: state, row: visible[i], index: i + 1, ai: aiParts.contains(visible[i].partNo)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
    final keyedTable = KeyedSubtree(key: tourTargets.checkTable, child: table);
    return LayoutBuilder(
      builder: (context, box) {
        final short = box.maxHeight < 900;
        final selected = state.selected != null;
        final side = box.maxWidth >= 1100 && (selected || showAi);
        // Right of the table: the selected part, else the AI analysis.
        final panel = selected ? _Detail(state: state) : aiPanel;
        final body = side
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: keyedTable),
                  const SizedBox(width: 16),
                  SizedBox(width: 380, child: panel),
                ],
              )
            : keyedTable;
        final children = [
          top,
          if (!side && showAi) ...[aiPanel, const SizedBox(height: 12)],
          filters,
          const SizedBox(height: 14),
          short ? SizedBox(height: math.max(440.0, box.maxHeight * 0.66), child: body) : Expanded(child: body),
          if (!side && selected) ...[const SizedBox(height: 14), SizedBox(height: 380, child: _Detail(state: state))],
          const SizedBox(height: 16),
        ];
        final column = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
        return Padding(
          padding: pad,
          child: short ? SingleChildScrollView(controller: _page, child: column) : column,
        );
      },
    );
  }

  /// Phones: one scrolling list of row cards; the selected part opens in a
  /// sheet over the bottom of the screen.
  Widget _phonePage(BuildContext context, List<Widget> head, List<CompareRow> visible, EdgeInsets pad) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final state = widget.state;
    final selected = state.selected;
    final aiParts = state.aiParts;
    return Stack(
      children: [
        ListView.builder(
          controller: _page,
          padding: EdgeInsets.fromLTRB(pad.left, pad.top, pad.right, bottomInset(context) + (selected == null ? 12 : 320)),
          itemCount: visible.length + head.length,
          itemBuilder: (context, i) {
            if (i < head.length) return head[i];
            final row = visible[i - head.length];
            final card = Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DCard(
                radius: 20,
                padding: EdgeInsets.zero,
                child: _RowCard(state: state, row: row, ai: aiParts.contains(row.partNo)),
              ),
            );
            return i == head.length ? KeyedSubtree(key: tourTargets.checkTable, child: card) : card;
          },
        ),
        if (visible.isEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomInset(context) + 40,
            child: Center(child: Text(s.t('no_rows'), style: TextStyle(fontSize: 15, color: c.tx2))),
          ),
        if (selected != null)
          Positioned(
            left: 8,
            right: 8,
            bottom: bottomInset(context),
            child: SizedBox(height: math.min(460.0, MediaQuery.sizeOf(context).height * 0.6), child: _Detail(state: state)),
          ),
      ],
    );
  }
}

/// Which other columns are compared, and which only one side has.
class _ColumnsNote extends StatelessWidget {
  const _ColumnsNote({required this.report});

  final CompareReport report;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final compared = [s.t('f_desc'), s.t('f_qty'), s.t('f_refs'), ...report.compared.values];
    final skipped = [...report.singleOnlyColumns, ...report.mergedOnlyColumns];
    return Hoverable(
      tooltip: skipped.isEmpty ? null : s.t('cols_skipped', {'cols': skipped.join('、')}),
      builder: (context, hover, _) => Text(
        s.t('cols_compared', {'cols': compared.join('、')}) + (skipped.isEmpty ? '' : s.t('cols_skipped_short', {'n': skipped.length})),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12.5, color: c.tx3),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.icon,
    required this.value,
    required this.tint,
    required this.fg,
    required this.bar,
    required this.selected,
    required this.onTap,
    this.total,
    this.dim = false,
  });

  final String label;
  final Lucide icon;
  final int value;
  final Color tint;
  final Color fg;
  final Color bar;
  final bool selected;
  final VoidCallback onTap;

  /// When set, the share and bar are shown.
  final int? total;

  /// Nothing to show yet (AI not run).
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final share = total == null || total == 0 ? null : value / total!;
    final pct = share == null ? '' : '${(share * 100).toStringAsFixed(share > 0 && share < 0.02 ? 1 : 0)}%';
    return Hoverable(
      onTap: onTap,
      builder: (context, hover, _) => Opacity(
        opacity: dim ? 0.55 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: c.r(20),
            border: Border.all(color: selected ? fg.withValues(alpha: 0.6) : (c.industrial ? c.lineStrong : const Color(0x00000000)), width: selected || !c.industrial ? 1.5 : 1),
            boxShadow: c.shadowSm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                    child: LucideIcon(icon, size: 14, color: fg, stroke: 2.4),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.tx),
                    ),
                  ),
                  Text(
                    '$value',
                    style: TextStyle(fontSize: 22, height: 1, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: c.tx, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: share != null ? TrackBar(value: share < 0.02 && value > 0 ? 0.02 : share, color: bar, height: 4) : const SizedBox(height: 4),
                  ),
                  const SizedBox(width: 8),
                  Text(pct, style: TextStyle(fontSize: 11.5, color: c.tx2, fontFeatures: const [FontFeature.tabularFigures()])),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Column widths: fixed px, or flex weight with a minimum.
const _cols = [
  (40.0, 0.0), // #
  (170.0, 0.0), // part number
  (280.0, 2.0), // description (single over A+B)
  (90.0, 0.0), // quantity
  (220.0, 1.4), // designators
  (110.0, 0.0), // other columns
  (96.0, 0.0), // result
];

Widget _gridRow(List<Widget> cells, {CrossAxisAlignment cross = CrossAxisAlignment.center}) => LayoutBuilder(
  builder: (context, box) {
    final fixed = _cols.fold<double>(0, (a, e) => a + e.$1);
    final flex = _cols.fold<double>(0, (a, e) => a + e.$2);
    final spare = math.max(box.maxWidth - fixed, 0.0);
    final shrink = box.maxWidth < fixed ? box.maxWidth / fixed : 1.0;
    return Row(
      crossAxisAlignment: cross,
      children: [
        for (var i = 0; i < cells.length; i++)
          SizedBox(
            width: _cols[i].$1 * shrink + (flex == 0 ? 0 : spare * _cols[i].$2 / flex),
            child: Align(alignment: i == cells.length - 1 ? Alignment.centerRight : (i == 3 ? Alignment.center : Alignment.centerLeft), child: cells[i]),
          ),
      ],
    );
  },
);

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final style = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.tx2);
    Text t(String key) => Text(s.t(key), maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: c.solid, borderRadius: c.r(14)),
      child: _gridRow([Text('#', style: style), t('f_part_no'), t('f_desc_both'), t('f_qty_both'), t('f_refs'), t('f_other'), t('f_result')]),
    );
  }
}

/// A value of each side, labelled, with its differing parts highlighted.
Widget _sides(BuildContext context, FieldCompare? f, {String? single, String? merged, int maxLines = 2}) {
  final c = AppTheme.of(context);
  final style = TextStyle(fontSize: 13, height: 1.35, color: c.tx);
  final tag = TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.tx3);
  final hl = c.dark ? const Color(0x66E0A030) : const Color(0xFFFFD98A);
  if (f == null) {
    return Text(single ?? merged ?? '—', maxLines: maxLines, overflow: TextOverflow.ellipsis, style: style);
  }
  if (f.equal) return HighlightText(f.single, const [], color: hl, style: style, maxLines: maxLines);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 30, child: Text(Strings.of(context).t('side_single'), style: tag)),
          Expanded(child: HighlightText(f.single, f.singleSpans, color: hl, style: style, maxLines: maxLines)),
        ],
      ),
      const SizedBox(height: 2),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 30, child: Text('A+B', style: tag)),
          Expanded(child: HighlightText(f.merged, f.mergedSpans, color: hl, style: style, maxLines: maxLines)),
        ],
      ),
    ],
  );
}

Widget _refChips(BuildContext context, CompareRow row, {int max = 8}) {
  final c = AppTheme.of(context);
  final s = Strings.of(context);
  final missing = row.missingRefs, extra = row.extraRefs;
  final all = row.single?.refs ?? row.merged?.refs ?? const <String>[];
  if (missing.isEmpty && extra.isEmpty) {
    if (all.isEmpty) return Text('—', style: TextStyle(color: c.tx3));
    final shown = sortedRefs(all).take(max).toList();
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final r in shown) DotChip(text: r, background: c.well, color: c.tx2),
        if (all.length > shown.length) Text('+${all.length - shown.length}', style: TextStyle(fontSize: 12, color: c.tx2)),
      ],
    );
  }
  final chips = [
    for (final r in missing) DotChip(text: '${s.t('ref_missing')} $r', background: c.ngTint, color: c.ngTx),
    for (final r in extra) DotChip(text: '${s.t('ref_extra')} $r', background: c.warnTint, color: c.warnTx),
  ];
  return Wrap(
    spacing: 5,
    runSpacing: 5,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      ...chips.take(max),
      if (chips.length > max) Text('+${chips.length - max}', style: TextStyle(fontSize: 12, color: c.tx2)),
    ],
  );
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.state, required this.row, required this.index, this.ai = false});

  final AppState state;
  final CompareRow row;
  final int index;

  /// The AI check flagged this part.
  final bool ai;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final selected = identical(state.selected, row);
    final desc = row.field('description');
    final qty = row.field('quantity');
    final otherDiffs = row.differences.where((f) => f.key.startsWith('col:')).toList();
    final diffBg = c.dark ? const Color(0x1FE0A030) : const Color(0xFFFFF6E0);
    Widget cell(Widget child, {bool diff = false}) => Container(
      margin: const EdgeInsets.only(right: 8),
      padding: diff ? const EdgeInsets.symmetric(horizontal: 6, vertical: 4) : EdgeInsets.zero,
      decoration: diff ? BoxDecoration(color: diffBg, borderRadius: c.r(8)) : null,
      child: child,
    );
    return Hoverable(
      onTap: () => state.select(selected ? null : row),
      cursor: SystemMouseCursors.basic,
      builder: (context, hover, _) => Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? c.rowSel
              : hover
              ? c.hover
              : null,
          borderRadius: c.r(14),
        ),
        child: _gridRow([
          Text('$index', style: TextStyle(fontSize: 13, color: c.tx3, fontFeatures: const [FontFeature.tabularFigures()])),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(row.partNo, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.tx)),
              if (row.sources.isNotEmpty) Text(row.sources.join(' + '), style: TextStyle(fontSize: 11, color: c.tx3)),
            ],
          ),
          cell(_sides(context, desc, single: row.single?.description, merged: row.merged?.description), diff: desc != null && !desc.equal),
          cell(
            qty == null
                ? Text(formatQuantity(row.single?.quantity ?? row.merged?.quantity), style: TextStyle(fontSize: 13, color: c.tx))
                : Text(
                    qty.equal ? qty.single : '${qty.single.isEmpty ? '—' : qty.single} / ${qty.merged.isEmpty ? '—' : qty.merged}',
                    style: TextStyle(fontSize: 13.5, fontWeight: qty.equal ? FontWeight.w400 : FontWeight.w700, color: qty.equal ? c.tx : c.ngTx, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
            diff: qty != null && !qty.equal,
          ),
          cell(_refChips(context, row, max: 6), diff: row.missingRefs.isNotEmpty || row.extraRefs.isNotEmpty),
          otherDiffs.isEmpty
              ? Text('—', style: TextStyle(color: c.tx3))
              : Hoverable(
                  tooltip: otherDiffs.map((f) => '${fieldLabel(s, f)}: ${f.single} ≠ ${f.merged}').join('\n'),
                  builder: (context, hover, _) => DBadge(text: s.t('other_diff', {'n': otherDiffs.length}), background: c.warnTint, color: c.warnTx),
                ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (ai) ...[
                Hoverable(
                  tooltip: s.t('ai_flagged'),
                  builder: (context, hover, _) => Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: aiTint(c), shape: BoxShape.circle),
                    child: LucideIcon(Lucide.sparkles, size: 12, color: aiText(c), stroke: 2.2),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              DBadge(text: statusLabel(s, row.status), background: _statusTint(c, row.status), color: _statusText(c, row.status)),
            ],
          ),
        ]),
      ),
    );
  }
}

/// Narrow screens: one card per part.
class _RowCard extends StatelessWidget {
  const _RowCard({required this.state, required this.row, this.ai = false});

  final AppState state;
  final CompareRow row;
  final bool ai;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final selected = identical(state.selected, row);
    final qty = row.field('quantity');
    return Hoverable(
      onTap: () => state.select(selected ? null : row),
      cursor: SystemMouseCursors.basic,
      builder: (context, hover, _) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: BoxDecoration(
          color: selected
              ? c.rowSel
              : hover
              ? c.hover
              : null,
          borderRadius: c.r(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(row.partNo, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.tx)),
                ),
                if (ai) ...[LucideIcon(Lucide.sparkles, size: 14, color: aiText(c), stroke: 2.2), const SizedBox(width: 6)],
                DBadge(text: statusLabel(s, row.status), background: _statusTint(c, row.status), color: _statusText(c, row.status)),
              ],
            ),
            const SizedBox(height: 6),
            _sides(context, row.field('description'), single: row.single?.description, merged: row.merged?.description),
            if (qty != null && !qty.equal) ...[
              const SizedBox(height: 4),
              Text(s.t('qty_pair', {'a': qty.single, 'b': qty.merged}), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.ngTx)),
            ],
            const SizedBox(height: 6),
            _refChips(context, row, max: 8),
          ],
        ),
      ),
    );
  }
}

/// The selected part: every compared field side by side, designator
/// differences and the AI's notes.
class _Detail extends StatelessWidget {
  const _Detail({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final row = state.selected!;
    final hl = c.dark ? const Color(0x66E0A030) : const Color(0xFFFFD98A);
    final findings = state.ai?.forPart(row.partNo).toList() ?? const <AiFinding>[];
    Widget label(String t) => Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.tx2));
    Widget field(String name, String a, String b, List<Span> sa, List<Span> sb, bool equal) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: equal ? c.well : (c.dark ? const Color(0x1FE0A030) : const Color(0xFFFFF6E0)), borderRadius: c.r(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: label(name)),
              LucideIcon(equal ? Lucide.check : Lucide.alert, size: 13, color: equal ? c.okTx : c.warnTx, stroke: 2.4),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 52, child: Text(s.t('side_single_long'), style: TextStyle(fontSize: 11.5, color: c.tx3))),
              Expanded(child: HighlightText(a, sa, color: hl, style: TextStyle(fontSize: 13, height: 1.4, color: c.tx))),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 52, child: Text('A+B', style: TextStyle(fontSize: 11.5, color: c.tx3))),
              Expanded(child: HighlightText(b, sb, color: hl, style: TextStyle(fontSize: 13, height: 1.4, color: c.tx))),
            ],
          ),
        ],
      ),
    );
    final body = <Widget>[
      Row(
        children: [
          Expanded(
            child: Text(row.partNo, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: c.tx)),
          ),
          DBadge(text: statusLabel(s, row.status), background: _statusTint(c, row.status), color: _statusText(c, row.status)),
          const SizedBox(width: 8),
          GlassButton(icon: Lucide.x, size: 30, iconSize: 14, tooltip: s.t('dlg_close'), onTap: () => state.select(null)),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        [
          if (row.single != null) s.t('src_single_rows', {'rows': row.single!.sources.map((x) => x.label).join(', ')}),
          if (row.merged != null) s.t('src_merged', {'src': row.merged!.recordIds.join(', ')}),
        ].join(' · '),
        style: TextStyle(fontSize: 12, color: c.tx3),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final k in {?row.single?.kind, ?row.merged?.kind}) DBadge(text: s.t('kind_${k.name}'), background: c.well, color: c.tx2),
          if (row.single?.dnp == true || row.merged?.dnp == true) DBadge(text: s.t('dnp_badge'), background: c.warnTint, color: c.warnTx),
        ],
      ),
      if ({...?row.single?.alternates, ...?row.merged?.alternates}.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(s.t('alt_list', {'alts': {...?row.single?.alternates, ...?row.merged?.alternates}.join(', ')}), style: TextStyle(fontSize: 12, color: c.tx2)),
      ],
      const SizedBox(height: 12),
      if (row.status == DiffStatus.onlySingle || row.status == DiffStatus.onlyMerged) ...[
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: _statusTint(c, row.status), borderRadius: c.r(12)),
          child: Text(s.t('why_${row.status.name}'), style: TextStyle(fontSize: 13, height: 1.45, color: _statusText(c, row.status))),
        ),
        const SizedBox(height: 10),
        field(s.t('f_desc'), row.single?.description ?? '', row.merged?.description ?? '', const [], const [], true),
      ],
      for (final f in row.fields)
        if (f.key != 'refs') field(fieldLabel(s, f), f.single, f.merged, f.singleSpans, f.mergedSpans, f.equal),
      if (row.field('refs') != null || row.missingRefs.isNotEmpty || row.extraRefs.isNotEmpty) ...[
        label(s.t('f_refs')),
        const SizedBox(height: 6),
        if (row.missingRefs.isEmpty && row.extraRefs.isEmpty)
          Text(s.t('refs_same', {'n': row.single?.refs.length ?? 0}), style: TextStyle(fontSize: 13, color: c.okTx))
        else ...[
          if (row.missingRefs.isNotEmpty)
            Text(s.t('refs_missing_list', {'refs': row.missingRefs.join(', ')}), style: TextStyle(fontSize: 13, height: 1.45, color: c.ngTx)),
          if (row.extraRefs.isNotEmpty)
            Text(s.t('refs_extra_list', {'refs': row.extraRefs.join(', ')}), style: TextStyle(fontSize: 13, height: 1.45, color: c.warnTx)),
        ],
        for (final e in row.movedRefs.entries)
          Text(s.t('ref_moved', {'ref': e.key, 'pn': e.value}), style: TextStyle(fontSize: 12.5, height: 1.45, color: c.tx2)),
        const SizedBox(height: 10),
      ],
      if (findings.isNotEmpty) ...[
        Row(
          children: [
            LucideIcon(Lucide.sparkles, size: 14, color: aiText(c), stroke: 2.2),
            const SizedBox(width: 6),
            label(s.t('ai_notes')),
          ],
        ),
        const SizedBox(height: 6),
        for (final f in findings) _FindingCard(finding: f),
      ],
    ];
    return DCard(
      radius: 22,
      clip: true,
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body),
      ),
    );
  }
}

class _FindingCard extends StatelessWidget {
  const _FindingCard({required this.finding, this.onTap});

  final AiFinding finding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final f = finding;
    final sev = switch (f.severity) {
      AiSeverity.error => (c.ngTint, c.ngTx),
      AiSeverity.warning => (c.warnTint, c.warnTx),
      AiSeverity.info => (c.well, c.tx2),
    };
    return Hoverable(
      onTap: onTap,
      cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      builder: (context, hover, _) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: hover && onTap != null ? Color.alphaBlend(c.hover, aiTint(c)) : aiTint(c), borderRadius: c.r(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DBadge(text: s.t('ai_sev_${f.severity.name}'), background: sev.$1, color: sev.$2),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    [if (onTap != null) f.partNo, aiFieldLabel(s, f.field)].where((x) => x.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: aiText(c)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(f.message, style: TextStyle(fontSize: 13, height: 1.45, color: c.tx)),
            if (f.singleValue.isNotEmpty || f.mergedValue.isNotEmpty) ...[
              const SizedBox(height: 6),
              if (f.singleValue.isNotEmpty) Text('${s.t('side_single_long')}: ${f.singleValue}', style: TextStyle(fontSize: 12, color: c.tx2)),
              if (f.mergedValue.isNotEmpty) Text('A+B: ${f.mergedValue}', style: TextStyle(fontSize: 12, color: c.tx2)),
            ],
          ],
        ),
      ),
    );
  }
}

/// The AI analysis: running, failed (with the reason and a retry), or the
/// summary and findings; a finding opens its part.
class _AiPanel extends StatelessWidget {
  const _AiPanel({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final ai = state.ai;
    final header = Row(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: aiTint(c), borderRadius: c.r(9)),
          child: LucideIcon(Lucide.sparkles, size: 16, color: aiText(c), stroke: 2.2),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.t('ai_analysis'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.tx)),
              Text(
                ai == null ? state.settings.ai.modelName : '${ai.model} · ${formatTime(ai.at)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: c.tx3),
              ),
            ],
          ),
        ),
        if (state.aiStatus == AiStatus.running)
          GlassButton(icon: Lucide.x, size: 30, iconSize: 14, tooltip: s.t('dlg_cancel'), onTap: state.cancelAi)
        else
          GlassButton(icon: Lucide.refresh, size: 30, iconSize: 14, tooltip: s.t('ai_rerun'), onTap: state.runAi),
      ],
    );
    final List<Widget> body = switch (state.aiStatus) {
      AiStatus.running => [
        Row(
          children: [
            const Spinner(size: 16),
            const SizedBox(width: 10),
            Expanded(child: Text(s.t('ai_running_long'), style: TextStyle(fontSize: 13, color: c.tx2))),
          ],
        ),
      ],
      AiStatus.failed => [
        Text(s.t(state.aiError), style: TextStyle(fontSize: 13, height: 1.45, color: c.ngTx)),
        if (state.aiErrorDetail.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(state.aiErrorDetail, maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.tx3)),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            PillButton(label: s.t('ai_rerun'), icon: Lucide.refresh, kind: PillKind.soft, height: 34, fontSize: 13, onTap: state.runAi),
            const SizedBox(width: 8),
            PillButton(label: s.t('set_ai'), kind: PillKind.ghost, height: 34, fontSize: 13, onTap: () => state.openSettings(SettingsSection.ai)),
          ],
        ),
      ],
      _ when ai != null => [
        Text(ai.summary.isEmpty ? s.t('ai_no_summary') : ai.summary, style: TextStyle(fontSize: 13.5, height: 1.55, color: c.tx)),
        const SizedBox(height: 12),
        if (ai.findings.isEmpty)
          Text(s.t('ai_no_findings'), style: TextStyle(fontSize: 13, color: c.okTx))
        else
          for (final f in ai.findings)
            _FindingCard(
              finding: f,
              onTap: () {
                final row = state.report?.rows.where((r) => r.partNo == f.partNo).firstOrNull;
                if (row != null) state.select(row);
              },
            ),
      ],
      _ => [Text(s.t('ai_on'), style: TextStyle(fontSize: 13, color: c.tx2))],
    };
    return DCard(
      radius: 22,
      clip: true,
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, const SizedBox(height: 14), ...body]),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text, this.action});

  final Lucide icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      // Short cards (large interface zoom) scale the content down.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.well, shape: BoxShape.circle, border: c.cardBorder),
            child: LucideIcon(icon, size: 30, color: c.tx2),
          ),
          const SizedBox(height: 18),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: c.tx2, fontSize: 15, height: 1.5)),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
      ),
    );
  }
}
