/// Check module page. Results are grouped into their result areas (NG,
/// alternates, excluded, PASS), each collapsed by default; a row expands in
/// place to show every designator and the reasons with explanations.
library;

import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../core/models.dart';
import '../l10n/strings.dart';
import 'actions.dart';
import '../core/discrepancies.dart';
import 'discrepancy_view.dart';
import 'glyphs.dart';
import 'icons.dart';
import 'theme.dart';
import 'tour.dart';
import 'widgets.dart';

const _areaOrder = [CheckCategory.pass, CheckCategory.ng, CheckCategory.excluded, CheckCategory.substitute];

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

enum _SideFilter { all, a, b, both }

enum _ConfirmFilter { all, yes, no }

class _CheckViewState extends State<CheckView> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _hScroll = ScrollController();

  /// Result-area filter; null shows every area.
  CheckCategory? _area = CheckCategory.pass;
  _SideFilter _side = _SideFilter.all;
  _ConfirmFilter _confirm = _ConfirmFilter.all;
  CheckRow? _expanded;

  @override
  void initState() {
    super.initState();
    _search.text = widget.state.search;
    // Open the area of a part selected elsewhere (e.g. the PCB navigator) or
    // picked as a filter; PASS otherwise.
    final sel = widget.state.selected;
    if (sel != null) {
      _expanded = sel;
      _area = sel.category;
    } else if (widget.state.filter != null) {
      _area = widget.state.filter!;
    }
    // The page filters by area itself; a leftover global filter would hide rows.
    widget.state.filter = null;
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

  void _setArea(CheckCategory? cat) {
    setState(() => _area = cat);
    widget.state.setCheckView(CheckPageView.materials);
  }

  bool _sideMatches(CheckRow r) => switch (_side) {
    _SideFilter.all => true,
    _SideFilter.a => r.sides.length == 1 && r.sides.contains(StationSide.a),
    _SideFilter.b => r.sides.length == 1 && r.sides.contains(StationSide.b),
    _SideFilter.both => r.sides.length == 2,
  };

  bool _confirmMatches(CheckRow r) => switch (_confirm) {
    _ConfirmFilter.all => true,
    _ConfirmFilter.yes => widget.state.confirmationOf(r) != null,
    _ConfirmFilter.no => widget.state.confirmationOf(r) == null,
  };

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final report = state.report;
    final stations = [state.stationA?.name, state.stationB?.name].whereType<String>().length;
    if (report == null) {
      return EmptyState(
        icon: Ic.listChecks,
        text: s.t('empty_check'),
        action: state.bom != null && stations > 0
            ? FlatButton(label: s.t('btn_run'), primary: true, onTap: () => runCheck(context, state))
            : FlatButton(label: s.t('go_files'), onTap: () => state.setModule(Module.files)),
      );
    }
    if (_search.text != state.search) _search.text = state.search;

    final discrepancies = state.discrepancies ?? const [];
    final showDiscrepancies = state.checkView == CheckPageView.discrepancies;
    final total = report.rows.length;

    final header = Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.pass, borderRadius: BorderRadius.circular(10)),
            child: const GlyphIcon(Glyph.modCad, size: 24, filled: true, color: Color(0xFFFFFFFF)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.bom?.name ?? '-',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.text),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    s.t('hdr_stations', {'n': stations}),
                    if (state.checkedAt != null) formatTime(state.checkedAt!),
                    s.t('hdr_total', {'n': total}),
                  ].join('   |   '),
                  style: TextStyle(fontSize: 12.5, color: c.textDim),
                ),
              ],
            ),
          ),
          Hoverable(
            key: tourTargets.checkExport,
            onTap: () => exportReport(context, state),
            builder: (context, hover, _) => Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: hover ? c.accent.withValues(alpha: 0.08) : c.panel,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: c.accent.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  GlyphIcon(Glyph.report, size: 18, color: c.accent),
                  const SizedBox(width: 8),
                  Text(
                    s.t('btn_export_excel'),
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.accent),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    final cardItems = <Widget>[
      for (final (cat, glyph) in [
        (CheckCategory.pass, Glyph.okCircle),
        (CheckCategory.ng, Glyph.errorCircle),
        (CheckCategory.excluded, Glyph.cube),
        (CheckCategory.substitute, Glyph.alternates),
      ])
        _AreaCard(
          label: _areaLabel(s, cat),
          glyph: glyph,
          count: report.count(cat),
          total: total,
          confirmed: state.confirmedCount(cat),
          color: c.category(cat),
          active: !showDiscrepancies && _area == cat,
          onTap: () => _setArea(_area == cat ? null : cat),
        ),
      _AreaCard(
        label: s.t('view_discrepancies'),
        glyph: Glyph.discrepancies,
        count: discrepancies.length,
        color: discrepancies.any((d) => d.severity == Severity.error) ? c.ng : c.accent,
        active: showDiscrepancies,
        chevron: true,
        onTap: () => state.setCheckView(showDiscrepancies ? CheckPageView.materials : CheckPageView.discrepancies),
      ),
    ];
    final cards = LayoutBuilder(
      key: tourTargets.checkCards,
      builder: (context, box) {
        final perRow = box.maxWidth >= 900 ? 5 : 3;
        return Column(
          children: [
            for (var r = 0; r < cardItems.length; r += perRow) ...[
              if (r > 0) const SizedBox(height: 12),
              Row(
                children: [
                  for (var i = r; i < r + perRow; i++) ...[
                    if (i > r) const SizedBox(width: 12),
                    Expanded(child: i < cardItems.length ? cardItems[i] : const SizedBox.shrink()),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );

    final top = Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, const SizedBox(height: 12), cards]),
    );

    if (showDiscrepancies) {
      return Container(
        color: c.window,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            top,
            Expanded(
              child: DiscrepancyView(state: state, items: discrepancies),
            ),
          ],
        ),
      );
    }

    final visible = state.visibleRows().where((r) => _sideMatches(r) && _confirmMatches(r)).toList();
    final entries = <_Entry>[];
    var shown = 0;
    for (final cat in _areaOrder) {
      if (_area != null && cat != _area) continue;
      final rows = visible.where((r) => r.category == cat).toList();
      for (var i = 0; i < rows.length; i++) {
        shown++;
        entries.add(_Row(rows[i], shown, entries.isEmpty));
        if (identical(_expanded, rows[i])) entries.add(_Details(rows[i]));
      }
    }
    final showReason = _area != CheckCategory.pass;
    final listed = [
      for (final e in entries)
        if (e is _Row) e.row,
    ];
    final allConfirmed = listed.isNotEmpty && listed.every((r) => state.confirmationOf(r) != null);

    final search = TextInput(controller: _search, hint: s.t('search_hint_fuzzy'), prefix: Ic.magnifyingGlass, onChanged: state.setSearch);
    Widget labelled(String label, Widget child) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: c.textDim)),
        const SizedBox(width: 8),
        child,
      ],
    );
    final dropdowns = [
      labelled(
        s.t('col_side'),
        DropdownSelect<_SideFilter>(
          value: _side,
          width: 130,
          options: [(_SideFilter.all, s.t('opt_all')), (_SideFilter.a, s.t('side_a')), (_SideFilter.b, s.t('side_b')), (_SideFilter.both, 'A+B')],
          onChanged: (v) => setState(() => _side = v),
        ),
      ),
      labelled(
        s.t('col_result'),
        DropdownSelect<CheckCategory?>(
          value: _area,
          width: 140,
          options: [(null, s.t('opt_all')), for (final cat in _areaOrder) (cat, _areaLabel(s, cat))],
          onChanged: _setArea,
        ),
      ),
      labelled(
        s.t('confirm_filter'),
        DropdownSelect<_ConfirmFilter>(
          value: _confirm,
          width: 120,
          options: [(_ConfirmFilter.all, s.t('opt_all')), (_ConfirmFilter.yes, s.t('confirm_yes')), (_ConfirmFilter.no, s.t('confirm_no'))],
          onChanged: (v) => setState(() => _confirm = v),
        ),
      ),
    ];
    final count = Text(s.t('check_total', {'n': shown}), style: TextStyle(fontSize: 12.5, color: c.textDim));
    // Narrow screens: search on its own line above the filters.
    final filters = Padding(
      key: tourTargets.checkFilters,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: widget.cards
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: Wrap(spacing: 16, runSpacing: 8, children: dropdowns)),
                    count,
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(flex: 3, child: search),
                for (final d in dropdowns) ...[const SizedBox(width: 20), d],
                const Spacer(flex: 2),
                count,
              ],
            ),
    );

    Widget body;
    if (entries.isEmpty) {
      body = EmptyState(
        icon: Ic.funnel,
        text: s.t(state.search.trim().isNotEmpty || _side != _SideFilter.all || _confirm != _ConfirmFilter.all ? 'empty_filter' : 'area_empty'),
      );
    } else {
      bool lastAt(int i) => i + 1 >= entries.length;
      final list = ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: entries.length,
        itemBuilder: (context, i) => switch (entries[i]) {
          _Row(:final row, :final index, :final first) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (first)
                (!widget.cards
                    ? _ColumnHeader(
                        reason: showReason,
                        allConfirmed: allConfirmed,
                        listed: listed.length,
                        onConfirmAll: () => state.setConfirmed(listed, !allConfirmed),
                      )
                    : Container(height: 1, color: c.border)),
              _ResultRow(
                row: row,
                index: index,
                expanded: identical(_expanded, row),
                cards: widget.cards,
                last: lastAt(i),
                showReason: showReason,
                confirmed: state.confirmationOf(row) != null,
                onConfirm: () => state.setConfirmed([row], state.confirmationOf(row) == null),
                onTap: () => _toggleRow(row),
              ),
            ],
          ),
          _Details(:final row) => _RowDetails(key: ValueKey(row.key), row: row, state: state, last: lastAt(i)),
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

    return Container(
      color: c.window,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          top,
          filters,
          Expanded(
            child: KeyedSubtree(key: tourTargets.checkTable, child: body),
          ),
        ],
      ),
    );
  }
}

/// Statistic card with an icon tile; doubles as a filter.
class _AreaCard extends StatelessWidget {
  const _AreaCard({
    required this.label,
    required this.glyph,
    required this.color,
    required this.onTap,
    required this.count,
    this.total,
    this.confirmed = 0,
    this.active = false,
    this.chevron = false,
  });

  final String label;
  final Glyph glyph;
  final Color color;
  final VoidCallback onTap;
  final int count;

  /// When set, a share bar and percentage are drawn.
  final int? total;

  /// Rows of this area confirmed by an operator.
  final int confirmed;
  final bool active;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final m = Metrics.of(context);
    final share = total == null || total == 0 ? null : count / total!;
    return Hoverable(
      onTap: onTap,
      builder: (context, hover, _) => Container(
        height: m.touch ? 112 : 104,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: active
              ? color.withValues(alpha: c.dark ? 0.14 : 0.07)
              : hover
              ? c.hover
              : c.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? color.withValues(alpha: 0.85) : c.border, width: active ? 1.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: c.dark ? 0.2 : 0.13),
                  ),
                  child: GlyphIcon(glyph, size: 20, filled: true, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textDim),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$count',
                            style: TextStyle(
                              fontSize: 26,
                              height: 1,
                              fontWeight: FontWeight.w800,
                              color: count == 0 ? c.textFaint : c.text,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          if (share != null) ...[
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                '${(share * 100).toStringAsFixed(share > 0 && share < 0.01 ? 1 : 0)}%',
                                style: TextStyle(fontSize: 12.5, color: c.textFaint),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (confirmed > 0)
                  Container(
                    padding: const EdgeInsets.fromLTRB(6, 2, 8, 2),
                    decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GlyphIcon(Glyph.okCircle, size: 13, filled: true, color: c.accent),
                        const SizedBox(width: 4),
                        Text(
                          Strings.of(context).t('confirm_count', {'n': confirmed}),
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.accent),
                        ),
                      ],
                    ),
                  ),
                if (chevron) GlyphIcon(Glyph.chevronRight, size: 16, color: c.textFaint),
              ],
            ),
            const Spacer(),
            if (share != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 5,
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

const _minWidth = 1100.0;

enum _Col { no, pn, desc, bom, smt, refs, side, reason, confirm, result }

/// Fixed width or flex weight per column.
const _colSpec = {
  _Col.no: (48.0, 0),
  _Col.pn: (180.0, 0),
  _Col.desc: (0.0, 3),
  _Col.bom: (80.0, 0),
  _Col.smt: (80.0, 0),
  _Col.refs: (0.0, 5),
  _Col.side: (64.0, 0),
  _Col.reason: (0.0, 4),
  _Col.confirm: (126.0, 0),
  _Col.result: (112.0, 0),
};

/// PASS rows have nothing to explain, so the reason column is left out.
List<_Col> _columns({required bool reason}) => [
  for (final col in _Col.values)
    if (col != _Col.reason || reason) col,
];

Widget _cell(_Col col, Widget child, {Alignment align = Alignment.centerLeft}) {
  final (w, flex) = _colSpec[col]!;
  final padded = Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Align(alignment: align, child: child),
  );
  return flex > 0 ? Expanded(flex: flex, child: padded) : SizedBox(width: w, child: padded);
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.reason, required this.allConfirmed, required this.listed, required this.onConfirmAll});

  final bool reason;

  /// Every listed row is confirmed; the confirm header toggles them all.
  final bool allConfirmed;
  final int listed;
  final VoidCallback onConfirmAll;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final style = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textFaint, letterSpacing: 0.2);
    final labels = {
      _Col.no: '#',
      _Col.pn: s.t('col_pn'),
      _Col.desc: s.t('col_desc'),
      _Col.bom: s.t('col_bom_qty'),
      _Col.smt: s.t('col_smt_qty'),
      _Col.refs: s.t('col_bom_refs'),
      _Col.side: s.t('col_side'),
      _Col.reason: s.t('col_reason'),
      _Col.confirm: s.t('col_confirm'),
      _Col.result: s.t('col_result'),
    };
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: c.panelAlt,
        border: Border.all(color: c.border),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 3),
          for (final col in _columns(reason: reason))
            _cell(
              col,
              col == _Col.confirm
                  ? Hoverable(
                      onTap: onConfirmAll,
                      tooltip: allConfirmed ? s.t('confirm_none_visible') : s.t('confirm_all_visible', {'n': listed}),
                      builder: (context, hover, _) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GlyphIcon(Glyph.okCircle, size: 15, filled: allConfirmed, color: allConfirmed || hover ? c.accent : c.textFaint),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              labels[col]!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: style.copyWith(color: hover ? c.accent : null),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Text(labels[col]!, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
              align: switch (col) {
                _Col.bom || _Col.smt || _Col.confirm => Alignment.center,
                _Col.result => Alignment.centerRight,
                _ => Alignment.centerLeft,
              },
            ),
        ],
      ),
    );
  }
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
    required this.confirmed,
    required this.onConfirm,
    this.showReason = true,
  });

  final CheckRow row;
  final int index;
  final bool expanded;
  final bool cards;
  final bool last;
  final VoidCallback onTap;
  final bool confirmed;
  final VoidCallback onConfirm;

  /// Whether the table has a reason column.
  final bool showReason;

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
                  _ConfirmToggle(confirmed: confirmed, onTap: onConfirm),
                  const SizedBox(width: 8),
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

    final mono = TextStyle(fontSize: 13, color: c.text, fontFeatures: const [FontFeature.tabularFigures()]);
    final passRow = row.category == CheckCategory.pass;
    Widget content(_Col col) => switch (col) {
      _Col.no => Text('$index', style: TextStyle(fontSize: 12, color: c.textFaint)),
      _Col.pn => Text(
        row.partNo,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: c.text),
      ),
      _Col.desc => Text(
        row.description,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, color: c.textDim),
      ),
      _Col.bom => Text(_qty(row.bomQty), style: mono),
      _Col.smt => Text(row.smtQty?.toString() ?? '-', style: mono),
      _Col.refs => _RefLine(marks: refs),
      _Col.side => Text(_sides(row.sides), style: TextStyle(fontSize: 12.5, color: c.textDim)),
      _Col.reason =>
        passRow
            ? const SizedBox.shrink()
            : Text(
                '$reasonText$more',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: reasonColor),
              ),
      _Col.confirm => _ConfirmToggle(confirmed: confirmed, onTap: onConfirm),
      _Col.result => _CategoryBadge(category: row.category, label: categoryLabel(s, row.category)),
    };
    return Hoverable(
      onTap: onTap,
      cursor: SystemMouseCursors.basic,
      builder: (context, hover, _) => Container(
        height: m.touch ? 60 : 54,
        decoration: decoration.copyWith(
          color: expanded
              ? c.selected
              : hover
              ? c.hover
              : c.panel,
        ),
        child: Row(
          children: [
            Container(width: 3, color: passRow ? catColor.withValues(alpha: 0.4) : catColor),
            for (final col in _columns(reason: showReason))
              _cell(
                col,
                content(col),
                align: switch (col) {
                  _Col.bom || _Col.smt || _Col.confirm => Alignment.center,
                  _Col.result => Alignment.centerRight,
                  _ => Alignment.centerLeft,
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Per-row manual confirmation switch.
class _ConfirmToggle extends StatelessWidget {
  const _ConfirmToggle({required this.confirmed, required this.onTap});

  final bool confirmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    return Hoverable(
      onTap: onTap,
      tooltip: confirmed ? s.t('confirm_undo') : null,
      builder: (context, hover, _) => Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: confirmed
              ? c.accent.withValues(alpha: hover ? 0.2 : 0.13)
              : hover
              ? c.hover
              : null,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: confirmed ? c.accent.withValues(alpha: 0.55) : (hover ? c.borderStrong : c.border)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlyphIcon(Glyph.okCircle, size: 15, filled: confirmed, color: confirmed ? c.accent : c.textFaint),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                confirmed ? s.t('confirm_done') : s.t('confirm_btn'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: confirmed ? c.accent : c.textDim),
              ),
            ),
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
class _RowDetails extends StatefulWidget {
  const _RowDetails({super.key, required this.row, required this.state, required this.last});

  final CheckRow row;
  final AppState state;
  final bool last;

  @override
  State<_RowDetails> createState() => _RowDetailsState();
}

class _RowDetailsState extends State<_RowDetails> {
  late final _note = TextEditingController(text: widget.state.confirmationOf(widget.row)?.note ?? '');

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final last = widget.last;
    final state = widget.state;
    final confirmation = state.confirmationOf(row);
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
                RefChip(text: m.ref, color: c.refState(m.state), soft: c.refStateSoft(m.state), strike: strike && m.state == RefState.extra),
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
              final smt = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [label(s.t('col_smt_refs')), chips(row.smtRefs, strike: true)]);
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
          const SizedBox(height: 14),
          label(s.t('confirm_section')),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            decoration: BoxDecoration(
              color: c.panel,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: confirmation != null ? c.accent.withValues(alpha: 0.45) : c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    GlyphIcon(Glyph.okCircle, size: 17, filled: confirmation != null, color: confirmation != null ? c.accent : c.textFaint),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        confirmation != null ? s.t('confirm_at', {'time': formatTime(confirmation.at)}) : s.t('confirm_pending'),
                        style: TextStyle(fontSize: 12.5, color: confirmation != null ? c.text : c.textDim),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FlatButton(
                      label: confirmation != null ? s.t('confirm_undo') : s.t('confirm_btn'),
                      primary: confirmation == null,
                      compact: true,
                      onTap: () => state.setConfirmed([row], confirmation == null),
                    ),
                  ],
                ),
                if (confirmation != null) ...[
                  const SizedBox(height: 8),
                  TextInput(controller: _note, hint: s.t('confirm_note_hint'), onChanged: (v) => state.setConfirmNote(row, v)),
                ],
              ],
            ),
          ),
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
