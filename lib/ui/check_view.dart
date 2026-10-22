/// Check result workspace: result-area filters, the result table (or cards on
/// narrow screens) and the import guide shown before the first check.
library;

import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../core/models.dart';
import '../l10n/strings.dart';
import 'actions.dart';
import 'icons.dart';
import 'panels.dart';
import 'theme.dart';
import 'widgets.dart';

class CheckView extends StatefulWidget {
  const CheckView({super.key, required this.state, this.cards = false});

  final AppState state;

  /// Card list instead of the wide table (portrait tablets).
  final bool cards;

  @override
  State<CheckView> createState() => _CheckViewState();
}

class _CheckViewState extends State<CheckView> {
  final _search = TextEditingController();
  final _vScroll = ScrollController();
  final _hScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _search.text = widget.state.search;
  }

  @override
  void dispose() {
    _search.dispose();
    _vScroll.dispose();
    _hScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final report = state.report;
    final stations = [state.stationA?.name, state.stationB?.name].whereType<String>().length;
    final header = PageHeader(
      title: s.t('mod_check'),
      subtitle: state.bom == null ? null : s.t('page_check_sub', {'bom': state.bom!.name, 'stations': stations}),
    );
    if (report == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        Expanded(
          child: EmptyState(
            icon: Ic.listChecks,
            text: s.t('empty_check'),
            action: state.bom != null && stations > 0
                ? FlatButton(label: s.t('btn_run'), primary: true, onTap: () => runCheck(context, state))
                : FlatButton(label: s.t('go_files'), onTap: () => state.setModule(Module.files)),
          ),
        ),
      ]);
    }
    if (_search.text != state.search) _search.text = state.search;

    final total = report.rows.length;
    final kpis = <(CheckCategory?, String, Color)>[
      (null, s.t('cat_all'), c.textDim),
      (CheckCategory.pass, s.t('cat_pass'), c.pass),
      (CheckCategory.ng, s.t('cat_ng'), c.ng),
      (CheckCategory.excluded, s.t('cat_excluded'), c.excluded),
      (CheckCategory.substitute, s.t('cat_substitute'), c.substitute),
    ];
    final search = TextInput(controller: _search, hint: s.t('search_hint'), prefix: Ic.magnifyingGlass, onChanged: state.setSearch);
    final rows = state.visibleRows();

    return LayoutBuilder(builder: (context, box) {
      final dockInspector = box.maxWidth >= 1240 && !widget.cards;
      final results = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(color: c.window, border: Border(bottom: BorderSide(color: c.border))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final (cat, label, color) in kpis) ...[
                    KpiCard(
                      label: label,
                      value: cat == null ? total : report.count(cat),
                      total: total,
                      color: color,
                      active: state.filter == cat,
                      onTap: () => state.setFilter(cat),
                    ),
                    const SizedBox(width: 10),
                  ],
                ]),
              ),
              const SizedBox(height: 12),
              if (widget.cards) search else Align(alignment: Alignment.centerLeft, child: SizedBox(width: 320, child: search)),
            ]),
          ),
          Expanded(
            child: rows.isEmpty
                ? EmptyState(icon: Ic.funnel, text: s.t('empty_filter'))
                : widget.cards
                    ? _cardList(rows)
                    : _table(context, rows),
          ),
        ],
      );
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        Expanded(
          child: Stack(children: [
            Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: results),
              if (dockInspector) ...[const VDivider(), SizedBox(width: 300, child: InspectorPanel(state: state))],
            ]),
            if (!dockInspector && state.selected != null)
              Positioned.fill(
                child: OverlayPanel(
                  width: 360,
                  onClose: () => state.select(null),
                  child: InspectorPanel(state: state, onClose: () => state.select(null)),
                ),
              ),
          ]),
        ),
      ]);
    });
  }

  Widget _cardList(List<CheckRow> rows) {
    final c = AppTheme.of(context);
    return Container(
      color: c.window,
      child: ThinScrollbar(
        controller: _vScroll,
        child: ListView.separated(
          controller: _vScroll,
          padding: const EdgeInsets.all(12),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) =>
              _ResultCard(row: rows[i], selected: identical(widget.state.selected, rows[i]), onTap: () => widget.state.select(rows[i])),
        ),
      ),
    );
  }

  Widget _table(BuildContext context, List<CheckRow> rows) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth < _minTableWidth ? _minTableWidth : box.maxWidth;
        return Container(
          color: c.panel,
          child: ThinScrollbar(
            controller: _hScroll,
            horizontal: true,
            child: SingleChildScrollView(
              controller: _hScroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                child: Column(
                  children: [
                    _HeaderRow(
                      cells: [
                        s.t('col_no'),
                        s.t('col_pn'),
                        s.t('col_desc'),
                        s.t('col_bom_qty'),
                        s.t('col_smt_qty'),
                        s.t('col_bom_refs'),
                        s.t('col_smt_refs'),
                        s.t('col_side'),
                        s.t('col_result'),
                        s.t('col_reason'),
                      ],
                    ),
                    Expanded(
                      child: ThinScrollbar(
                        controller: _vScroll,
                        child: ListView.builder(
                          controller: _vScroll,
                          itemCount: rows.length,
                          itemBuilder: (context, i) => _ResultRow(
                            index: i + 1,
                            row: rows[i],
                            selected: identical(widget.state.selected, rows[i]),
                            onTap: () => widget.state.select(rows[i]),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

const _minTableWidth = 1000.0;

/// Column layout: fixed widths or flex weights.
const _cols = <(double, int)>[
  (44, 0), // No.
  (150, 0), // Part no.
  (0, 3), // Description
  (70, 0), // BOM qty
  (70, 0), // SMT qty
  (0, 4), // BOM refs
  (0, 4), // SMT refs
  (50, 0), // Side
  (92, 0), // Result
  (0, 4), // Reason
];

Widget _cell(int i, Widget child, double padV, {Alignment align = Alignment.centerLeft}) {
  final (w, flex) = _cols[i];
  final padded = Padding(
    padding: EdgeInsets.symmetric(horizontal: 8, vertical: padV),
    child: Align(alignment: align, child: child),
  );
  return flex > 0 ? Expanded(flex: flex, child: padded) : SizedBox(width: w, child: padded);
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.cells});

  final List<String> cells;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Container(
      height: Metrics.of(context).touch ? 40 : 36,
      decoration: BoxDecoration(
        color: c.panelAlt,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 3),
          for (var i = 0; i < cells.length; i++)
            _cell(
              i,
              Text(
                cells[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textDim, letterSpacing: 0.2),
              ),
              0,
              align: (i == 3 || i == 4) ? Alignment.center : Alignment.centerLeft,
            ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.index, required this.row, required this.selected, required this.onTap});

  final int index;
  final CheckRow row;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final pad = Metrics.of(context).rowPad;
    final catColor = c.category(row.category);
    final mono = TextStyle(fontSize: 13, color: c.text, fontFeatures: const [FontFeature.tabularFigures()]);
    return Hoverable(
      onTap: onTap,
      cursor: SystemMouseCursors.basic,
      builder: (context, hover, _) => Container(
        decoration: BoxDecoration(
          color: selected
              ? c.selected
              : hover
              ? c.hover
              : null,
          border: Border(
            bottom: BorderSide(color: c.border),
            left: BorderSide(color: row.category == CheckCategory.pass ? catColor.withValues(alpha: 0.55) : catColor, width: 3),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _cell(0, Text('$index', style: TextStyle(color: c.textFaint, fontSize: 12)), pad),
            _cell(
              1,
              Text(
                row.partNo,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: c.text),
              ),
              pad,
            ),
            _cell(
              2,
              Text(
                row.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.text, fontSize: 12.5),
              ),
              pad,
            ),
            _cell(3, Text(_qty(row.bomQty), style: mono), pad, align: Alignment.center),
            _cell(4, Text(row.smtQty?.toString() ?? '-', style: mono), pad, align: Alignment.center),
            _cell(5, RefChips(marks: row.bomRefs), pad),
            _cell(6, RefChips(marks: row.smtRefs, strikeExtra: true), pad),
            _cell(7, Text(_sides(row.sides), style: TextStyle(color: c.textDim, fontSize: 12)), pad),
            _cell(8, CategoryBadge(category: row.category, label: categoryLabel(s, row.category)), pad),
            _cell(9, ReasonList(row: row), pad),
          ],
        ),
      ),
    );
  }
}

/// One result as a card (portrait tablets).
class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.row, required this.selected, required this.onTap});

  final CheckRow row;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final catColor = c.category(row.category);
    final dim = TextStyle(fontSize: 12, color: c.textDim);
    final extras = row.smtRefs.where((m) => m.state == RefState.extra).toList();
    return Hoverable(
      onTap: onTap,
      cursor: SystemMouseCursors.basic,
      builder: (context, hover, _) => Container(
        decoration: BoxDecoration(
          color: selected ? c.selected : c.panel,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? c.accent.withValues(alpha: 0.6) : c.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(left: 0, top: 0, bottom: 0, width: 4, child: ColoredBox(color: catColor)),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          row.partNo,
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: c.text),
                        ),
                      ),
                      CategoryBadge(category: row.category, label: categoryLabel(s, row.category)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    row.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: c.text),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${s.t('col_bom_qty')} ${_qty(row.bomQty)}   ·   ${s.t('col_smt_qty')} ${row.smtQty ?? '-'}   ·   ${s.t('col_side')} ${_sides(row.sides)}',
                    style: dim,
                  ),
                  if (row.bomRefs.isNotEmpty || extras.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    RefChips(marks: [...row.bomRefs, ...extras], strikeExtra: true, limit: 40),
                  ],
                  if (row.reasons.isNotEmpty) ...[const SizedBox(height: 8), ReasonList(row: row)],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Designator chips coloured by their check state.
class RefChips extends StatelessWidget {
  const RefChips({super.key, required this.marks, this.strikeExtra = false, this.limit = 60});

  final List<RefMark> marks;
  final bool strikeExtra;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    if (marks.isEmpty) return Text('-', style: TextStyle(color: c.textFaint));
    final shown = marks.length > limit ? marks.sublist(0, limit) : marks;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final m in shown)
          RefChip(text: m.ref, color: c.refState(m.state), soft: c.refStateSoft(m.state), strike: strikeExtra && m.state == RefState.extra),
        if (marks.length > limit) Text('+${marks.length - limit}', style: TextStyle(color: c.textDim, fontSize: 12)),
      ],
    );
  }
}

class CategoryBadge extends StatelessWidget {
  const CategoryBadge({super.key, required this.category, required this.label});

  final CheckCategory category;
  final String label;

  @override
  Widget build(BuildContext context) => ResultBadge(
    text: label,
    color: AppTheme.of(context).category(category),
    icon: switch (category) {
      CheckCategory.pass => IcBold.checkCircle,
      CheckCategory.ng => IcBold.xCircle,
      CheckCategory.excluded => IcBold.prohibit,
      CheckCategory.substitute => IcBold.arrowsLeftRight,
    },
  );
}

class ReasonList extends StatelessWidget {
  const ReasonList({super.key, required this.row});

  final CheckRow row;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    if (row.reasons.isEmpty) return Text('-', style: TextStyle(color: c.textFaint));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in row.reasons)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1.5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3, right: 6),
                  child: Icon(
                    r.info ? Ic.info : Ic.warning,
                    size: 13,
                    color: r.info ? (row.category == CheckCategory.excluded ? c.excluded : c.substitute) : c.ng,
                  ),
                ),
                Expanded(
                  child: Text(
                    s.t(r.code, r.args),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: r.info ? c.textDim : c.text),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

String _qty(double? q) {
  if (q == null) return '-';
  return q == q.roundToDouble() ? q.toInt().toString() : q.toString();
}

String _sides(Set<StationSide> sides) {
  if (sides.isEmpty) return '-';
  if (sides.length == 2) return 'A+B';
  return sides.first == StationSide.a ? 'A' : 'B';
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Container(
      color: c.window,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.panel, shape: BoxShape.circle, border: Border.all(color: c.border)),
            child: Icon(icon, size: 30, color: c.textFaint),
          ),
          const SizedBox(height: 16),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: c.textDim, fontSize: 13)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// Result-area statistic that doubles as a filter.
class KpiCard extends StatelessWidget {
  const KpiCard({super.key, required this.label, required this.value, required this.total, required this.color, required this.active, required this.onTap});

  final String label;
  final int value;
  final int total;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final m = Metrics.of(context);
    final share = total == 0 ? 0.0 : value / total;
    return Hoverable(
      onTap: onTap,
      builder: (context, hover, _) => Container(
        width: m.touch ? 150 : 142,
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: c.dark ? 0.14 : 0.07) : hover ? c.hover : c.panel,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: active ? color.withValues(alpha: 0.8) : c.border, width: active ? 1.5 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 7),
            Expanded(
              child: Text(label,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.textDim, fontWeight: FontWeight.w500)),
            ),
          ]),
          const SizedBox(height: 6),
          Text('$value',
              style: TextStyle(
                fontSize: 24,
                height: 1.1,
                fontWeight: FontWeight.w700,
                color: c.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 4,
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (share > 0) Expanded(flex: (share * 1000).round().clamp(1, 1000), child: ColoredBox(color: color)),
                if (share < 1) Expanded(flex: (1000 - share * 1000).round().clamp(1, 1000), child: ColoredBox(color: c.border)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
