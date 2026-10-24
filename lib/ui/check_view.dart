/// BOM check page: file header with export, one statistic card per result
/// area (doubling as the area filter), search and filters, the result table
/// with manual confirmation, and the details of the selected part.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../core/models.dart';
import '../l10n/strings.dart';
import 'actions.dart';
import 'design.dart';
import 'discrepancy_view.dart';
import 'icons.dart';
import 'lucide.dart';
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

/// Short result names for badges and the result filter.
String _resultShort(Strings s, CheckCategory c) => s.t(switch (c) {
  CheckCategory.pass => 'res_pass',
  CheckCategory.ng => 'res_ng',
  CheckCategory.excluded => 'res_excluded_short',
  CheckCategory.substitute => 'res_substitute_short',
});

class CheckView extends StatefulWidget {
  const CheckView({super.key, required this.state, this.cards = false});

  final AppState state;

  /// Narrow screens: rows as cards instead of table columns.
  final bool cards;

  @override
  State<CheckView> createState() => _CheckViewState();
}

enum _SideFilter { all, a, b, both }

enum _ConfirmFilter { all, yes, no }

class _CheckViewState extends State<CheckView> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _hScroll = ScrollController();
  final _page = ScrollController();

  /// Result-area filter; null shows every area.
  CheckCategory? _area = CheckCategory.pass;
  _SideFilter _side = _SideFilter.all;
  _ConfirmFilter _confirm = _ConfirmFilter.all;

  @override
  void initState() {
    super.initState();
    _search.text = widget.state.search;
    // Open the area of a part selected elsewhere (e.g. the PCB navigator) or
    // picked as a filter; PASS otherwise.
    final sel = widget.state.selected;
    if (sel != null) {
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
    _page.dispose();
    super.dispose();
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
    final narrow = widget.cards;
    final phone = isPhoneLayout(context);

    // File header.
    final header = DCard(
      radius: phone ? 24 : 32,
      padding: EdgeInsets.symmetric(horizontal: phone ? 16 : (narrow ? 20 : 28), vertical: phone ? 14 : 22),
      child: Row(
        children: [
          GradientTile(
            icon: Lucide.clipboardCheck,
            colors: GradientTile.blue,
            glow: GradientTile.blueGlow,
            size: phone ? 42 : 56,
            radius: phone ? 13 : 17,
            iconSize: phone ? 20 : 26,
          ),
          SizedBox(width: phone ? 12 : 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.bom?.name ?? '-',
                  maxLines: phone ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: phone ? 17 : (narrow ? 20 : 26), height: 1.2, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: c.tx),
                ),
                SizedBox(height: phone ? 3 : 5),
                Text(
                  [
                    s.t('hdr_stations', {'n': stations}),
                    if (state.checkedAt != null) formatTime(state.checkedAt!),
                    s.t('hdr_total', {'n': total}),
                  ].join(' · '),
                  maxLines: phone ? 2 : null,
                  style: TextStyle(fontSize: phone ? 12.5 : 14, color: c.tx2),
                ),
              ],
            ),
          ),
          SizedBox(width: phone ? 8 : 16),
          if (phone)
            GlassButton(
              key: tourTargets.checkExport,
              icon: Lucide.download,
              size: 42,
              tooltip: s.t('btn_export_excel'),
              onTap: () => exportReport(context, state),
            )
          else
            PillButton(
              key: tourTargets.checkExport,
              label: s.t('btn_export_excel'),
              icon: Lucide.download,
              kind: PillKind.glass,
              height: 44,
              fontSize: 15,
              iconSize: 17,
              color: c.blueTx,
              onTap: () => exportReport(context, state),
            ),
        ],
      ),
    );

    // Statistic cards.
    final statCards = <Widget>[
      for (final (cat, icon) in [
        (CheckCategory.pass, Lucide.check),
        (CheckCategory.ng, Lucide.x),
        (CheckCategory.excluded, Lucide.package),
        (CheckCategory.substitute, Lucide.swap),
      ])
        _StatCard(
          label: _areaLabel(s, cat),
          icon: icon,
          value: report.count(cat),
          total: total,
          confirmed: state.confirmedCount(cat),
          tint: c.categorySoft(cat),
          fg: c.categoryText(cat),
          bar: _barColor(cat),
          glow: _glow(cat),
          selected: !showDiscrepancies && _area == cat,
          onTap: () => _setArea(cat),
        ),
      _StatCard(
        label: s.t('view_discrepancies'),
        icon: Lucide.alert,
        value: discrepancies.length,
        tint: c.blueTint,
        fg: c.blueTx,
        bar: const Color(0xFF0A84FF),
        glow: const Color(0x420A84FF),
        selected: showDiscrepancies,
        chevron: true,
        onTap: () => state.setCheckView(showDiscrepancies ? CheckPageView.materials : CheckPageView.discrepancies),
      ),
    ];
    // Phones: one row of compact cards that scrolls sideways.
    final stats = phone
        ? SizedBox(
            key: tourTargets.checkCards,
            height: 126,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: statCards.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) => SizedBox(width: 148, child: statCards[i]),
            ),
          )
        : LayoutBuilder(
            key: tourTargets.checkCards,
            builder: (context, box) {
              final perRow = box.maxWidth >= 1100 ? 5 : (box.maxWidth >= 640 ? 3 : 2);
              final w = (box.maxWidth - (perRow - 1) * 16) / perRow;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [for (final card in statCards) SizedBox(width: w, child: card)],
              );
            },
          );

    final gap = phone ? 14.0 : 20.0;
    final top = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        SizedBox(height: gap),
        stats,
        SizedBox(height: gap),
      ],
    );
    final pad = EdgeInsets.fromLTRB(narrow ? 16 : 32, phone ? 4 : 12, narrow ? 16 : 32, 0);

    if (showDiscrepancies) {
      return Padding(
        padding: pad,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            top,
            Expanded(
              child: DCard(
                clip: true,
                child: DiscrepancyView(state: state, items: discrepancies),
              ),
            ),
          ],
        ),
      );
    }

    final visible = state.visibleRows().where((r) => _sideMatches(r) && _confirmMatches(r) && (_area == null || r.category == _area)).toList()
      ..sort((a, b) => _areaOrder.indexOf(a.category) - _areaOrder.indexOf(b.category));
    final allConfirmed = visible.isNotEmpty && visible.every((r) => state.confirmationOf(r) != null);

    Widget labelled(String label, Widget child) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: c.tx2)),
        const SizedBox(width: 10),
        child,
      ],
    );
    final selects = [
      labelled(
        s.t('col_side'),
        DropdownSelect<_SideFilter>(
          value: _side,
          width: 104,
          options: [(_SideFilter.all, s.t('opt_all')), (_SideFilter.a, 'A'), (_SideFilter.b, 'B'), (_SideFilter.both, 'A+B')],
          onChanged: (v) => setState(() => _side = v),
        ),
      ),
      labelled(
        s.t('col_result'),
        DropdownSelect<CheckCategory?>(
          value: _area,
          width: 112,
          options: [(null, s.t('opt_all')), for (final cat in _areaOrder) (cat, _resultShort(s, cat))],
          onChanged: _setArea,
        ),
      ),
      labelled(
        s.t('confirm_filter'),
        DropdownSelect<_ConfirmFilter>(
          value: _confirm,
          width: 112,
          options: [(_ConfirmFilter.all, s.t('opt_all')), (_ConfirmFilter.yes, s.t('confirm_yes')), (_ConfirmFilter.no, s.t('confirm_no'))],
          onChanged: (v) => setState(() => _confirm = v),
        ),
      ),
    ];
    final search = PillSearch(controller: _search, hint: s.t('search_hint_fuzzy'), onChanged: state.setSearch);
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

    final Widget table;
    if (visible.isEmpty) {
      table = DCard(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 56),
            child: Text(s.t('no_rows'), style: TextStyle(fontSize: 15, color: c.tx2)),
          ),
        ),
      );
    } else if (narrow) {
      table = DCard(
        clip: true,
        child: ThinScrollbar(
          controller: _scroll,
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(12),
            itemCount: visible.length,
            itemBuilder: (context, i) => _RowCard(state: state, row: visible[i]),
          ),
        ),
      );
    } else {
      table = DCard(
        clip: true,
        child: LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth < _minTable ? _minTable : box.maxWidth;
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                        child: _HeaderRow(allConfirmed: allConfirmed, listed: visible.length, onConfirmAll: () => state.setConfirmed(visible, !allConfirmed)),
                      ),
                      Expanded(
                        child: ThinScrollbar(
                          controller: _scroll,
                          child: ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                            itemCount: visible.length,
                            itemBuilder: (context, i) => _ResultRow(state: state, row: visible[i], index: i + 1),
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
    }

    final filters = KeyedSubtree(
      key: tourTargets.checkFilters,
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: 12),
                if (phone)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    child: Row(
                      children: [
                        for (final w in selects) ...[w, const SizedBox(width: 14)],
                        count,
                      ],
                    ),
                  )
                else
                  Wrap(spacing: 16, runSpacing: 12, children: selects),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: ConstrainedBox(constraints: const BoxConstraints(minWidth: 260), child: search),
                ),
                for (final w in selects) ...[const SizedBox(width: 16), w],
                const SizedBox(width: 16),
                count,
              ],
            ),
    );
    if (phone) return _phonePage(context, top, filters, visible, pad);
    final keyedTable = KeyedSubtree(key: tourTargets.checkTable, child: table);
    return LayoutBuilder(
      builder: (context, box) {
        // Short windows (tablets in landscape) scroll the whole page so the
        // table keeps a usable height.
        final short = box.maxHeight < 900;
        final children = [
          top,
          filters,
          const SizedBox(height: 20),
          short ? SizedBox(height: math.max(420.0, box.maxHeight * 0.62), child: keyedTable) : Expanded(child: keyedTable),
          const SizedBox(height: 20),
          _Detail(state: state),
          if (short) const SizedBox(height: 20),
        ];
        final column = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
        return Padding(
          padding: pad,
          child: short ? SingleChildScrollView(controller: _page, child: column) : column,
        );
      },
    );
  }

  /// Phones: the whole page scrolls as one list of row cards; the selected
  /// part opens in a sheet over the bottom of the screen.
  Widget _phonePage(BuildContext context, Widget top, Widget filters, List<CheckRow> visible, EdgeInsets pad) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final state = widget.state;
    final selected = state.selected;
    return Stack(
      children: [
        ListView.builder(
          controller: _page,
          padding: EdgeInsets.fromLTRB(pad.left, pad.top, pad.right, selected == null ? 16 : 280),
          itemCount: visible.length + 2,
          itemBuilder: (context, i) {
            if (i == 0) return top;
            if (i == 1) return Padding(padding: const EdgeInsets.only(bottom: 14), child: filters);
            final row = visible[i - 2];
            final card = Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DCard(
                radius: 22,
                padding: EdgeInsets.zero,
                child: _RowCard(state: state, row: row),
              ),
            );
            return i == 2 ? KeyedSubtree(key: tourTargets.checkTable, child: card) : card;
          },
        ),
        if (visible.isEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: Center(
              child: Text(s.t('no_rows'), style: TextStyle(fontSize: 15, color: c.tx2)),
            ),
          ),
        if (selected != null)
          Positioned(
            left: 8,
            right: 8,
            bottom: 0,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.55),
              child: Stack(
                children: [
                  SingleChildScrollView(child: _Detail(state: state)),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: GlassButton(icon: Lucide.x, size: 34, tooltip: s.t('dlg_close'), onTap: () => state.select(null)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static Color _barColor(CheckCategory c) => switch (c) {
    CheckCategory.pass => const Color(0xFF34C759),
    CheckCategory.ng => const Color(0xFFFF3B30),
    CheckCategory.excluded => const Color(0xFF8E8E93),
    CheckCategory.substitute => const Color(0xFFFF9500),
  };

  static Color _glow(CheckCategory c) => switch (c) {
    CheckCategory.pass => const Color(0x4234C759),
    CheckCategory.ng => const Color(0x3DFF3B30),
    CheckCategory.excluded => const Color(0x38787880),
    CheckCategory.substitute => const Color(0x42FF9500),
  };
}

/// Statistic card: icon, label, big number, share and bar; lifts when chosen.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.icon,
    required this.value,
    required this.tint,
    required this.fg,
    required this.bar,
    required this.glow,
    required this.selected,
    required this.onTap,
    this.total,
    this.confirmed = 0,
    this.chevron = false,
  });

  final String label;
  final Lucide icon;
  final int value;
  final Color tint;
  final Color fg;
  final Color bar;
  final Color glow;
  final bool selected;
  final VoidCallback onTap;

  /// When set, the share and bar are shown.
  final int? total;
  final int confirmed;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final share = total == null || total == 0 ? null : value / total!;
    final pct = share == null ? '' : '${(share * 100).toStringAsFixed(share > 0 && share < 0.02 ? 1 : 0)}%';
    return Hoverable(
      onTap: onTap,
      builder: (context, hover, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(24),
          boxShadow: selected
              ? [BoxShadow(color: glow, offset: const Offset(0, 2), blurRadius: 4), BoxShadow(color: glow, offset: const Offset(0, 24), blurRadius: 56)]
              : c.shadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                  child: LucideIcon(icon, size: 16, color: fg, stroke: 2.3),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: -0.15, color: c.tx),
                  ),
                ),
                if (chevron) LucideIcon(Lucide.chevronRight, size: 16, color: c.tx2, stroke: 2.2),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '$value',
                  style: TextStyle(
                    fontSize: 32,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.1,
                    color: c.tx,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (share != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    pct,
                    style: TextStyle(fontSize: 14, color: c.tx2, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ],
                if (confirmed > 0) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      s.t('confirm_count', {'n': confirmed}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.blueTx),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            // Cards without a share keep the bar's space so all are one size.
            share != null ? TrackBar(value: share < 0.02 && value > 0 ? 0.02 : share, color: bar) : const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

const _minTable = 1200.0;

/// Column widths: fixed px, or flex weight with a minimum.
const _cols = [
  (44.0, 0.0), // #
  (196.0, 0.0), // part number
  (260.0, 1.6), // description
  (84.0, 0.0), // BOM qty
  (84.0, 0.0), // SMT qty
  (280.0, 2.4), // designators
  (72.0, 0.0), // side
  (112.0, 0.0), // confirmation
  (104.0, 0.0), // result
];

/// Lays out one table line in the design's grid.
Widget _gridRow(List<Widget> cells, {List<Alignment>? align}) => LayoutBuilder(
  builder: (context, box) {
    final fixed = _cols.fold<double>(0, (a, e) => a + e.$1);
    final flex = _cols.fold<double>(0, (a, e) => a + e.$2);
    final spare = (box.maxWidth - fixed).clamp(0.0, double.infinity);
    // Narrower than the fixed columns (tablets): shrink them all evenly.
    final shrink = box.maxWidth < fixed ? box.maxWidth / fixed : 1.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < cells.length; i++)
          SizedBox(
            width: _cols[i].$1 * shrink + (flex == 0 ? 0 : spare * _cols[i].$2 / flex),
            child: Align(alignment: align?[i] ?? Alignment.centerLeft, child: cells[i]),
          ),
      ],
    );
  },
);

const _centerCols = {3, 4};

List<Alignment> _alignments() => [
  for (var i = 0; i < _cols.length; i++)
    i == _cols.length - 1
        ? Alignment.centerRight
        : _centerCols.contains(i)
        ? Alignment.center
        : Alignment.centerLeft,
];

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.allConfirmed, required this.listed, required this.onConfirmAll});

  final bool allConfirmed;
  final int listed;
  final VoidCallback onConfirmAll;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final style = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.tx2);
    Text t(String key) => Text(s.t(key), maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: c.solid, borderRadius: BorderRadius.circular(18)),
      child: _gridRow([
        Text('#', style: style),
        t('col_pn'),
        t('col_desc'),
        t('col_bom_qty'),
        t('col_smt_qty'),
        t('col_bom_refs'),
        t('col_side'),
        Hoverable(
          onTap: onConfirmAll,
          tooltip: allConfirmed ? s.t('confirm_none_visible') : s.t('confirm_all_visible', {'n': listed}),
          builder: (context, hover, _) => Text(s.t('col_confirm'), style: style.copyWith(color: hover ? c.blueTx : null)),
        ),
        t('col_result'),
      ], align: _alignments()),
    );
  }
}

/// Designators of a row: BOM designators, plus extra ones from the station.
List<RefMark> _refs(CheckRow row) => [...row.bomRefs, ...row.smtRefs.where((r) => r.state == RefState.extra)];

Widget _chip(AppColors c, CheckRow row, RefMark m) {
  // Chips take the row's result colour; a designator with its own problem
  // (missing, extra, conflicting) shows in red.
  final bad = m.state == RefState.missing || m.state == RefState.extra || m.state == RefState.conflict;
  final cat = bad ? CheckCategory.ng : row.category;
  return DotChip(text: m.ref, background: c.categorySoft(cat), color: c.categoryText(cat), strike: m.state == RefState.extra);
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.state, required this.row, required this.index});

  final AppState state;
  final CheckRow row;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final selected = identical(state.selected, row);
    final refs = _refs(row);
    final shown = refs.take(12).toList();
    final mismatch = row.smtQty != null && row.bomQty != null && row.smtQty != row.bomQty!.round();
    final mono = TextStyle(fontSize: 14, color: c.tx, fontFeatures: const [FontFeature.tabularFigures()]);
    return Hoverable(
      onTap: () => state.select(selected ? null : row),
      cursor: SystemMouseCursors.basic,
      builder: (context, hover, _) => Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? c.rowSel
              : hover
              ? c.hover
              : null,
          borderRadius: BorderRadius.circular(18),
        ),
        child: _gridRow([
          Text(
            '$index',
            style: TextStyle(fontSize: 13, color: c.tx2, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          Text(
            row.partNo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: -0.07, color: hover ? c.blueTx : c.tx),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(row.description, style: TextStyle(fontSize: 14, height: 1.45, color: c.tx)),
          ),
          Text(_qty(row.bomQty), style: mono),
          Text(
            row.smtQty?.toString() ?? '-',
            style: mismatch ? mono.copyWith(color: c.ngTx, fontWeight: FontWeight.w700) : mono,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Wrap(
              spacing: 5,
              runSpacing: 5,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final m in shown) _chip(c, row, m),
                if (refs.length > shown.length) Text('+${refs.length - shown.length}', style: TextStyle(fontSize: 12, color: c.tx2)),
                if (refs.isEmpty) Text('-', style: TextStyle(color: c.tx3)),
              ],
            ),
          ),
          Text(_sides(row.sides), style: TextStyle(fontSize: 14, color: c.tx2)),
          _ConfirmPill(confirmed: state.confirmationOf(row) != null, onTap: () => state.setConfirmed([row], state.confirmationOf(row) == null)),
          DBadge(text: _resultShort(s, row.category), background: c.categorySoft(row.category), color: c.categoryText(row.category)),
        ], align: _alignments()),
      ),
    );
  }
}

/// Narrow screens: one card per part.
class _RowCard extends StatelessWidget {
  const _RowCard({required this.state, required this.row});

  final AppState state;
  final CheckRow row;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final selected = identical(state.selected, row);
    final refs = _refs(row);
    final reason = row.reasons.isEmpty ? null : row.reasons.first;
    return Hoverable(
      onTap: () => state.select(selected ? null : row),
      cursor: SystemMouseCursors.basic,
      builder: (context, hover, _) => Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: BoxDecoration(
          color: selected
              ? c.rowSel
              : hover
              ? c.hover
              : null,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.partNo,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.tx),
                  ),
                ),
                _ConfirmPill(confirmed: state.confirmationOf(row) != null, onTap: () => state.setConfirmed([row], state.confirmationOf(row) == null)),
                const SizedBox(width: 8),
                DBadge(text: _resultShort(s, row.category), background: c.categorySoft(row.category), color: c.categoryText(row.category)),
              ],
            ),
            const SizedBox(height: 4),
            Text(row.description, style: TextStyle(fontSize: 13, color: c.tx2)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final m in refs.take(12)) _chip(c, row, m),
                if (refs.length > 12) Text('+${refs.length - 12}', style: TextStyle(fontSize: 12, color: c.tx2)),
              ],
            ),
            if (reason != null) ...[
              const SizedBox(height: 6),
              Text(s.t(reason.code, reason.args), style: TextStyle(fontSize: 13, color: reason.info ? c.tx2 : c.ngTx)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConfirmPill extends StatelessWidget {
  const _ConfirmPill({required this.confirmed, required this.onTap});

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
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(color: confirmed ? c.blueTint : (hover ? c.glass2 : c.hover), borderRadius: BorderRadius.circular(15)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (confirmed) ...[LucideIcon(Lucide.check, size: 13, color: c.blueTx, stroke: 2.8), const SizedBox(width: 6)],
            Text(
              confirmed ? s.t('confirm_done') : s.t('confirm_btn'),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: confirmed ? c.blueTx : c.tx2),
            ),
          ],
        ),
      ),
    );
  }
}

/// Details of the selected part: quantities, side, result, reasons and the
/// manual confirmation with its note.
class _Detail extends StatefulWidget {
  const _Detail({required this.state});

  final AppState state;

  @override
  State<_Detail> createState() => _DetailState();
}

class _DetailState extends State<_Detail> {
  final _note = TextEditingController();
  CheckRow? _noteFor;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final state = widget.state;
    final row = state.selected;
    final narrow = MediaQuery.sizeOf(context).width < 900;
    if (row == null) {
      return DCard(
        radius: 26,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        child: Text(s.t('detail_hint'), style: TextStyle(fontSize: 14, color: c.tx2)),
      );
    }
    final confirmation = state.confirmationOf(row);
    if (!identical(_noteFor, row)) {
      _noteFor = row;
      _note.text = confirmation?.note ?? '';
    }
    Widget fact(String label, String value) => Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$label '),
          TextSpan(
            text: value,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.tx),
          ),
        ],
      ),
      style: TextStyle(fontSize: 13, color: c.tx2),
    );
    return DCard(
      radius: 26,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 24,
            runSpacing: 12,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: narrow ? double.infinity : 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.t('detail_selected', {'pn': row.partNo}), style: TextStyle(fontSize: 12, color: c.tx2)),
                    const SizedBox(height: 4),
                    Text(
                      row.description,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.16, color: c.tx),
                    ),
                  ],
                ),
              ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 28,
                runSpacing: 8,
                children: [
                  fact('BOM', _qty(row.bomQty)),
                  fact('SMT', row.smtQty?.toString() ?? '-'),
                  fact(s.t('col_side'), _sides(row.sides)),
                  if (row.slots.isNotEmpty) fact(s.t('col_slot'), row.slots.join(', ')),
                  DBadge(text: _resultShort(s, row.category), background: c.categorySoft(row.category), color: c.categoryText(row.category)),
                ],
              ),
            ],
          ),
          if (row.reasons.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final r in row.reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: r.info ? c.warnSolid : c.ngSolid),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: s.t(r.code, r.args),
                              style: TextStyle(fontWeight: FontWeight.w600, color: r.info ? c.warnTx : c.ngTx),
                            ),
                            if (Texts.has('why_${r.code}')) TextSpan(text: '  ${s.t('why_${r.code}')}'),
                          ],
                        ),
                        style: TextStyle(fontSize: 13, height: 1.5, color: c.tx2),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _ConfirmPill(confirmed: confirmation != null, onTap: () => state.setConfirmed([row], confirmation == null)),
              const SizedBox(width: 12),
              Expanded(
                child: confirmation == null
                    ? Text(s.t('confirm_pending'), style: TextStyle(fontSize: 13, color: c.tx2))
                    : PillSearch(
                        controller: _note,
                        hint: '${s.t('confirm_at', {'time': formatTime(confirmation.at)})} · ${s.t('confirm_note_hint')}',
                        icon: Lucide.fileText,
                        onChanged: (v) => state.setConfirmNote(row, v),
                        flat: true,
                      ),
              ),
            ],
          ),
        ],
      ),
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

/// Centred message with an icon, for pages that have nothing to show yet.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.glass, shape: BoxShape.circle, boxShadow: c.shadowSm),
            child: Icon(icon, size: 30, color: c.tx2),
          ),
          const SizedBox(height: 18),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.tx2, fontSize: 15),
          ),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}
