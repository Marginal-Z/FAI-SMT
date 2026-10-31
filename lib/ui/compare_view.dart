/// Compare page: BOM ↔ BOM, BOM ↔ station list, BOM ↔ station lists A + B.
/// Import cards, then the editable result table, the analysis report, the
/// designator map (BOM ↔ BOM) and the recognised columns, all exportable.
library;

import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../compare_session.dart';
import '../core/compare.dart';
import '../core/discrepancies.dart';
import '../core/exporters.dart';
import '../core/models.dart';
import '../core/smart_table.dart';
import '../l10n/strings.dart';
import 'actions.dart';
import 'check_view.dart' show EmptyState;
import 'design.dart';
import 'discrepancy_view.dart' show severityLabel;
import 'icons.dart';
import 'lucide.dart';
import 'theme.dart';
import 'widgets.dart';

const _tableExts = ['xlsx', 'xlsm', 'xls', 'csv', 'txt'];

String slotLabel(Strings s, CompareMode mode, CompareSlot slot) => s.t(switch (slot) {
      CompareSlot.bomA => mode == CompareMode.bomBom ? 'slot_bomA' : 'slot_bomA_short',
      CompareSlot.bomB => 'slot_bomB',
      CompareSlot.station => 'slot_station',
      CompareSlot.stationA => 'slot_stationA',
      CompareSlot.stationB => 'slot_stationB',
    });

String roleLabel(Strings s, ColumnRole r) => s.t('role_${r.name}');

String compareSourceLabel(Strings s, CompareMode mode, Source src) =>
    mode == CompareMode.bomBom && src == Source.cross ? s.t('src_cross_bom') : s.t('src_${src.name}');

Color categoryColor(AppColors c, CheckCategory cat) => switch (cat) {
      CheckCategory.pass => c.pass,
      CheckCategory.ng => c.ng,
      CheckCategory.excluded => c.excluded,
      CheckCategory.substitute => c.substitute,
    };

Color severityColor(AppColors c, Severity v) => switch (v) {
      Severity.error => c.ngTx,
      Severity.warning => c.warnTx,
      Severity.info => c.textDim,
    };

// ----------------------------------------------------------------- actions

Future<void> _pick(BuildContext context, CompareSession session, CompareSlot slot) async {
  final s = Strings.of(context);
  try {
    final file = await FilePicker.pickFile(
      dialogTitle: slotLabel(s, session.mode, slot),
      type: FileType.custom,
      allowedExtensions: _tableExts,
    );
    if (file == null) return;
    session.load(slot, file.name, await file.xFile.readAsBytes());
  } catch (e) {
    if (context.mounted) await showError(context, e);
  }
}

void _run(BuildContext context, CompareSession session) {
  try {
    session.run();
    session.setTab(CompareTab.preview);
  } catch (e) {
    showError(context, e);
  }
}

String _reasonText(Strings s, ResultRow r) => r.reasons.map((x) => s.t(x.code, x.args)).join('\n');

/// Result table, report, designator map and columns as one workbook.
Future<void> exportCompare(BuildContext context, AppState state) async {
  final s = Strings.of(context);
  final session = state.compare;
  final res = session.result;
  if (res == null) {
    await showError(context, UserMessage('msg_need_check'));
    return;
  }
  const fills = {
    CheckCategory.pass: '#DCFCE7',
    CheckCategory.ng: '#FEE2E2',
    CheckCategory.excluded: '#F3F4F6',
    CheckCategory.substitute: '#FEF3C7',
  };
  final cols = res.columns;
  final resultFills = <(int, int), String>{};
  final resultRows = <List<String>>[
    [s.t('cc_no'), for (final k in cols) s.t('cc_$k'), s.t('cc_result'), s.t('cc_original_result'), s.t('cc_reason'), s.t('cc_note'), s.t('cc_edited')],
  ];
  for (var i = 0; i < res.rows.length; i++) {
    final r = res.rows[i];
    final line = i + 1;
    resultRows.add([
      '$line',
      for (final k in cols) r.cells[k] ?? '',
      categoryLabel(s, r.category),
      r.categoryEdited ? categoryLabel(s, r.originalCategory) : '',
      _reasonText(s, r),
      r.note,
      r.edited ? '✓' : '',
    ]);
    resultFills[(line, cols.length + 1)] = fills[r.category]!;
    for (var c = 0; c < cols.length; c++) {
      if (r.cellEdited(cols[c])) resultFills[(line, c + 1)] = '#FFF3BF';
    }
  }
  final sheets = [
    SheetData(s.t('ws_cmp_result'), resultRows, fills: resultFills, widths: [
      6,
      for (final k in cols) k.startsWith('refs') || k.endsWith('Refs') || k.startsWith('desc') ? 36.0 : 16.0,
      10,
      10,
      60,
      30,
      8,
    ]),
    SheetData(s.t('ws_cmp_report'), [
      [s.t('col_severity'), s.t('col_source'), s.t('col_subject'), s.t('col_problem'), s.t('col_explain'), s.t('col_ref')],
      for (final d in res.findings)
        [severityLabel(s, d.severity), compareSourceLabel(s, res.mode, d.source), d.subject, s.t(d.code, d.args), s.t('why_${d.code}'), d.refs.join(',')],
    ], widths: const [10, 14, 22, 60, 60, 30]),
    if (res.mode == CompareMode.bomBom)
      SheetData(s.t('ws_cmp_refs'), [
        [s.t('col_ref'), s.t('cc_pnA'), s.t('cc_descA'), s.t('cc_pnB'), s.t('cc_descB'), s.t('ref_state')],
        for (final p in res.refPairs) [p.ref, p.pnA, p.descA, p.pnB, p.descB, s.t('ref_${p.state.name}')],
      ], widths: const [10, 22, 40, 22, 40, 12]),
    SheetData(s.t('ws_cmp_columns'), [
      [s.t('rep_detection'), s.t('col_letter'), s.t('col_header'), s.t('col_role'), s.t('col_conf'), s.t('col_samples')],
      for (final slot in session.slots)
        if (session.files[slot] != null)
          for (final c in session.files[slot]!.layout.columns)
            [
              '${slotLabel(s, res.mode, slot)} · ${session.files[slot]!.name}',
              c.letter,
              c.header,
              roleLabel(s, c.role),
              c.manual ? s.t('col_manual') : '${(c.confidence * 100).round()}%',
              c.samples.join(' | '),
            ],
    ], widths: const [36, 6, 20, 14, 10, 60]),
  ];
  final bytes = exportSheetsWorkbook(sheets);
  if (!context.mounted) return;
  await saveFile(context, '${session.exportBaseName}.xlsx', bytes, ['xlsx']);
}

// -------------------------------------------------------------------- page

class CompareView extends StatefulWidget {
  const CompareView({super.key, required this.state, this.compact = false});

  final AppState state;
  final bool compact;

  @override
  State<CompareView> createState() => _CompareViewState();
}

class _CompareViewState extends State<CompareView> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.text = widget.state.compare.search;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final session = state.compare;
    final s = Strings.of(context);
    final c = AppTheme.of(context);
    final phone = isPhoneLayout(context);
    final narrow = widget.compact;
    final res = session.result;

    final modes = SegmentedPill<CompareMode>(
      value: session.mode,
      options: [for (final m in CompareMode.values) (m, s.t('cmp_mode_${m.name}'))],
      onChanged: session.setMode,
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PillButton(label: s.t('btn_run'), icon: Lucide.play, kind: PillKind.primary, height: 40, onTap: session.ready ? () => _run(context, session) : null),
        PillButton(label: s.t('btn_export_excel'), icon: Lucide.download, color: c.blueTx, onTap: res == null ? null : () => exportCompare(context, state)),
        PillButton(label: s.t('cmp_rules'), icon: Lucide.shield, kind: PillKind.ghost, onTap: () => state.openRules(RulesSection.exclusion)),
        PillButton(label: s.t('btn_clear'), icon: Lucide.trash, kind: PillKind.ghost, onTap: session.clear),
      ],
    );
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!phone) ...[
          Text(s.t('mod_compare'), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: c.tx)),
          const SizedBox(height: 4),
          Text(s.t('cmp_sub'), style: TextStyle(fontSize: 13.5, color: c.tx2)),
          const SizedBox(height: 14),
        ],
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [SingleChildScrollView(scrollDirection: Axis.horizontal, child: modes), actions],
        ),
        const SizedBox(height: 14),
        _SlotCards(session: session, collapsed: res != null && narrow),
      ],
    );

    final pad = EdgeInsets.fromLTRB(narrow ? 16 : 24, phone ? 4 : 10, narrow ? 16 : 24, 0);
    if (res == null) {
      return ListView(
        padding: EdgeInsets.fromLTRB(pad.left, pad.top, pad.right, bottomInset(context) + 16),
        children: [
          header,
          const SizedBox(height: 16),
          SizedBox(height: 260, child: DCard(radius: 24, child: EmptyState(icon: Ic.listChecks, text: s.t('cmp_empty')))),
        ],
      );
    }

    final tabs = [
      CompareTab.preview,
      CompareTab.report,
      if (res.mode == CompareMode.bomBom) CompareTab.refs,
      CompareTab.columns,
    ];
    final tab = tabs.contains(session.tab) ? session.tab : CompareTab.preview;
    final body = switch (tab) {
      CompareTab.preview => _Preview(session: session, result: res, cards: narrow, search: _search),
      CompareTab.report => _Report(session: session, result: res),
      CompareTab.refs => _RefMap(result: res),
      CompareTab.columns => _Columns(session: session),
    };
    return Padding(
      padding: pad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedPill<CompareTab>(
              value: tab,
              options: [for (final t in tabs) (t, s.t('cmp_tab_${t.name}'))],
              onChanged: session.setTab,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: body),
          SizedBox(height: 12 + bottomInset(context)),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ import cards

class _SlotCards extends StatelessWidget {
  const _SlotCards({required this.session, required this.collapsed});

  final CompareSession session;

  /// Phones with a result: one line per file instead of full cards.
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final slots = session.slots;
    if (collapsed) {
      return Wrap(spacing: 8, runSpacing: 8, children: [for (final slot in slots) _SlotChip(session: session, slot: slot)]);
    }
    return LayoutBuilder(builder: (context, box) {
      const gap = 12.0;
      final perRow = box.maxWidth >= 900 ? slots.length : (box.maxWidth >= 560 ? 2 : 1);
      final w = (box.maxWidth - gap * (perRow - 1)) / perRow;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final slot in slots) SizedBox(width: w, child: _SlotCard(session: session, slot: slot))],
      );
    });
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({required this.session, required this.slot});

  final CompareSession session;
  final CompareSlot slot;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final f = session.files[slot];
    return Hoverable(
      onTap: () => _pick(context, session, slot),
      builder: (context, hover, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: hover ? c.hover : c.card, borderRadius: c.r(999), border: c.cardBorder),
        child: Text(
          '${slotLabel(s, session.mode, slot)}: ${f?.name ?? s.t('chk_not_imported')}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12.5, color: f?.error != null ? c.ngTx : c.tx2),
        ),
      ),
    );
  }
}

class _SlotCard extends StatefulWidget {
  const _SlotCard({required this.session, required this.slot});

  final CompareSession session;
  final CompareSlot slot;

  @override
  State<_SlotCard> createState() => _SlotCardState();
}

class _SlotCardState extends State<_SlotCard> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final session = widget.session;
    final slot = widget.slot;
    final f = session.files[slot];
    final bom = isBomSlot(slot);
    final (colors, glow) = switch (slot) {
      CompareSlot.bomA => (GradientTile.blue, GradientTile.blueGlow),
      CompareSlot.bomB => (GradientTile.orange, GradientTile.orangeGlow),
      CompareSlot.stationB => (GradientTile.orange, GradientTile.orangeGlow),
      _ => (GradientTile.teal, GradientTile.tealGlow),
    };

    final Widget status;
    if (f == null) {
      status = Text(dropSupported ? s.t('in_drop_or_click') : s.t('well_tap'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: c.blueTx));
    } else if (f.error != null) {
      status = Text(s.t('cmp_card_error'), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: c.ngTx));
    } else {
      final h = f.layout.headerRow;
      final text = h >= 0 ? s.t('cmp_card_rows', {'n': f.count, 'h': h + 1}) : s.t('cmp_card_rows_nohead', {'n': f.count});
      final issues = f.issues.length;
      status = Row(children: [
        LucideIcon(issues == 0 ? Lucide.check : Lucide.alert, size: 13, color: issues == 0 ? c.okTx : c.warnTx, stroke: 2.6),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            issues == 0 ? text : '$text · ${s.t('in_issues', {'n': issues})}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: issues == 0 ? c.okTx : c.warnTx),
          ),
        ),
      ]);
    }

    Widget iconButton(Lucide icon, String tip, VoidCallback onTap) => Hoverable(
          onTap: onTap,
          tooltip: tip,
          builder: (context, hover, _) => Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: hover ? c.hover : null, shape: BoxShape.circle),
            child: LucideIcon(icon, size: 15, color: c.tx2),
          ),
        );

    final card = Hoverable(
      onTap: f == null ? () => _pick(context, session, slot) : null,
      builder: (context, hover, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: _dragging || (hover && f == null) ? Color.alphaBlend(c.blueTint, c.card) : c.card,
          borderRadius: c.r(22),
          border: Border.all(color: _dragging ? c.blue : (c.industrial ? c.lineStrong : const Color(0x00000000)), width: _dragging || !c.industrial ? 1.5 : 1),
          boxShadow: c.shadowSm,
        ),
        child: Row(children: [
          Hoverable(
            tooltip: s.t(bom ? 'cmp_bom_help' : 'cmp_station_help'),
            cursor: SystemMouseCursors.help,
            builder: (context, hover, _) => GradientTile(icon: bom ? Lucide.clipboardCheck : Lucide.fileText, colors: colors, glow: glow, size: 42, radius: 13, iconSize: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(slotLabel(s, session.mode, slot), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: c.tx)),
              const SizedBox(height: 3),
              Text(f?.name ?? s.t('well_formats'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: c.tx2)),
              const SizedBox(height: 3),
              status,
            ]),
          ),
          if (f != null) ...[
            const SizedBox(width: 4),
            iconButton(Lucide.refresh, s.t('step_replace'), () => _pick(context, session, slot)),
            iconButton(Lucide.trash, s.t('file_remove'), () => session.unload(slot)),
          ] else
            Padding(padding: const EdgeInsets.only(right: 4), child: LucideIcon(Lucide.plus, size: 18, color: c.blue, stroke: 2.2)),
        ]),
      ),
    );
    if (!dropSupported) return card;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) async {
        setState(() => _dragging = false);
        if (detail.files.isEmpty) return;
        final file = detail.files.first;
        final ext = file.name.split('.').last.toLowerCase();
        try {
          if (!_tableExts.contains(ext)) throw UserMessage('msg_bad_drop', {'ext': '.$ext', 'allowed': _tableExts.map((e) => '.$e').join(' / ')});
          session.load(slot, file.name, await file.readAsBytes());
        } catch (e) {
          if (context.mounted) await showError(context, e);
        }
      },
      child: card,
    );
  }
}

// ----------------------------------------------------------------- preview

const _colWidth = {
  'pnA': 170.0, 'pnB': 170.0, 'descA': 220.0, 'descB': 220.0, 'qtyA': 70.0, 'qtyB': 70.0, 'refsA': 200.0, 'refsB': 200.0, //
  'pn': 170.0, 'desc': 240.0, 'bomQty': 80.0, 'smtQty': 80.0, 'bomRefs': 200.0, 'smtRefs': 200.0, 'smtPn': 170.0, 'side': 60.0, 'slot': 90.0,
};
const _noWidth = 52.0;

/// Data columns shown before the result and reason (part numbers / description).
const _lead = 2;
const _resultWidth = 108.0;
const _reasonWidth = 340.0;
const _noteWidth = 170.0;

class _Preview extends StatefulWidget {
  const _Preview({required this.session, required this.result, required this.cards, required this.search});

  final CompareSession session;
  final CompareResult result;
  final bool cards;
  final TextEditingController search;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  final _v = ScrollController();
  final _h = ScrollController();

  @override
  void dispose() {
    _v.dispose();
    _h.dispose();
    super.dispose();
  }

  List<(int, ResultRow)> _visible() {
    final session = widget.session;
    final q = session.search.trim().toUpperCase();
    return [
      for (var i = 0; i < widget.result.rows.length; i++)
        if ((session.filter == null || widget.result.rows[i].category == session.filter) &&
            (q.isEmpty ||
                widget.result.rows[i].cells.values.any((v) => v.toUpperCase().contains(q)) ||
                widget.result.rows[i].note.toUpperCase().contains(q)))
          (i, widget.result.rows[i]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final session = widget.session;
    final res = widget.result;
    final rows = _visible();
    final edited = res.edited;

    final filters = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilterPill(label: s.t('cmp_all'), active: session.filter == null, count: res.rows.length, color: c.textDim, onTap: () => session.setFilter(null)),
        for (final cat in [CheckCategory.pass, CheckCategory.ng, CheckCategory.excluded, CheckCategory.substitute])
          FilterPill(label: categoryLabel(s, cat), active: session.filter == cat, count: res.count(cat), color: categoryColor(c, cat), onTap: () => session.setFilter(cat)),
        SizedBox(width: 260, child: TextInput(controller: widget.search, hint: s.t('search_hint'), prefix: Ic.magnifyingGlass, onChanged: session.setSearch)),
        if (edited > 0) ...[
          Text(s.t('cmp_edited_n', {'n': edited}), style: TextStyle(fontSize: 12.5, color: c.blueTx, fontWeight: FontWeight.w600)),
          PillButton(label: s.t('cmp_reset_all'), icon: Lucide.undo, kind: PillKind.ghost, height: 32, fontSize: 12.5, onTap: session.resetAllEdits),
        ] else
          Text(s.t('cmp_tap_edit'), style: TextStyle(fontSize: 12, color: c.textFaint)),
      ],
    );

    final Widget table;
    if (rows.isEmpty) {
      table = EmptyState(icon: Ic.checkCircle, text: s.t('empty_filter'));
    } else if (widget.cards) {
      table = ThinScrollbar(
        controller: _v,
        child: ListView.separated(
          controller: _v,
          padding: const EdgeInsets.all(10),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) => _RowCard(session: session, result: res, index: rows[i].$1, row: rows[i].$2),
        ),
      );
    } else {
      final cols = res.columns;
      final total = _noWidth + cols.fold(0.0, (w, k) => w + _colWidth[k]!) + _resultWidth + _reasonWidth + _noteWidth;
      table = LayoutBuilder(builder: (context, box) {
        final width = math.max(box.maxWidth, total);
        final extra = (width - total) / (cols.length + 2);
        double w(String k) => _colWidth[k]! + extra;
        Widget headCell(String text, double width) => SizedBox(
              width: width,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.tx2)),
              ),
            );
        return ThinScrollbar(
          controller: _h,
          horizontal: true,
          child: SingleChildScrollView(
            controller: _h,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              height: box.maxHeight,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
                  child: Row(children: [
                    headCell(s.t('cc_no'), _noWidth),
                    for (final k in cols.take(_lead)) headCell(s.t('cc_$k'), w(k)),
                    headCell(s.t('cc_result'), _resultWidth),
                    headCell(s.t('cc_reason'), _reasonWidth + extra),
                    for (final k in cols.skip(_lead)) headCell(s.t('cc_$k'), w(k)),
                    headCell(s.t('cc_note'), _noteWidth + extra),
                  ]),
                ),
                Expanded(
                  child: ThinScrollbar(
                    controller: _v,
                    child: ListView.builder(
                      controller: _v,
                      itemCount: rows.length,
                      itemExtent: 64,
                      itemBuilder: (context, i) => _TableRow(session: session, result: res, index: rows[i].$1, row: rows[i].$2, width: w, extra: extra),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        );
      });
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      filters,
      const SizedBox(height: 10),
      Expanded(child: DCard(radius: 22, clip: true, child: table)),
    ]);
  }
}

class _ResultBadge extends StatelessWidget {
  const _ResultBadge({required this.row});

  final ResultRow row;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final color = categoryColor(c, row.category);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        DBadge(text: categoryLabel(s, row.category), background: color.withValues(alpha: c.dark ? 0.22 : 0.14), color: color, height: 24),
        if (row.categoryEdited) ...[const SizedBox(width: 4), LucideIcon(Lucide.pencil, size: 12, color: c.blueTx)],
      ]),
    );
  }
}

class _Reasons extends StatelessWidget {
  const _Reasons({required this.row, this.maxLines = 3});

  final ResultRow row;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    if (row.reasons.isEmpty) return Text('—', style: TextStyle(fontSize: 12.5, color: c.textFaint));
    return Text.rich(
      TextSpan(children: [
        for (var i = 0; i < row.reasons.length; i++)
          TextSpan(
            text: '${i > 0 ? '\n' : ''}${s.t(row.reasons[i].code, row.reasons[i].args)}',
            style: TextStyle(color: severityColor(c, severityOf(row.reasons[i]))),
          ),
      ]),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12.5, height: 1.35),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({required this.session, required this.result, required this.index, required this.row, required this.width, required this.extra});

  final CompareSession session;
  final CompareResult result;
  final int index;
  final ResultRow row;
  final double Function(String) width;
  final double extra;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    Widget cell(double w, Widget child, {String? focus}) => Hoverable(
          onTap: () => showRowEditor(context, session, result, row, focus: focus),
          builder: (context, hover, _) => Container(
            width: w,
            height: 64,
            color: hover ? c.hover : null,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            alignment: Alignment.centerLeft,
            child: child,
          ),
        );
    Text value(String key) {
      final v = row.cells[key] ?? '';
      final edited = row.cellEdited(key);
      return Text(
        v.isEmpty ? '—' : v,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12.5, height: 1.3, color: edited ? c.blueTx : (v.isEmpty ? c.textFaint : c.tx), fontWeight: edited ? FontWeight.w600 : null),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: row.edited ? c.blueTint.withValues(alpha: 0.35) : null,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(children: [
        cell(_noWidth, Text('${index + 1}', style: TextStyle(fontSize: 12, color: c.tx3))),
        for (final k in result.columns.take(_lead)) cell(width(k), value(k), focus: k),
        cell(_resultWidth, _ResultBadge(row: row), focus: 'result'),
        cell(_reasonWidth + extra, _Reasons(row: row)),
        for (final k in result.columns.skip(_lead)) cell(width(k), value(k), focus: k),
        cell(
          _noteWidth + extra,
          Text(row.note.isEmpty ? '—' : row.note, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: row.note.isEmpty ? c.textFaint : c.blueTx)),
          focus: 'note',
        ),
      ]),
    );
  }
}

class _RowCard extends StatelessWidget {
  const _RowCard({required this.session, required this.result, required this.index, required this.row});

  final CompareSession session;
  final CompareResult result;
  final int index;
  final ResultRow row;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final bomBom = result.mode == CompareMode.bomBom;
    final title = bomBom
        ? [row.cells['pnA'], row.cells['pnB']].where((e) => e != null && e.isNotEmpty).toSet().join(' → ')
        : row.cells['pn'] ?? '';
    return Hoverable(
      onTap: () => showRowEditor(context, session, result, row),
      builder: (context, hover, _) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: hover ? c.hover : (row.edited ? c.blueTint.withValues(alpha: 0.35) : c.card), borderRadius: c.r(16), border: c.cardBorder),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('${index + 1}', style: TextStyle(fontSize: 12, color: c.tx3)),
            const SizedBox(width: 8),
            Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.tx))),
            _ResultBadge(row: row),
          ]),
          const SizedBox(height: 4),
          Text(bomBom ? (row.cells['descA']!.isNotEmpty ? row.cells['descA']! : row.cells['descB']!) : row.cells['desc'] ?? '',
              maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: c.tx2)),
          const SizedBox(height: 6),
          _Reasons(row: row, maxLines: 4),
          if (row.note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('${s.t('cc_note')}: ${row.note}', style: TextStyle(fontSize: 12, color: c.blueTx)),
          ],
        ]),
      ),
    );
  }
}

/// Edits one result row: every cell, the result and the note.
Future<void> showRowEditor(BuildContext context, CompareSession session, CompareResult result, ResultRow row, {String? focus}) {
  final s = Strings.of(context);
  return showAppDialog<void>(context, title: s.t('cmp_edit_cell', {'col': row.cells['pn'] ?? row.cells['pnA'] ?? ''}), width: 620, body: (ctx) => _RowEditor(session: session, result: result, row: row, focus: focus));
}

class _RowEditor extends StatefulWidget {
  const _RowEditor({required this.session, required this.result, required this.row, this.focus});

  final CompareSession session;
  final CompareResult result;
  final ResultRow row;
  final String? focus;

  @override
  State<_RowEditor> createState() => _RowEditorState();
}

class _RowEditorState extends State<_RowEditor> {
  late final Map<String, TextEditingController> _cells = {for (final k in widget.result.columns) k: TextEditingController(text: widget.row.cells[k] ?? '')};
  late final _note = TextEditingController(text: widget.row.note);
  late CheckCategory _category = widget.row.category;

  @override
  void dispose() {
    for (final c in _cells.values) {
      c.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final session = widget.session;
    final row = widget.row;
    for (final e in _cells.entries) {
      if (e.value.text != (row.cells[e.key] ?? '')) session.setCell(row, e.key, e.value.text);
    }
    if (_category != row.category) session.setCategory(row, _category);
    if (_note.text != row.note) session.setNote(row, _note.text.trim());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final row = widget.row;
    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.tx2)),
        );
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            label(s.t('cmp_set_result')),
            Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedPill<CheckCategory>(
                  value: _category,
                  options: [for (final cat in CheckCategory.values) (cat, categoryLabel(s, cat))],
                  onChanged: (v) => setState(() => _category = v),
                ),
              ),
            ),
            if (row.reasons.isNotEmpty) ...[
              const SizedBox(height: 14),
              label(s.t('cc_reason')),
              _Reasons(row: row, maxLines: 20),
            ],
            for (final k in widget.result.columns) ...[
              const SizedBox(height: 14),
              label(s.t('cc_$k')),
              TextInput(controller: _cells[k]!, maxLines: k.toLowerCase().contains('refs') || k.startsWith('desc') ? 3 : 1, autofocus: widget.focus == k),
              if ((row.originalCells[k] ?? '') != _cells[k]!.text) ...[
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(child: Text(s.t('cmp_original', {'v': row.originalCells[k] ?? ''}), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.textFaint))),
                  FlatButton(label: s.t('cmp_restore'), compact: true, onTap: () => setState(() => _cells[k]!.text = row.originalCells[k] ?? '')),
                ]),
              ],
            ],
            const SizedBox(height: 14),
            label(s.t('cc_note')),
            TextInput(controller: _note, maxLines: 3, autofocus: widget.focus == 'note'),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
        child: Row(children: [
          if (row.edited)
            FlatButton(
              label: s.t('cmp_reset_row'),
              onTap: () {
                widget.session.resetRow(row);
                Navigator.of(context).pop();
              },
            ),
          const Spacer(),
          FlatButton(label: s.t('dlg_cancel'), onTap: () => Navigator.of(context).pop()),
          const SizedBox(width: 8),
          FlatButton(label: s.t('dlg_save'), primary: true, onTap: _save),
        ]),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ report

class _Report extends StatefulWidget {
  const _Report({required this.session, required this.result});

  final CompareSession session;
  final CompareResult result;

  @override
  State<_Report> createState() => _ReportState();
}

class _ReportState extends State<_Report> {
  final _scroll = ScrollController();
  Severity? _sev;
  Source? _src;
  static const _page = 300;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final res = widget.result;
    final session = widget.session;
    final f = res.findings;
    int sev(Severity v) => f.where((d) => d.severity == v).length;
    final sources = {for (final d in f) d.source};
    final ngRows = res.count(CheckCategory.ng);

    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: SurfaceCard(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.tx)),
              const SizedBox(height: 10),
              ...children,
            ]),
          ),
        );
    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 120, child: Text(k, style: TextStyle(fontSize: 13, color: c.tx2))),
            Expanded(child: Text(v, style: TextStyle(fontSize: 13, color: c.tx))),
          ]),
        );
    Widget stat(String label, int n, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: color.withValues(alpha: c.dark ? 0.16 : 0.09), borderRadius: c.r(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('$n', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
            Text(label, style: TextStyle(fontSize: 12, color: c.tx2)),
          ]),
        );

    final shown = [
      for (final d in f)
        if ((_sev == null || d.severity == _sev) && (_src == null || d.source == _src)) d,
    ];

    return ThinScrollbar(
      controller: _scroll,
      child: ListView(controller: _scroll, padding: const EdgeInsets.only(bottom: 16), children: [
        section(s.t('rep_overview'), [
          kv(s.t('rep_mode'), s.t('cmp_mode_${res.mode.name}')),
          for (final slot in session.slots)
            if (res.files[slot.name] != null) kv(slotLabel(s, res.mode, slot), res.files[slot.name]!),
          kv(s.t('rep_time'), formatTime(res.at)),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 10, children: [
            stat(s.t('rep_lines'), res.rows.length, c.blueTx),
            for (final cat in [CheckCategory.pass, CheckCategory.ng, CheckCategory.excluded, CheckCategory.substitute]) stat(categoryLabel(s, cat), res.count(cat), categoryColor(c, cat)),
          ]),
          const SizedBox(height: 12),
          Text(
            ngRows == 0 && sev(Severity.error) == 0 && sev(Severity.warning) == 0 ? s.t('rep_ok') : s.t('rep_ng', {'n': ngRows, 'e': sev(Severity.error), 'w': sev(Severity.warning)}),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ngRows == 0 ? c.okTx : c.ngTx),
          ),
        ]),
        section(s.t('rep_detection'), [
          for (final slot in session.slots)
            if (session.files[slot] != null) _DetectionSummary(label: slotLabel(s, res.mode, slot), file: session.files[slot]!),
        ]),
        section(s.t('rep_details'), [
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilterPill(label: s.t('sev_all'), active: _sev == null, count: f.length, color: c.textDim, onTap: () => setState(() => _sev = null)),
            for (final v in Severity.values) FilterPill(label: severityLabel(s, v), active: _sev == v, count: sev(v), color: severityColor(c, v), onTap: () => setState(() => _sev = v)),
          ]),
          if (sources.length > 1) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilterPill(label: s.t('rep_by_src'), active: _src == null, count: f.length, color: c.textDim, onTap: () => setState(() => _src = null)),
              for (final src in sources)
                FilterPill(label: compareSourceLabel(s, res.mode, src), active: _src == src, count: f.where((d) => d.source == src).length, color: c.accent, onTap: () => setState(() => _src = src)),
            ]),
          ],
          const SizedBox(height: 12),
          if (shown.isEmpty) Text(s.t('rep_none'), style: TextStyle(fontSize: 13, color: c.okTx)),
          for (final d in shown.take(_page)) _FindingTile(mode: res.mode, d: d),
          if (shown.length > _page) Text(s.t('rep_more', {'n': shown.length - _page}), style: TextStyle(fontSize: 12.5, color: c.tx2)),
        ]),
      ]),
    );
  }
}

class _DetectionSummary extends StatelessWidget {
  const _DetectionSummary({required this.label, required this.file});

  final String label;
  final TableFile file;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final l = file.layout;
    final parts = [
      s.t('rep_sheet', {'s': l.sheet.name}),
      l.headerRow >= 0 ? s.t('rep_header_row', {'n': l.headerRow + 1}) : s.t('rep_no_header'),
    ];
    final mapped = [
      for (final col in l.columns)
        if (col.role != ColumnRole.other) '${roleLabel(s, col.role)} = ${col.letter}${col.header.isEmpty ? '' : '「${col.header}」'}',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$label · ${file.name}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.tx)),
        const SizedBox(height: 2),
        Text(parts.join(' · '), style: TextStyle(fontSize: 12.5, color: c.tx2)),
        const SizedBox(height: 2),
        Text(mapped.join('；'), style: TextStyle(fontSize: 12.5, color: c.tx2)),
        if (file.error != null) Text(s.t('cmp_card_error'), style: TextStyle(fontSize: 12.5, color: c.ngTx)),
      ]),
    );
  }
}

class _FindingTile extends StatelessWidget {
  const _FindingTile({required this.mode, required this.d});

  final CompareMode mode;
  final Discrepancy d;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final color = severityColor(c, d.severity);
    final why = s.t('why_${d.code}');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: c.hover,
        borderRadius: c.r(12),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(severityLabel(s, d.severity), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          Text(compareSourceLabel(s, mode, d.source), style: TextStyle(fontSize: 12, color: c.tx2)),
          if (d.subject.isNotEmpty) Text(d.subject, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.tx)),
        ]),
        const SizedBox(height: 4),
        Text(s.t(d.code, d.args), maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.tx)),
        if (why != 'why_${d.code}') ...[
          const SizedBox(height: 3),
          Text(why, style: TextStyle(fontSize: 12, color: c.tx2, height: 1.4)),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------- designator map

class _RefMap extends StatefulWidget {
  const _RefMap({required this.result});

  final CompareResult result;

  @override
  State<_RefMap> createState() => _RefMapState();
}

class _RefMapState extends State<_RefMap> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  bool _diffOnly = true;

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final q = _search.text.trim().toUpperCase();
    final pairs = [
      for (final p in widget.result.refPairs)
        if ((!_diffOnly || p.state != RefPairState.same) &&
            (q.isEmpty || p.ref.contains(q) || p.pnA.contains(q) || p.pnB.contains(q)))
          p,
    ];
    Color stateColor(RefPairState st) => switch (st) {
          RefPairState.same => c.okTx,
          RefPairState.changed => c.ngTx,
          RefPairState.onlyA || RefPairState.onlyB => c.warnTx,
        };
    Widget cell(String text, double flex, {Color? color, bool bold = false}) => Expanded(
          flex: (flex * 10).round(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(text.isEmpty ? '—' : text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: color ?? (text.isEmpty ? c.textFaint : c.tx), fontWeight: bold ? FontWeight.w600 : null)),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        CheckBox(value: _diffOnly, label: s.t('ref_only_diff'), onChanged: (v) => setState(() => _diffOnly = v)),
        SizedBox(width: 240, child: TextInput(controller: _search, hint: s.t('search_hint'), prefix: Ic.magnifyingGlass, onChanged: (_) => setState(() {}))),
        Text('${pairs.length} / ${widget.result.refPairs.length}', style: TextStyle(fontSize: 12.5, color: c.tx2)),
      ]),
      const SizedBox(height: 10),
      Expanded(
        child: DCard(
          radius: 22,
          clip: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
              child: Row(children: [
                for (final (t, f) in [(s.t('col_ref'), 0.8), (s.t('cc_pnA'), 1.4), (s.t('cc_descA'), 2.0), (s.t('cc_pnB'), 1.4), (s.t('cc_descB'), 2.0), (s.t('ref_state'), 0.9)])
                  cell(t, f, color: c.tx2, bold: true),
              ]),
            ),
            Expanded(
              child: pairs.isEmpty
                  ? EmptyState(icon: Ic.checkCircle, text: s.t('empty_filter'))
                  : ThinScrollbar(
                      controller: _scroll,
                      child: ListView.builder(
                        controller: _scroll,
                        itemCount: pairs.length,
                        itemExtent: 44,
                        itemBuilder: (context, i) {
                          final p = pairs[i];
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
                            child: Row(children: [
                              cell(p.ref, 0.8, bold: true),
                              cell(p.pnA, 1.4),
                              cell(p.descA, 2.0, color: c.tx2),
                              cell(p.pnB, 1.4, color: p.state == RefPairState.changed ? c.ngTx : null),
                              cell(p.descB, 2.0, color: c.tx2),
                              cell(s.t('ref_${p.state.name}'), 0.9, color: stateColor(p.state), bold: true),
                            ]),
                          );
                        },
                      ),
                    ),
            ),
          ]),
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- columns

const _bomRoles = [ColumnRole.partNo, ColumnRole.refs, ColumnRole.qty, ColumnRole.desc, ColumnRole.alt, ColumnRole.other];
const _stationRoles = [ColumnRole.slot, ColumnRole.partNo, ColumnRole.related, ColumnRole.desc, ColumnRole.qty, ColumnRole.refs, ColumnRole.side, ColumnRole.other];

class _Columns extends StatefulWidget {
  const _Columns({required this.session});

  final CompareSession session;

  @override
  State<_Columns> createState() => _ColumnsState();
}

class _ColumnsState extends State<_Columns> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final session = widget.session;
    return ThinScrollbar(
      controller: _scroll,
      child: ListView(controller: _scroll, padding: const EdgeInsets.only(bottom: 16), children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(s.t('cmp_cols_note'), style: TextStyle(fontSize: 12.5, color: c.tx2, height: 1.45)),
        ),
        for (final slot in session.slots)
          if (session.files[slot] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _ColumnsCard(session: session, slot: slot, file: session.files[slot]!),
            ),
      ]),
    );
  }
}

class _ColumnsCard extends StatelessWidget {
  const _ColumnsCard({required this.session, required this.slot, required this.file});

  final CompareSession session;
  final CompareSlot slot;
  final TableFile file;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final l = file.layout;
    final roles = isBomSlot(slot) ? _bomRoles : _stationRoles;
    Widget text(String t, {Color? color, bool bold = false}) =>
        Text(t, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: color ?? c.tx, fontWeight: bold ? FontWeight.w600 : null));
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${slotLabel(s, session.mode, slot)} · ${file.name}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.tx)),
              const SizedBox(height: 2),
              Text(
                '${s.t('rep_sheet', {'s': l.sheet.name})} · ${l.headerRow >= 0 ? s.t('rep_header_row', {'n': l.headerRow + 1}) : s.t('rep_no_header')}',
                style: TextStyle(fontSize: 12.5, color: c.tx2),
              ),
              if (file.error != null) Text(s.t('cmp_card_error'), style: TextStyle(fontSize: 12.5, color: c.ngTx)),
            ]),
          ),
          FlatButton(label: s.t('cmp_cols_reset'), compact: true, onTap: () => session.resetColumns(slot)),
        ]),
        const SizedBox(height: 10),
        Container(height: 1, color: c.line),
        for (final col in l.columns)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
            child: Row(children: [
              SizedBox(width: 36, child: text(col.letter, color: c.tx3, bold: true)),
              Expanded(flex: 3, child: text(col.header.isEmpty ? '—' : col.header, bold: true)),
              const SizedBox(width: 8),
              Expanded(flex: 6, child: text(col.samples.join('  |  '), color: c.tx2)),
              const SizedBox(width: 8),
              DropdownSelect<ColumnRole>(
                value: col.role,
                width: 136,
                flat: true,
                options: [for (final r in roles) (r, roleLabel(s, r))],
                onChanged: (r) => session.setRole(slot, col.index, r),
              ),
              SizedBox(
                width: 72,
                child: Text(
                  col.manual ? s.t('col_manual') : (col.role == ColumnRole.other ? '' : '${(col.confidence * 100).round()}%'),
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, color: col.manual ? c.blueTx : c.tx3),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}
