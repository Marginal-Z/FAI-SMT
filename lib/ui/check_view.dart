/// BOM check page: file header with export, one statistic card per result
/// area (doubling as the area filter), search and filters, the result table
/// with manual confirmation, and the details of the selected part.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../core/models.dart';
import '../l10n/strings.dart';
import 'design.dart';
import 'discrepancy_view.dart';
import 'import_bar.dart';
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
    _ConfirmFilter.no => r.category != CheckCategory.pass && widget.state.confirmationOf(r) == null,
  };

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
        child: EmptyState(icon: Ic.listChecks, text: s.t('empty_check_import')),
      );
      if (phone) {
        return ListView(
          padding: EdgeInsets.fromLTRB(pad.left, pad.top, pad.right, bottomInset(context) + 12),
          children: [
            imports,
            const SizedBox(height: 14),
            SizedBox(height: 260, child: hint),
          ],
        );
      }
      return Padding(
        padding: pad,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            imports,
            const SizedBox(height: 16),
            Expanded(child: hint),
            const SizedBox(height: 16),
          ],
        ),
      );
    }
    if (_search.text != state.search) _search.text = state.search;

    final discrepancies = state.discrepancies ?? const [];
    final showDiscrepancies = state.checkView == CheckPageView.discrepancies;
    final total = report.rows.length;

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
          confirmed: cat == CheckCategory.pass ? 0 : state.confirmedCount(cat),
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
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: statCards.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) => SizedBox(width: 156, child: statCards[i]),
            ),
          )
        // Desktop: compact cards of one width, not stretched across the page.
        : Wrap(
            key: tourTargets.checkCards,
            spacing: 12,
            runSpacing: 12,
            children: [for (final card in statCards) SizedBox(width: 200, child: card)],
          );

    final gap = phone ? 14.0 : 16.0;
    // Wide windows: import cards over the statistics, both rows the same
    // width, and the run / export / clear card spanning their height.
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
                        IntrinsicHeight(
                          key: tourTargets.checkCards,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var i = 0; i < statCards.length; i++) ...[if (i > 0) const SizedBox(width: 12), Expanded(child: statCards[i])],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(width: 220, child: ImportActions(state: state)),
                ],
              ),
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              imports,
              SizedBox(height: gap),
              stats,
              SizedBox(height: gap),
            ],
          );

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
    // Only results other than PASS are confirmed by hand.
    final toConfirm = [
      for (final r in visible)
        if (r.category != CheckCategory.pass) r,
    ];
    final allConfirmed = toConfirm.isNotEmpty && toConfirm.every((r) => state.confirmationOf(r) != null);

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
                        child: _HeaderRow(
                          allConfirmed: allConfirmed,
                          listed: toConfirm.length,
                          showConfirm: toConfirm.isNotEmpty,
                          onConfirmAll: () => state.setConfirmed(toConfirm, !allConfirmed),
                        ),
                      ),
                      Expanded(
                        child: ThinScrollbar(
                          controller: _scroll,
                          child: ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                            itemCount: visible.length,
                            itemBuilder: (context, i) => _ResultRow(state: state, row: visible[i], index: i + 1, showConfirm: toConfirm.isNotEmpty),
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
                SizedBox(width: 320, child: search),
                for (final w in selects) ...[const SizedBox(width: 16), w],
                const Spacer(),
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
        // The selected part's card sits right of the table, top and bottom
        // aligned with it; narrow windows put it under the table.
        // The card opens only once a result is clicked.
        final selected = state.selected != null;
        final side = box.maxWidth >= 1100 && selected;
        final body = side
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: keyedTable),
                  const SizedBox(width: 16),
                  SizedBox(width: 360, child: _Detail(state: state, panel: true)),
                ],
              )
            : keyedTable;
        final children = [
          top,
          filters,
          const SizedBox(height: 16),
          short ? SizedBox(height: math.max(440.0, box.maxHeight * 0.66), child: body) : Expanded(child: body),
          if (!side && selected) ...[const SizedBox(height: 16), _Detail(state: state)],
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
          padding: EdgeInsets.fromLTRB(pad.left, pad.top, pad.right, bottomInset(context) + (selected == null ? 12 : 300)),
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
            bottom: bottomInset(context),
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
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? fg.withValues(alpha: 0.55) : const Color(0x00000000), width: 1.5),
          boxShadow: selected ? [BoxShadow(color: glow, offset: const Offset(0, 10), blurRadius: 26)] : c.shadowSm,
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
                  style: TextStyle(
                    fontSize: 22,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                    color: c.tx,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (chevron) ...[const SizedBox(width: 2), LucideIcon(Lucide.chevronRight, size: 14, color: c.tx2, stroke: 2.2)],
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: share != null ? TrackBar(value: share < 0.02 && value > 0 ? 0.02 : share, color: bar, height: 4) : const SizedBox(height: 4),
                ),
                const SizedBox(width: 8),
                Text(
                  confirmed > 0 ? s.t('confirm_count', {'n': confirmed}) : pct,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: confirmed > 0 ? FontWeight.w600 : FontWeight.w400,
                    color: confirmed > 0 ? c.blueTx : c.tx2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

const _minTable = 900.0;

/// Column widths: fixed px, or flex weight with a minimum.
const _cols = [
  (40.0, 0.0), // #
  (168.0, 0.0), // part number
  (200.0, 1.6), // description
  (68.0, 0.0), // BOM qty
  (68.0, 0.0), // SMT qty
  (220.0, 2.4), // designators
  (52.0, 0.0), // side
  (80.0, 0.0), // result
  (112.0, 0.0), // confirmation (only when a listed row needs one)
];

/// Lays out one table line in the design's grid.
Widget _gridRow(List<Widget> cells, {List<Alignment>? align}) => LayoutBuilder(
  builder: (context, box) {
    final cols = _cols.take(cells.length).toList();
    final fixed = cols.fold<double>(0, (a, e) => a + e.$1);
    final flex = cols.fold<double>(0, (a, e) => a + e.$2);
    final spare = (box.maxWidth - fixed).clamp(0.0, double.infinity);
    // Narrower than the fixed columns (tablets): shrink them all evenly.
    final shrink = box.maxWidth < fixed ? box.maxWidth / fixed : 1.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < cells.length; i++)
          SizedBox(
            width: cols[i].$1 * shrink + (flex == 0 ? 0 : spare * cols[i].$2 / flex),
            child: Align(alignment: align?[i] ?? Alignment.centerLeft, child: cells[i]),
          ),
      ],
    );
  },
);

const _centerCols = {3, 4, 7};

List<Alignment> _alignments() => [
  for (var i = 0; i < _cols.length; i++)
    i == _cols.length - 1
        ? Alignment.centerRight
        : _centerCols.contains(i)
        ? Alignment.center
        : Alignment.centerLeft,
];

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.allConfirmed, required this.listed, required this.onConfirmAll, required this.showConfirm});

  final bool allConfirmed;
  final int listed;
  final VoidCallback onConfirmAll;

  /// Some listed row needs manual confirmation.
  final bool showConfirm;

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
        t('col_result'),
        if (showConfirm)
          Hoverable(
            onTap: onConfirmAll,
            tooltip: allConfirmed ? s.t('confirm_none_visible') : s.t('confirm_all_visible', {'n': listed}),
            builder: (context, hover, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                LucideIcon(allConfirmed ? Lucide.check : Lucide.clipboardCheck, size: 13, color: hover ? c.blueTx : c.tx2, stroke: 2.2),
                const SizedBox(width: 4),
                Text(s.t('col_confirm'), style: style.copyWith(color: hover ? c.blueTx : null)),
              ],
            ),
          ),
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
  const _ResultRow({required this.state, required this.row, required this.index, required this.showConfirm});

  final AppState state;
  final CheckRow row;
  final int index;
  final bool showConfirm;

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
          DBadge(text: _resultShort(s, row.category), background: c.categorySoft(row.category), color: c.categoryText(row.category)),
          // PASS needs no manual confirmation: the cell stays empty.
          if (showConfirm)
            row.category == CheckCategory.pass
                ? const SizedBox.shrink()
                : _ConfirmPill(confirmed: state.confirmationOf(row) != null, onTap: () => state.setConfirmed([row], state.confirmationOf(row) == null)),
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
                if (row.category != CheckCategory.pass) ...[
                  _ConfirmPill(confirmed: state.confirmationOf(row) != null, onTap: () => state.setConfirmed([row], state.confirmationOf(row) == null)),
                  const SizedBox(width: 8),
                ],
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

/// Manual confirmation toggle: an outlined blue "Confirm" that fills on
/// hover; once confirmed a green tick that offers "Undo" on hover.
class _ConfirmPill extends StatelessWidget {
  const _ConfirmPill({required this.confirmed, required this.onTap, this.large = false});

  final bool confirmed;
  final VoidCallback onTap;

  /// Detail card: a bigger primary button.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    return Hoverable(
      onTap: onTap,
      tooltip: confirmed ? s.t('confirm_undo') : s.t('confirm_hint_short'),
      builder: (context, hover, pressed) {
        final (bg, fg, border, icon, label) = confirmed
            ? hover
                  ? (c.grayTint, c.tx2, const Color(0x00000000), Lucide.x, s.t('confirm_undo_short'))
                  : (c.okTint, c.okTx, const Color(0x00000000), Lucide.check, s.t('confirm_done'))
            : hover
            ? (c.btn, const Color(0xFFFFFFFF), c.btn, Lucide.check, s.t('confirm_btn'))
            : (large ? c.btn : c.card, large ? const Color(0xFFFFFFFF) : c.blueTx, c.btn.withValues(alpha: 0.55), Lucide.circle, s.t('confirm_btn'));
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: large ? 40 : 30,
          padding: EdgeInsets.symmetric(horizontal: large ? 18 : 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(large ? 20 : 15),
            border: Border.all(color: border, width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LucideIcon(icon, size: large ? 16 : 13, color: fg, stroke: 2.6),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontSize: large ? 14.5 : 13, fontWeight: FontWeight.w600, color: fg),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Details of the selected part: quantities, side, result, reasons and the
/// manual confirmation with its note.
class _Detail extends StatefulWidget {
  const _Detail({required this.state, this.panel = false});

  final AppState state;

  /// Shown right of the table at its full height (scrolls inside).
  final bool panel;

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
    final panel = widget.panel;
    if (row == null) {
      if (panel) {
        return DCard(
          radius: 22,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TintTile(icon: Lucide.clipboardCheck),
                  const SizedBox(height: 14),
                  Text(
                    s.t('detail_hint'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, height: 1.5, color: c.tx2),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return DCard(
        radius: 22,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
    final body = Column(
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
        if (row.category == CheckCategory.pass) ...[
          const SizedBox(height: 12),
          Text(s.t('confirm_not_needed'), style: TextStyle(fontSize: 13, color: c.tx2)),
        ] else ...[
          const SizedBox(height: 12),
          Row(
            children: [
              _ConfirmPill(large: true, confirmed: confirmation != null, onTap: () => state.setConfirmed([row], confirmation == null)),
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
      ],
    );
    if (panel) {
      return DCard(
        radius: 22,
        clip: true,
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 20, 46, 20), child: body),
            Positioned(
              top: 10,
              right: 10,
              child: GlassButton(icon: Lucide.x, size: 32, iconSize: 15, tooltip: s.t('dlg_close'), onTap: () => state.select(null)),
            ),
          ],
        ),
      );
    }
    return DCard(radius: 22, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16), child: body);
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
