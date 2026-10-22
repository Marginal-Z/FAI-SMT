/// Check result workspace: category tabs and the result table.
library;

import 'package:flutter/widgets.dart';
import 'icons.dart';

import '../app_state.dart';
import '../core/models.dart';
import '../l10n/strings.dart';
import 'actions.dart';
import 'theme.dart';
import 'widgets.dart';

class CheckView extends StatefulWidget {
  const CheckView({super.key, required this.state});

  final AppState state;

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
    if (_search.text != state.search) _search.text = state.search;

    final tabs = <(CheckCategory?, String, Color?)>[
      (null, s.t('cat_all'), null),
      (CheckCategory.pass, s.t('cat_pass'), c.pass),
      (CheckCategory.ng, s.t('cat_ng'), c.ng),
      (CheckCategory.excluded, s.t('cat_excluded'), c.excluded),
      (CheckCategory.substitute, s.t('cat_substitute'), c.substitute),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 38,
          decoration: BoxDecoration(color: c.panel, border: Border(bottom: BorderSide(color: c.border))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (cat, label, color) in tabs)
                TabItem(
                  label: label,
                  dense: true,
                  color: color,
                  active: state.filter == cat,
                  count: report == null ? null : (cat == null ? report.rows.length : report.count(cat)),
                  onTap: () => state.setFilter(cat),
                ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: TextInput(
                  controller: _search,
                  width: 260,
                  hint: s.t('search_hint'),
                  prefix: Ic.magnifyingGlass,
                  onChanged: state.setSearch,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: report == null
              ? EmptyState(icon: Ic.listChecks, text: s.t('empty_check'))
              : _table(context, state.visibleRows()),
        ),
      ],
    );
  }

  Widget _table(BuildContext context, List<CheckRow> rows) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth < _minTableWidth ? _minTableWidth : box.maxWidth;
      return ThinScrollbar(
        controller: _hScroll,
        horizontal: true,
        child: SingleChildScrollView(
          controller: _hScroll,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Column(
              children: [
                _HeaderRow(cells: [
                  s.t('col_no'), s.t('col_pn'), s.t('col_desc'), s.t('col_bom_qty'), s.t('col_smt_qty'),
                  s.t('col_bom_refs'), s.t('col_smt_refs'), s.t('col_side'), s.t('col_result'), s.t('col_reason'),
                ]),
                Expanded(
                  child: rows.isEmpty
                      ? EmptyState(icon: Ic.funnel, text: s.t('empty_filter'))
                      : ThinScrollbar(
                          controller: _vScroll,
                          child: ListView.builder(
                            controller: _vScroll,
                            itemCount: rows.length,
                            itemBuilder: (context, i) => _ResultRow(
                              index: i + 1,
                              row: rows[i],
                              selected: identical(widget.state.selected, rows[i]),
                              onTap: () => widget.state.select(rows[i]),
                              stripe: i.isOdd ? c.panelAlt : c.panel,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

const _minTableWidth = 1000.0;

/// Column layout: fixed widths or flex weights.
const _cols = <(double, int)>[
  (40, 0), // No.
  (150, 0), // Part no.
  (0, 3), // Description
  (66, 0), // BOM qty
  (66, 0), // SMT qty
  (0, 3), // BOM refs
  (0, 3), // SMT refs
  (48, 0), // Side
  (88, 0), // Result
  (0, 4), // Reason
];

Widget _cell(int i, Widget child, {Alignment align = Alignment.centerLeft}) {
  final (w, flex) = _cols[i];
  final padded = Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
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
      height: 34,
      decoration: BoxDecoration(color: c.panelAlt, border: Border(bottom: BorderSide(color: c.borderStrong))),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++)
            _cell(
              i,
              Text(cells[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textDim)),
              align: (i == 3 || i == 4) ? Alignment.center : Alignment.centerLeft,
            ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.index, required this.row, required this.selected, required this.onTap, required this.stripe});

  final int index;
  final CheckRow row;
  final bool selected;
  final VoidCallback onTap;
  final Color stripe;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final catColor = c.category(row.category);
    return Hoverable(
      onTap: onTap,
      cursor: SystemMouseCursors.basic,
      builder: (context, hover, _) => Container(
        decoration: BoxDecoration(
          color: selected ? c.selected : hover ? c.hover : stripe,
          border: Border(
            bottom: BorderSide(color: c.border),
            left: BorderSide(color: catColor, width: 3),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _cell(0, Text('$index', style: TextStyle(color: c.textFaint, fontSize: 12))),
            _cell(1, Text(row.partNo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
            _cell(2, Text(row.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.text))),
            _cell(3, Text(_qty(row.bomQty), style: TextStyle(color: c.text)), align: Alignment.center),
            _cell(4, Text(row.smtQty?.toString() ?? '-', style: TextStyle(color: c.text)), align: Alignment.center),
            _cell(5, _chips(context, row.bomRefs, strikeMissing: false)),
            _cell(6, _chips(context, row.smtRefs, strikeMissing: true)),
            _cell(7, Text(_sides(s, row.sides), style: TextStyle(color: c.textDim, fontSize: 12))),
            _cell(
              8,
              ResultBadge(
                text: categoryLabel(s, row.category),
                color: catColor,
                icon: switch (row.category) {
                  CheckCategory.pass => IcBold.checkCircle,
                  CheckCategory.ng => IcBold.xCircle,
                  CheckCategory.excluded => IcBold.prohibit,
                  CheckCategory.substitute => IcBold.arrowsLeftRight,
                },
              ),
            ),
            _cell(9, _reasons(context, row)),
          ],
        ),
      ),
    );
  }

  Widget _chips(BuildContext context, List<RefMark> marks, {required bool strikeMissing}) {
    final c = AppTheme.of(context);
    if (marks.isEmpty) return Text('-', style: TextStyle(color: c.textFaint));
    const limit = 60;
    final shown = marks.length > limit ? marks.sublist(0, limit) : marks;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final m in shown)
          RefChip(
            text: m.ref,
            color: c.refState(m.state),
            soft: c.refStateSoft(m.state),
            strike: strikeMissing && m.state == RefState.extra,
          ),
        if (marks.length > limit)
          Text('+${marks.length - limit}', style: TextStyle(color: c.textDim, fontSize: 12)),
      ],
    );
  }

  Widget _reasons(BuildContext context, CheckRow row) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    if (row.reasons.isEmpty) return Text('-', style: TextStyle(color: c.textFaint));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in row.reasons)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
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
                  child: Text(s.t(r.code, r.args),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: r.info ? c.textDim : c.text)),
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

String _sides(Strings s, Set<StationSide> sides) {
  if (sides.isEmpty) return '-';
  if (sides.length == 2) return 'A+B';
  return sides.first == StationSide.a ? 'A' : 'B';
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Container(
      color: c.window,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: c.textFaint),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: c.textDim)),
        ],
      ),
    );
  }
}
