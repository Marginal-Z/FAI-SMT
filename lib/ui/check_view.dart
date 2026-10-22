/// Check result workspace: result-area filters, the result table (or cards on
/// narrow screens) and the import guide shown before the first check.
library;

import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../core/models.dart';
import '../l10n/strings.dart';
import 'actions.dart';
import 'icons.dart';
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
    final m = Metrics.of(context);
    final s = Strings.of(context);
    final report = state.report;
    if (report == null) return ImportGuide(state: state);
    if (_search.text != state.search) _search.text = state.search;

    final pills = <(CheckCategory?, String, Color?)>[
      (null, s.t('cat_all'), null),
      (CheckCategory.pass, s.t('cat_pass'), c.pass),
      (CheckCategory.ng, s.t('cat_ng'), c.ng),
      (CheckCategory.excluded, s.t('cat_excluded'), c.excluded),
      (CheckCategory.substitute, s.t('cat_substitute'), c.substitute),
    ];
    final filters = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (cat, label, color) in pills)
          FilterPill(
            label: label,
            color: color,
            active: state.filter == cat,
            count: cat == null ? report.rows.length : report.count(cat),
            onTap: () => state.setFilter(cat),
          ),
      ],
    );
    final search = TextInput(controller: _search, hint: s.t('search_hint'), prefix: Ic.magnifyingGlass, onChanged: state.setSearch);
    final rows = state.visibleRows();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: m.touch ? 10 : 8),
          decoration: BoxDecoration(
            color: c.panel,
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          child: widget.cards
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [filters, const SizedBox(height: 10), search])
              : Row(
                  children: [
                    Expanded(child: filters),
                    const SizedBox(width: 12),
                    SizedBox(width: 280, child: search),
                  ],
                ),
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

/// Shown before the first check: the four inputs as steps, then Run Check.
class ImportGuide extends StatelessWidget {
  const ImportGuide({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final steps = [
      (InputKind.bom, Ic.treeStructure, s.t('btn_bom'), s.t('step_bom'), state.bom?.name, false),
      (InputKind.stationA, Ic.squaresFour, s.t('btn_station_a'), s.t('step_station_a'), state.stationA?.name, false),
      (InputKind.stationB, Ic.gridFour, s.t('btn_station_b'), s.t('step_station_b'), state.stationB?.name, true),
      (InputKind.coords, Ic.crosshair, s.t('btn_coord'), s.t('step_coord'), state.coords?.name, true),
    ];
    final ready = state.bom != null && (state.stationA != null || state.stationB != null);
    return Container(
      color: c.window,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  s.t('guide_title'),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.text),
                ),
                const SizedBox(height: 4),
                Text(s.t('guide_sub'), style: TextStyle(fontSize: 13, color: c.textDim)),
                const SizedBox(height: 18),
                for (var i = 0; i < steps.length; i++) ...[
                  _GuideStep(
                    number: i + 1,
                    icon: steps[i].$2,
                    title: steps[i].$3,
                    hint: steps[i].$4,
                    file: steps[i].$5,
                    optional: steps[i].$6,
                    onTap: () => importFile(context, state, steps[i].$1),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FlatButton(
                    icon: Ic.play,
                    label: s.t('btn_run'),
                    primary: true,
                    onTap: ready ? () => runCheck(context, state) : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.number,
    required this.icon,
    required this.title,
    required this.hint,
    required this.file,
    required this.optional,
    required this.onTap,
  });

  final int number;
  final IconData icon;
  final String title;
  final String hint;
  final String? file;
  final bool optional;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final m = Metrics.of(context);
    final s = Strings.of(context);
    final done = file != null;
    return Hoverable(
      onTap: onTap,
      builder: (context, hover, _) => Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: m.touch ? 14 : 12),
        decoration: BoxDecoration(
          color: hover ? c.hover : c.panel,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: done ? c.pass.withValues(alpha: 0.5) : c.border),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? c.pass : c.panelAlt,
                border: done ? null : Border.all(color: c.borderStrong),
              ),
              child: done
                  ? const Icon(IcBold.check, size: 15, color: Color(0xFFFFFFFF))
                  : Text(
                      '$number',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: c.textDim),
                    ),
            ),
            const SizedBox(width: 14),
            Icon(icon, size: 22, color: done ? c.accent : c.textDim),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: c.text),
                      ),
                      if (optional) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: c.panelAlt,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: c.border),
                          ),
                          child: Text(s.t('step_optional'), style: TextStyle(fontSize: 11, color: c.textFaint)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    file ?? hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: done ? c.textDim : c.textFaint),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              done ? s.t('step_replace') : s.t('step_import'),
              style: TextStyle(fontSize: 12.5, color: c.accent, fontWeight: FontWeight.w600),
            ),
            Icon(Ic.caretRight, size: 14, color: c.accent),
          ],
        ),
      ),
    );
  }
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
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: c.textFaint),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textDim),
          ),
        ],
      ),
    );
  }
}
