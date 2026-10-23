/// Check module page. Results are grouped into their result areas (NG,
/// alternates, excluded, PASS), each collapsed by default; a row expands in
/// place to show every designator and the reasons with explanations.
library;

import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../core/models.dart';
import '../l10n/strings.dart';
import 'actions.dart';
import 'discrepancy_view.dart';
import 'icons.dart';
import 'theme.dart';
import 'widgets.dart';

const _areaOrder = [CheckCategory.ng, CheckCategory.substitute, CheckCategory.excluded, CheckCategory.pass];

String _areaLabel(Strings s, CheckCategory c) => s.t(switch (c) {
  CheckCategory.pass => 'area_pass',
  CheckCategory.ng => 'area_ng',
  CheckCategory.excluded => 'area_excluded',
  CheckCategory.substitute => 'area_substitute',
});

class CheckView extends StatefulWidget {
  const CheckView({super.key, required this.state, this.cards = false});

  final AppState state;

  /// Narrow screens: two-line rows instead of table columns.
  final bool cards;

  @override
  State<CheckView> createState() => _CheckViewState();
}

/// One entry of the item list: a row, or the details of the expanded row.
sealed class _Entry {}

class _Row extends _Entry {
  _Row(this.row, this.index, this.first);

  final CheckRow row;
  final int index;

  /// First row of an area (draws the column header above it).
  final bool first;
}

class _Details extends _Entry {
  _Details(this.row);

  final CheckRow row;
}

class _CheckViewState extends State<CheckView> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _hScroll = ScrollController();
  CheckCategory? _area;
  CheckRow? _expanded;

  @override
  void initState() {
    super.initState();
    _search.text = widget.state.search;
    // Open the area of a part selected elsewhere (e.g. the PCB navigator),
    // or the area picked as a filter.
    final sel = widget.state.selected;
    if (sel != null) {
      _expanded = sel;
      _area = sel.category;
    } else {
      _area = widget.state.filter;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    _hScroll.dispose();
    super.dispose();
  }

  void _toggleRow(CheckRow row) {
    setState(() => _expanded = identical(_expanded, row) ? null : row);
    widget.state.select(_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final report = state.report;
    final stations = [state.stationA?.name, state.stationB?.name].whereType<String>().length;
    final header = PageHeader(
      title: state.checkView == CheckPageView.discrepancies ? s.t('view_discrepancies') : s.t('mod_check'),
      subtitle: state.bom == null ? null : s.t('page_check_sub', {'bom': state.bom!.name, 'stations': stations}),
    );
    if (report == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
        ],
      );
    }
    if (state.checkView == CheckPageView.discrepancies) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(
            child: DiscrepancyView(state: state, items: state.discrepancies ?? const []),
          ),
        ],
      );
    }
    if (_search.text != state.search) _search.text = state.search;

    final searching = state.search.trim().isNotEmpty;
    final visible = state.visibleRows();
    final entries = <_Entry>[];
    for (final cat in _areaOrder) {
      if (!searching && cat != _area) continue;
      final rows = visible.where((r) => r.category == cat).toList();
      for (var i = 0; i < rows.length; i++) {
        entries.add(_Row(rows[i], i + 1, i == 0));
        if (identical(_expanded, rows[i])) entries.add(_Details(rows[i]));
      }
    }

    final cards = Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      color: c.window,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var i = 0; i < _areaOrder.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                  child: _AreaCard(
                    label: _areaLabel(s, _areaOrder[i]),
                    count: report.count(_areaOrder[i]),
                    total: report.rows.length,
                    color: c.category(_areaOrder[i]),
                    active: !searching && _area == _areaOrder[i],
                    onTap: () => setState(() {
                      _area = _area == _areaOrder[i] ? null : _areaOrder[i];
                      if (searching) state.setSearch('');
                    }),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 340,
                child: TextInput(controller: _search, hint: s.t('search_hint'), prefix: Ic.magnifyingGlass, onChanged: state.setSearch),
              ),
              const Spacer(),
              Text(s.t('check_total', {'n': report.rows.length}), style: TextStyle(fontSize: 12, color: c.textDim)),
            ],
          ),
        ],
      ),
    );

    Widget body;
    if (!searching && _area == null) {
      body = EmptyState(icon: Ic.listChecks, text: s.t('area_hint'));
    } else if (entries.isEmpty) {
      body = EmptyState(icon: Ic.funnel, text: s.t(searching ? 'empty_filter' : 'area_empty'));
    } else {
      final list = ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: entries.length,
        itemBuilder: (context, i) => switch (entries[i]) {
          _Row(:final row, :final index, :final first) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (first) ...[
                if (i > 0) const SizedBox(height: 12),
                if (!widget.cards) _ColumnHeader() else Container(height: 1, color: c.border),
              ],
              _ResultRow(
                row: row,
                index: index,
                expanded: identical(_expanded, row),
                cards: widget.cards,
                last: i + 1 >= entries.length || (entries[i + 1] is _Row && (entries[i + 1] as _Row).first),
                onTap: () => _toggleRow(row),
              ),
            ],
          ),
          _Details(:final row) => _RowDetails(
            row: row,
            last: i + 1 >= entries.length || (entries[i + 1] is _Row && (entries[i + 1] as _Row).first),
          ),
        },
      );
      body = widget.cards
          ? ThinScrollbar(controller: _scroll, child: list)
          : LayoutBuilder(
              builder: (context, box) => ThinScrollbar(
                controller: _hScroll,
                horizontal: true,
                child: SingleChildScrollView(
                  controller: _hScroll,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: box.maxWidth < _minWidth ? _minWidth : box.maxWidth,
                    child: ThinScrollbar(controller: _scroll, child: list),
                  ),
                ),
              ),
            );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        cards,
        Expanded(
          child: Container(color: c.window, child: body),
        ),
      ],
    );
  }
}

/// Result-area card: name, count and share; selecting it lists its items.
class _AreaCard extends StatelessWidget {
  const _AreaCard({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int count;
  final int total;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final m = Metrics.of(context);
    final share = total == 0 ? 0.0 : count / total;
    return Hoverable(
      onTap: onTap,
      builder: (context, hover, _) => Container(
        padding: EdgeInsets.fromLTRB(16, m.touch ? 14 : 12, 16, m.touch ? 14 : 12),
        decoration: BoxDecoration(
          color: active
              ? color.withValues(alpha: c.dark ? 0.14 : 0.07)
              : hover
              ? c.hover
              : c.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? color.withValues(alpha: 0.85) : c.border, width: active ? 1.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: c.textDim, fontWeight: FontWeight.w600),
                  ),
                ),
                CustomPaint(size: const Size(11, 11), painter: _ChevronPainter(active ? color : c.textFaint, active)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 26,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: count == 0 ? c.textFaint : c.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '${(share * 100).toStringAsFixed(share > 0 && share < 0.01 ? 1 : 0)}%',
                    style: TextStyle(fontSize: 12, color: c.textFaint),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 4,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (share > 0)
                      Expanded(
                        flex: (share * 1000).round().clamp(1, 1000),
                        child: ColoredBox(color: color),
                      ),
                    if (share < 1)
                      Expanded(
                        flex: (1000 - share * 1000).round().clamp(1, 1000),
                        child: ColoredBox(color: c.border),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _minWidth = 980.0;

/// Table columns: fixed widths or flex weights.
const _cols = <(double, int)>[
  (40, 0), // No.
  (168, 0), // Part no.
  (0, 3), // Description
  (56, 0), // BOM qty
  (56, 0), // SMT qty
  (0, 4), // Designators
  (52, 0), // Side
  (84, 0), // Result
  (0, 4), // Reason
  (30, 0), // Chevron
];

Widget _cell(int i, Widget child, {Alignment align = Alignment.centerLeft}) {
  final (w, flex) = _cols[i];
  final padded = Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Align(alignment: align, child: child),
  );
  return flex > 0 ? Expanded(flex: flex, child: padded) : SizedBox(width: w, child: padded);
}

class _ColumnHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final style = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.textFaint, letterSpacing: 0.2);
    final labels = [
      '#',
      s.t('col_pn'),
      s.t('col_desc'),
      'BOM',
      'SMT',
      s.t('col_bom_refs'),
      s.t('col_side'),
      s.t('col_result'),
      s.t('col_reason'),
      '',
    ];
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: c.panelAlt,
        border: Border.all(color: c.border),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 3),
          for (var i = 0; i < labels.length; i++)
            _cell(
              i,
              Text(labels[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
              align: i == 3 || i == 4 ? Alignment.center : Alignment.centerLeft,
            ),
        ],
      ),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  _ChevronPainter(this.color, this.open);

  final Color color;
  final bool open;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final w = size.width, h = size.height;
    final path = open
        ? (Path()
            ..moveTo(w * 0.2, h * 0.35)
            ..lineTo(w * 0.5, h * 0.68)
            ..lineTo(w * 0.8, h * 0.35))
        : (Path()
            ..moveTo(w * 0.35, h * 0.2)
            ..lineTo(w * 0.68, h * 0.5)
            ..lineTo(w * 0.35, h * 0.8));
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_ChevronPainter old) => old.open != open || old.color != color;
}

/// One compact line per part; the full detail opens below it.
class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.row,
    required this.index,
    required this.expanded,
    required this.cards,
    required this.last,
    required this.onTap,
  });

  final CheckRow row;
  final int index;
  final bool expanded;
  final bool cards;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final m = Metrics.of(context);
    final catColor = c.category(row.category);
    final refs = [...row.bomRefs, ...row.smtRefs.where((r) => r.state == RefState.extra)];
    final firstReason = row.reasons.isEmpty ? null : row.reasons.first;
    final reasonText = firstReason == null ? '-' : s.t(firstReason.code, firstReason.args);
    final more = row.reasons.length > 1 ? '  +${row.reasons.length - 1}' : '';
    final reasonColor = firstReason == null ? c.textFaint : (firstReason.info ? c.textDim : c.ng);

    final decoration = BoxDecoration(
      color: expanded ? c.selected : null,
      border: Border(
        left: BorderSide(color: c.border),
        right: BorderSide(color: c.border),
        bottom: BorderSide(color: c.border),
      ),
      borderRadius: last && !expanded ? const BorderRadius.vertical(bottom: Radius.circular(8)) : null,
    );

    if (cards) {
      return Hoverable(
        onTap: onTap,
        cursor: SystemMouseCursors.basic,
        builder: (context, hover, _) => Container(
          decoration: decoration.copyWith(
            color: expanded
                ? c.selected
                : hover
                ? c.hover
                : c.panel,
          ),
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      row.partNo,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: c.text),
                    ),
                  ),
                  _CategoryBadge(category: row.category, label: categoryLabel(s, row.category)),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                row.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: c.textDim),
              ),
              const SizedBox(height: 6),
              _RefLine(marks: refs),
              if (firstReason != null) ...[
                const SizedBox(height: 6),
                Text(
                  '$reasonText$more',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: reasonColor),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final mono = TextStyle(fontSize: 12.5, color: c.text, fontFeatures: const [FontFeature.tabularFigures()]);
    return Hoverable(
      onTap: onTap,
      cursor: SystemMouseCursors.basic,
      builder: (context, hover, _) => Container(
        height: m.touch ? 50 : 42,
        decoration: decoration.copyWith(
          color: expanded
              ? c.selected
              : hover
              ? c.hover
              : c.panel,
        ),
        child: Row(
          children: [
            Container(width: 3, color: row.category == CheckCategory.pass ? catColor.withValues(alpha: 0.4) : catColor),
            _cell(0, Text('$index', style: TextStyle(fontSize: 11.5, color: c.textFaint))),
            _cell(
              1,
              Text(
                row.partNo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: c.text),
              ),
            ),
            _cell(
              2,
              Text(
                row.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: c.textDim),
              ),
            ),
            _cell(3, Text(_qty(row.bomQty), style: mono), align: Alignment.center),
            _cell(4, Text(row.smtQty?.toString() ?? '-', style: mono), align: Alignment.center),
            _cell(5, _RefLine(marks: refs)),
            _cell(6, Text(_sides(row.sides), style: TextStyle(fontSize: 12, color: c.textDim))),
            _cell(7, _CategoryBadge(category: row.category, label: categoryLabel(s, row.category))),
            _cell(
              8,
              Text(
                '$reasonText$more',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: reasonColor),
              ),
            ),
            _cell(9, CustomPaint(size: const Size(11, 11), painter: _ChevronPainter(c.textFaint, expanded))),
          ],
        ),
      ),
    );
  }
}

/// Single line of designator chips, cut with "+N".
class _RefLine extends StatelessWidget {
  const _RefLine({required this.marks});

  final List<RefMark> marks;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    if (marks.isEmpty) return Text('-', style: TextStyle(color: c.textFaint));
    return LayoutBuilder(
      builder: (context, box) {
        // Roughly 52 px per chip; keep room for the "+N" counter.
        final fit = ((box.maxWidth - 30) / 54).floor().clamp(1, marks.length);
        final shown = marks.take(fit).toList();
        return ClipRect(
          child: Row(
            children: [
              for (final m in shown)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: RefChip(text: m.ref, color: c.refState(m.state), soft: c.refStateSoft(m.state), strike: m.state == RefState.extra),
                ),
              if (marks.length > fit)
                Text(
                  '+${marks.length - fit}',
                  style: TextStyle(fontSize: 11.5, color: c.textDim, fontWeight: FontWeight.w600),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Full designator lists, loaded part numbers and reasons with explanations.
class _RowDetails extends StatelessWidget {
  const _RowDetails({required this.row, required this.last});

  final CheckRow row;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        t,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.textFaint, letterSpacing: 0.3),
      ),
    );
    Widget chips(List<RefMark> marks, {bool strike = false}) => marks.isEmpty
        ? Text('-', style: TextStyle(color: c.textFaint))
        : Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final m in marks)
                RefChip(
                  text: m.ref,
                  color: c.refState(m.state),
                  soft: c.refStateSoft(m.state),
                  strike: strike && m.state == RefState.extra,
                ),
            ],
          );
    final facts = [
      (s.t('col_bom_qty'), _qty(row.bomQty)),
      (s.t('col_smt_qty'), row.smtQty?.toString() ?? '-'),
      (s.t('col_smt_pn'), row.smtPartNos.isEmpty ? '-' : row.smtPartNos.join(', ')),
      (s.t('col_slot'), row.slots.isEmpty ? '-' : row.slots.join(', ')),
      (s.t('col_side'), _sides(row.sides)),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      decoration: BoxDecoration(
        color: c.panelAlt,
        border: Border(
          left: BorderSide(color: c.border),
          right: BorderSide(color: c.border),
          bottom: BorderSide(color: c.border),
        ),
        borderRadius: last ? const BorderRadius.vertical(bottom: Radius.circular(8)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(row.description, style: TextStyle(fontSize: 13, color: c.text)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 28,
            runSpacing: 6,
            children: [
              for (final (k, v) in facts)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$k  ', style: TextStyle(fontSize: 12, color: c.textFaint)),
                    Text(
                      v,
                      style: TextStyle(fontSize: 12.5, color: c.text, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, box) {
              final two = box.maxWidth > 700;
              final bom = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [label(s.t('col_bom_refs')), chips(row.bomRefs)]);
              final smt = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [label(s.t('col_smt_refs')), chips(row.smtRefs, strike: true)],
              );
              return two
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: bom),
                        const SizedBox(width: 24),
                        Expanded(child: smt),
                      ],
                    )
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [bom, const SizedBox(height: 12), smt]);
            },
          ),
          if (row.reasons.isNotEmpty) ...[
            const SizedBox(height: 14),
            label(s.t('col_reason')),
            for (final r in row.reasons)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                  color: c.panel,
                  borderRadius: BorderRadius.circular(6),
                  border: Border(left: BorderSide(color: r.info ? c.substitute : c.ng, width: 3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.t(r.code, r.args),
                      style: TextStyle(fontSize: 13, color: c.text, fontWeight: FontWeight.w600),
                    ),
                    if (Texts.has('why_${r.code}')) ...[
                      const SizedBox(height: 3),
                      Text(s.t('why_${r.code}'), style: TextStyle(fontSize: 12.5, color: c.textDim, height: 1.45)),
                    ],
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.category, required this.label});

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
            decoration: BoxDecoration(
              color: c.panel,
              shape: BoxShape.circle,
              border: Border.all(color: c.border),
            ),
            child: Icon(icon, size: 30, color: c.textFaint),
          ),
          const SizedBox(height: 16),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textDim, fontSize: 13),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}
