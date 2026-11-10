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
import '../core/params.dart';
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

Color statusTint(AppColors c, CheckStatus s) => switch (s) {
  CheckStatus.pass => c.okTint,
  CheckStatus.ng => c.ngTint,
  CheckStatus.review => c.warnTint,
  CheckStatus.unmatched => c.blueTint,
  CheckStatus.substitute => aiTint(c),
};

Color statusText(AppColors c, CheckStatus s) => switch (s) {
  CheckStatus.pass => c.okTx,
  CheckStatus.ng => c.ngTx,
  CheckStatus.review => c.warnTx,
  CheckStatus.unmatched => c.blueTx,
  CheckStatus.substitute => aiText(c),
};

Color _statusSolid(AppColors c, CheckStatus s) => switch (s) {
  CheckStatus.pass => c.okSolid,
  CheckStatus.ng => c.ngSolid,
  CheckStatus.review => c.warnSolid,
  CheckStatus.unmatched => c.blue,
  CheckStatus.substitute => aiText(c),
};

String statusLabel(Strings s, CheckStatus d) => s.t('status_${d.name}');

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
  _ => f.key.startsWith('input:')
        ? '${s.t('input_integrity')} ${f.header}'
        : f.header.isEmpty ? f.key.substring(4) : f.header,
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
  final _headerScroll = ScrollController();
  final _storage = PageStorageBucket();
  bool _moreFilters = false;
  bool _directionExpanded = false;
  CompareReport? _directionReport;
  final _directionKey = GlobalKey(debugLabel: 'direction-summary');

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
    _headerScroll.dispose();
    super.dispose();
  }

  void _setFilter(CheckStatus? f) {
    setState(() => _aiOnly = false);
    widget.state.setFilter(widget.state.filter == f ? null : f);
  }

  void _toggleDirections() {
    setState(() => _directionExpanded = !_directionExpanded);
    if (!_directionExpanded) { return; }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_directionExpanded) { return; }
      final target = _directionKey.currentContext;
      if (target != null) { Scrollable.ensureVisible(target, alignment: 0); }
    });
  }

  @override
  Widget build(BuildContext context) => PageStorage(bucket: _storage, child: Builder(builder: _buildPage));

  Widget _buildPage(BuildContext context) {
    final state = widget.state;
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final report = state.report;
    if (!identical(_directionReport, report)) { _directionReport = report; _directionExpanded = false; }
    final phone = isPhoneLayout(context) || widget.cards;
    final narrow = widget.cards;
    final pad = EdgeInsets.fromLTRB(narrow ? 16 : 24, phone ? 4 : 6, narrow ? 16 : 24, 0);
    final imports = ImportBar(state: state, compact: phone);
    final models = LocalModelIndicator(state: state, compact: phone);

    if (report == null) {
      final hint = DCard(
        radius: 24,
        child: state.localAnalysisRequired && state.localStatus == LocalStatus.running
            ? Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Spinner(size: 28), const SizedBox(height: 12),
                Text(s.t(state.localLoading ? 'status_local_required_loading' : 'status_local_required_running'), textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: c.tx)),
                const SizedBox(height: 8),
                Text(s.t('local_analysis_counts', {'n': state.localRows, 'all': state.localTotal, 'b': state.localCalls, 'ms': state.localMillis}), style: TextStyle(fontSize: 12.5, color: c.tx2)),
                const SizedBox(height: 12), TrackBar(value: state.localProgress, color: c.blue), const SizedBox(height: 12),
                PillButton(label: s.t('dlg_cancel'), kind: PillKind.soft, onTap: state.cancelLocalAnalysis),
              ]))
            : state.localAnalysisRequired && state.localStatus == LocalStatus.failed
            ? EmptyState(icon: Lucide.alert, text: '${s.t('local_analysis_no_result')}\n${s.t(state.localError)}')
            : state.cloudRunning
            ? EmptyState(icon: Lucide.sparkles, text: s.t('cloud_full_running', {'done': state.cloudRun?.batchesDone ?? 0, 'all': state.cloudRun?.batches ?? 0}))
            : state.cloudError.isNotEmpty
            ? EmptyState(icon: Lucide.alert, text: '${s.t(state.cloudError)}\n${s.t('cloud_full_failed')}')
            : EmptyState(icon: Lucide.clipboardCheck, text: s.t(state.ready ? 'empty_ready' : 'empty_check_import')),
      );
      if (phone) {
        return ListView(
          padding: EdgeInsets.fromLTRB(pad.left, pad.top, pad.right, bottomInset(context) + 12),
          children: [imports, const SizedBox(height: 8), models, const SizedBox(height: 8), SizedBox(height: 280, child: hint), const SizedBox(height: 8), DirectionReminderPanel(state: state)],
        );
      }
      return Padding(padding: pad, child: LayoutBuilder(builder: (context, box) {
        final short = box.maxHeight < 700;
        final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          imports, const SizedBox(height: 12), models, const SizedBox(height: 12),
          DirectionReminderPanel(state: state), const SizedBox(height: 16),
          short ? SizedBox(height: 280, child: hint) : Expanded(child: hint), const SizedBox(height: 16),
        ]);
        return short ? SingleChildScrollView(child: body) : body;
      }));
    }
    if (_search.text != state.search) _search.text = state.search;

    final total = report.rows.length;
    final aiParts = state.aiParts;
    final statCards = <Widget>[
      for (final (st, icon) in [
        (CheckStatus.pass, Lucide.check),
        (CheckStatus.ng, Lucide.x),
        (CheckStatus.review, Lucide.alert),
        (CheckStatus.unmatched, Lucide.minus),
        (CheckStatus.substitute, Lucide.swap),
      ])
        _StatCard(
          label: statusLabel(s, st),
          icon: icon,
          value: report.count(st),
          total: total,
          tint: statusTint(c, st),
          fg: statusText(c, st),
          bar: _statusSolid(c, st),
          selected: !_aiOnly && state.filter == st,
          onTap: () => _setFilter(st),
        ),
      _StatCard(
        label: s.t(state.localAnalysisRequired ? 'local_analysis_stat' : 'ai_findings'),
        icon: Lucide.sparkles,
        value: state.localAnalysisRequired ? report.localModel.rows : state.ai?.findings.length ?? 0,
        tint: aiTint(c),
        fg: aiText(c),
        bar: aiText(c),
        selected: _aiOnly,
        dim: state.localAnalysisRequired ? report.localModel.state != 'done' : state.ai == null,
        onTap: () {
          if (state.localAnalysisRequired) {
            state.setFilter(null); state.setReasonFilter(null); state.setRiskFilter(null);
            return;
          }
          if (state.ai == null) return;
          state.setFilter(null);
          setState(() => _aiOnly = !_aiOnly);
        },
      ),
    ];
    final stats = LayoutBuilder(builder: (context, box) {
      final columns = box.maxWidth >= 880 ? 6 : 3;
      return Container(key: tourTargets.checkCards, decoration: BoxDecoration(color: c.card, border: c.cardBorder), child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (var start = 0; start < statCards.length; start += columns)
          SizedBox(height: 56, child: Row(children: [
            for (var i = start; i < math.min(start + columns, statCards.length); i++) Expanded(child: statCards[i]),
          ])),
      ]));
    });

    var visible = state.visibleRows();
    if (_aiOnly) visible = visible.where((r) => aiParts.contains(r.partNo)).toList();

    final search = PillSearch(controller: _search, hint: s.t('search_hint'), onChanged: state.setSearch);
    final count = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '${s.t('count_prefix')} '),
          TextSpan(
            text: '${visible.length}',
            style: TextStyle(fontWeight: FontWeight.w600, color: c.tx, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          TextSpan(text: ' ${s.t('count_suffix')}'),
        ],
      ),
      style: TextStyle(fontSize: 14, color: c.tx2),
    );
    final resultSelect = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(s.t('f_result'), style: TextStyle(fontSize: 14, color: c.tx2)),
        const SizedBox(width: 10),
        DropdownSelect<CheckStatus?>(
          value: _aiOnly ? null : state.filter,
          width: 128,
          options: [(null, s.t('opt_all')), for (final d in CheckStatus.values) (d, statusLabel(s, d))],
          onChanged: (v) {
            setState(() => _aiOnly = false);
            state.setFilter(v);
          },
        ),
      ],
    );
    final riskSelect = DropdownSelect<Risk?>(
      value: state.riskFilter,
      width: 120,
      options: [(null, s.t('risk_all')), for (final k in Risk.values) (k, s.t('risk_${k.name}'))],
      onChanged: state.setRiskFilter,
    );
    final reasons = report.reasonCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final reasonSelect = DropdownSelect<String?>(
      value: state.reasonFilter,
      width: 190,
      options: [(null, s.t('reason_all')),
        (
          'orientation',
          '${s.t('orientation_title')} (${report.rows.where((r) => r.orientation.isNotEmpty).length})',
        ), for (final e in reasons) (e.key, '${s.t('reason_${e.key}')} (${e.value})')],
      onChanged: state.setReasonFilter,
    );
    final columnsNote = _ColumnsNote(report: report);
    final filters = KeyedSubtree(key: tourTargets.checkFilters, child: DCard(radius: 14,
      padding: const EdgeInsets.all(8), child: LayoutBuilder(builder: (context, box) {
        if (box.maxWidth >= 880) { return Row(children: [
          Expanded(child: search), const SizedBox(width: 12), resultSelect, const SizedBox(width: 8),
          riskSelect, const SizedBox(width: 8), reasonSelect,
          if (box.maxWidth >= 1250) ...[const SizedBox(width: 12), SizedBox(width: 160, child: columnsNote)],
          const SizedBox(width: 12), count,
        ]); }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [Expanded(child: search), const SizedBox(width: 10), count,
            if (phone) ...[const SizedBox(width: 6), GlassButton(key: const ValueKey('more-check-filters'), icon: Lucide.filter, size: 44,
              tooltip: s.t(_moreFilters ? 'filters_less' : 'filters_more'), onTap: () => setState(() => _moreFilters = !_moreFilters))]]),
          if (!phone || _moreFilters) ...[const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [resultSelect, riskSelect, reasonSelect])],
        ]);
      })));

    Widget metadata() => LayoutBuilder(builder: (context, box) {
      final paired = box.maxWidth >= 900;
      final directions = DirectionReminderPanel(key: _directionKey, state: state, onFilter: () => setState(() => _aiOnly = false),
        expanded: _directionExpanded, onExpand: _toggleDirections, inlineDetails: !paired);
      if (paired) { return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 3, child: models), const SizedBox(width: 8), Expanded(flex: 2, child: directions),
      ]), if (_directionExpanded) ...[const SizedBox(height: 8), DCard(key: const ValueKey('direction-expanded-content'), padding: const EdgeInsets.all(12), radius: 16, child: _DirectionDetails(state: state))]]); }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [models, const SizedBox(height: 8), directions]);
    });
    final top = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      imports, const SizedBox(height: 8), stats, const SizedBox(height: 8), metadata(),
    ]);

    final aiPanel = _AiPanel(state: state);
    final showAi = state.settings.aiEnabled && state.aiStatus != AiStatus.idle;

    if (phone) return _phonePage(context, [top, const SizedBox(height: 8), if (showAi) ...[aiPanel, const SizedBox(height: 8)], filters, const SizedBox(height: 8)], visible, pad);

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
                final width = math.max(box.maxWidth, 1260.0);
                return ThinScrollbar(
                  controller: _hScroll,
                  horizontal: true,
                  child: SingleChildScrollView(
                    key: const PageStorageKey('check-table-columns'),
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
                                key: const PageStorageKey('check-table-rows'),
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
    return Padding(padding: pad, child: LayoutBuilder(builder: (context, box) {
      final selected = state.selected != null;
      final side = box.maxWidth >= 1400 && (selected || showAi);
      final panel = selected ? _Detail(state: state) : aiPanel;
      Widget body = side
        ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: keyedTable), const SizedBox(width: 12), SizedBox(width: 360, child: panel)])
        : keyedTable;
      if (!side && selected) { body = Stack(children: [Positioned.fill(child: keyedTable),
        Positioned(top: 0, bottom: 0, right: 0, width: math.min(420, box.maxWidth * 0.8), child: _Detail(state: state))]); }
      final header = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min,
        children: [top, if (!side && showAi) ...[const SizedBox(height: 8), aiPanel]]);
      final viewport = KeyedSubtree(key: const ValueKey('check-results-viewport'), child: body);
      if (box.maxHeight < 360) { return SingleChildScrollView(controller: _page, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header, const SizedBox(height: 8), filters, const SizedBox(height: 8), SizedBox(height: 360, child: viewport), const SizedBox(height: 12),
      ])); }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ConstrainedBox(constraints: BoxConstraints(maxHeight: box.maxHeight * 0.44),
          child: ThinScrollbar(controller: _headerScroll, child: SingleChildScrollView(key: const PageStorageKey('check-header-scroll'), controller: _headerScroll, child: header))),
        const SizedBox(height: 8), filters, const SizedBox(height: 8), Expanded(child: viewport), const SizedBox(height: 12),
      ]);
    }));
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
          key: const PageStorageKey('check-card-rows'),
          controller: _page,
          padding: EdgeInsets.fromLTRB(pad.left, pad.top, pad.right, bottomInset(context) + (selected == null ? 12 : 320)),
          itemCount: visible.length + head.length,
          itemBuilder: (context, i) {
            if (i < head.length) return head[i];
            final row = visible[i - head.length];
            final card = DecoratedBox(decoration: BoxDecoration(color: c.card, border: Border(bottom: BorderSide(color: c.lineStrong))),
              child: _RowCard(state: state, row: row, ai: aiParts.contains(row.partNo)));
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

/// Assembly reminders stay visible as a compact summary; details open on demand.
class DirectionReminderPanel extends StatefulWidget {
  const DirectionReminderPanel({super.key, required this.state, this.onFilter, this.expanded, this.onExpand, this.inlineDetails = true});
  final AppState state;
  final VoidCallback? onFilter;
  final bool? expanded;
  final VoidCallback? onExpand;
  final bool inlineDetails;
  @override
  State<DirectionReminderPanel> createState() => _DirectionReminderPanelState();
}

class _DirectionReminderPanelState extends State<DirectionReminderPanel> {
  bool _expanded = false;
  CompareReport? _report;
  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final report = state.report;
    if (!identical(_report, report)) { _expanded = false; _report = report; }
    final expanded = widget.expanded ?? _expanded;
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final rows = report?.rows.where((r) => r.orientation.isNotEmpty).toList() ?? <CompareRow>[];
    final refs = <String>{};
    for (final row in rows) {
      for (final h in row.orientation) { refs.addAll(h.refs); }
    }
    return DCard(key: const ValueKey('direction-reminders-panel'), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), radius: 16,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [Expanded(child: Hoverable(tooltip: s.t('orientation_scope'), builder: (context, hover, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.t('orientation_title'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.tx)),
          const SizedBox(height: 3), Text(s.t(report == null ? 'direction_waiting' : rows.isEmpty ? 'direction_no_items' : 'direction_panel_counts', {'n': rows.length, 'refs': refs.length}),
            maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: rows.isEmpty ? c.tx2 : c.warnTx)),
        ]))), if (rows.isNotEmpty) ...[
          const SizedBox(width: 8), Semantics(toggled: state.reasonFilter == 'orientation', child: DecoratedBox(position: DecorationPosition.foreground,
            decoration: BoxDecoration(borderRadius: c.r(22), border: state.reasonFilter == 'orientation' ? Border.all(color: c.warnTx, width: 1.5) : null),
            child: GlassButton(key: const ValueKey('direction-filter'), icon: Lucide.filter, size: 44,
            tooltip: s.t(state.reasonFilter == 'orientation' ? 'direction_show_all' : 'direction_filter'), onTap: () {
              final off = state.reasonFilter == 'orientation';
              if (!off) { state.setFilter(null); state.setRiskFilter(null); state.setSearch(''); }
              widget.onFilter?.call(); state.setReasonFilter(off ? null : 'orientation');
            }))),
          GlassButton(key: const ValueKey('direction-expand'), icon: expanded ? Lucide.chevronUp : Lucide.chevronDown, size: 44,
            tooltip: s.t(expanded ? 'direction_collapse' : 'direction_expand'), onTap: widget.onExpand ?? () => setState(() => _expanded = !_expanded)),
        ]]),
        if (expanded && rows.isNotEmpty && widget.inlineDetails) ...[
          const SizedBox(height: 8), _DirectionDetails(state: state),
        ],
      ]));
  }
}

class _DirectionDetails extends StatelessWidget {
  const _DirectionDetails({required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final rows = state.report!.rows.where((r) => r.orientation.isNotEmpty).toList();
    final counts = <String, int>{};
    for (final row in rows) {
      for (final h in row.orientation) { counts.update(h.code, (n) => n + 1, ifAbsent: () => 1); }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Wrap(spacing: 6, runSpacing: 6, children: [for (final e in counts.entries)
        DBadge(text: '${s.t('orientation_short_${e.key}')} · ${e.value}', background: c.warnTint, color: c.warnTx)]),
      const SizedBox(height: 8), Text(s.t('orientation_scope'), style: TextStyle(fontSize: 12, height: 1.4, color: c.tx2)), const SizedBox(height: 8),
      LayoutBuilder(builder: (context, box) {
        final columns = box.maxWidth >= 1000 ? 3 : box.maxWidth >= 600 ? 2 : 1;
        return SizedBox(height: math.min(180, ((rows.length + columns - 1) ~/ columns) * 72.0), child: GridView.builder(
          key: const ValueKey('direction-details-list'), primary: false, itemCount: rows.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, mainAxisExtent: 66),
          itemBuilder: (context, i) {
            final row = rows[i]; final hints = row.orientation;
            return Hoverable(onTap: () => state.select(row), builder: (context, hover, _) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(color: hover ? c.hover : c.card, border: Border(bottom: BorderSide(color: c.line), right: BorderSide(color: c.line))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('${row.partNo} · ${hints.map((h) => s.t('orientation_short_${h.code}')).join(' / ')}', maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.warnTx)),
                Text(hints.expand((h) => h.refs).toSet().join(', '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.tx2)),
              ])));
          }));
      }),
    ]);
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
    // Fields switched off in the settings are named apart.
    final on = CompareOptions(skip: report.skipped.toSet());
    final compared = [
      for (final (k, label) in [('description', s.t('f_desc')), ('quantity', s.t('f_qty')), ('refs', s.t('f_refs'))])
        if (on.checks(k)) label,
      for (final e in report.compared.entries)
        if (on.checks(e.key)) e.value,
    ];
    final skipped = [...report.singleOnlyColumns, ...report.mergedOnlyColumns];
    final off = [for (final k in report.skipped) s.t('cmpf_$k')];
    final tip = [if (skipped.isNotEmpty) s.t('cols_skipped', {'cols': skipped.join('、')}), if (off.isNotEmpty) s.t('cols_off', {'cols': off.join('、')})].join('\n');
    return Hoverable(
      tooltip: tip.isEmpty ? null : tip,
      builder: (context, hover, _) => Text(
        s.t('cols_compared', {'cols': compared.join('、')}) + (skipped.isEmpty ? '' : s.t('cols_skipped_short', {'n': skipped.length})) + (off.isEmpty ? '' : s.t('cols_off_short', {'n': off.length})),
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
    return Hoverable(onTap: onTap, tooltip: '$label: $value${total == null ? '' : ' / $total · $pct'}',
      builder: (context, hover, _) => Opacity(opacity: dim ? 0.55 : 1, child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(color: selected ? tint : hover ? c.hover : c.card, borderRadius: c.r(12),
          border: Border.all(color: selected ? fg.withValues(alpha: 0.55) : c.lineStrong.withValues(alpha: c.industrial ? 1 : 0.35))),
        child: LayoutBuilder(builder: (context, box) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(children: [if (box.maxWidth >= 130) ...[LucideIcon(icon, size: 16, color: fg), const SizedBox(width: 7)],
            Expanded(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, height: 1.1, fontWeight: FontWeight.w600, color: c.tx))),
            const SizedBox(width: 6), Text('$value', style: TextStyle(fontSize: 20, height: 1, fontWeight: FontWeight.w700, color: fg, fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
          if (share != null) ...[const SizedBox(height: 5), TrackBar(value: share, color: bar, height: 2)],
        ])),
      )));
  }
}

/// Column widths: fixed px, or flex weight with a minimum.
const _cols = [
  (40.0, 0.0), // #
  (190.0, 0.8), // part number
  (240.0, 1.6), // description (A over B+C)
  (90.0, 0.0), // quantity
  (190.0, 1.1), // designators
  (110.0, 0.0), // other columns
  (220.0, 0.6), // orientation reminders
  (120.0, 0.0), // result, including translated labels and an optional AI mark
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
        // Put the verdict beside the part number, within a laptop viewport.
        for (final i in const [0, 1, 7, 2, 3, 4, 5, 6])
          SizedBox(
            width: _cols[i].$1 * shrink + (flex == 0 ? 0 : spare * _cols[i].$2 / flex),
            child: Align(alignment: i == 7 || i == 3 ? Alignment.center : Alignment.centerLeft, child: cells[i]),
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
      child: _gridRow([Text('#', style: style), t('f_part_no'), t('f_desc_both'), t('f_qty_both'), t('f_refs'), t('f_other'),
        t('orientation_title'), t('f_result')]),
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
          SizedBox(width: 30, child: Text(Strings.of(context).t('side_merged'), style: tag)),
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
        margin: const EdgeInsets.only(top: 2),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? c.rowSel
              : hover
              ? c.hover
              : null,
          borderRadius: c.r(14),
          border: Border(bottom: BorderSide(color: c.line)),
        ),
        child: _gridRow([
          Text('$index', style: TextStyle(fontSize: 13, color: c.tx3, fontFeatures: const [FontFeature.tabularFigures()])),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Long numbers wrap rather than being cut off.
              Text(row.partNo, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.tx)),
              if (row.sources.isNotEmpty) Text(row.sourceNames.join(' + '), style: TextStyle(fontSize: 11, color: c.tx3)),
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
          _OrientationCell(row: row),
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
              Flexible(child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: statusTint(c, row.status), borderRadius: c.r(12)),
                child: Text(statusLabel(s, row.status), maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, height: 1.2, fontWeight: FontWeight.w600, color: statusText(c, row.status))))),
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
                DBadge(text: statusLabel(s, row.status), background: statusTint(c, row.status), color: statusText(c, row.status)),
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
            if (row.orientation.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: c.warnTint,
                  borderRadius: c.r(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                s.t('orientation_title'),
                style: TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: c.warnTx),
              ),
                    const SizedBox(height: 4),
                    _OrientationCell(row: row),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact, actionable reminders. Full evidence stays in the part detail.
class _OrientationCell extends StatelessWidget {
  const _OrientationCell({required this.row});
  final CompareRow row;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    if (row.orientation.isEmpty) {
      return Text('—', style: TextStyle(color: c.tx3));
    }
    final tip = [
      for (final h in row.orientation)
        '${s.t('orientation_${h.code}')}\n${h.evidence}\n${h.refs.isEmpty ? s.t('orientation_no_refs') : h.refs.join(', ')}',
      s.t('orientation_scope'),
    ].join('\n\n');
    return Hoverable(
      key: ValueKey('orientation-${row.partNo}'),
      tooltip: tip,
      cursor: SystemMouseCursors.help,
      builder: (context, hover, _) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final h in row.orientation) ...[
              Text(
                s.t('orientation_short_${h.code}'),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: c.warnTx,
                ),
              ),
              Text(
                h.refs.isEmpty
                    ? s.t('orientation_no_refs')
                    : '${h.refs.take(6).join(', ')}${h.refs.length > 6 ? ' … (+${h.refs.length - 6})' : ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, height: 1.4, color: c.tx2),
              ),
            ],
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
              SizedBox(width: 52, child: Text(s.t('side_merged'), style: TextStyle(fontSize: 11.5, color: c.tx3))),
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
          DBadge(text: statusLabel(s, row.status), background: statusTint(c, row.status), color: statusText(c, row.status)),
          const SizedBox(width: 8),
          GlassButton(icon: Lucide.x, size: 44, iconSize: 16, tooltip: s.t('dlg_close'), onTap: () => state.select(null)),
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
      // What the line was matched by, and why it is not PASS.
      if (row.orientation.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: c.warnTint, borderRadius: c.r(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.t('orientation_title'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.warnTx,
                ),
              ),
              Text(
                s.t('orientation_scope'),
                style: TextStyle(fontSize: 12, height: 1.4, color: c.tx2),
              ),
              for (final h in row.orientation) ...[
                const SizedBox(height: 6),
                Text(
                  s.t('orientation_${h.code}'),
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: c.warnTx,
                  ),
                ),
                Text(
                  h.evidence,
                  style: TextStyle(fontSize: 12, height: 1.4, color: c.tx2),
                ),
                Text(
                  h.refs.isEmpty
                      ? s.t('orientation_no_refs')
                      : h.refs.join(', '),
                  style: TextStyle(fontSize: 12, color: c.tx),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
      if (row.basis.kinds.isNotEmpty || row.reasons.isNotEmpty || row.cloudNote.isNotEmpty || row.localNote.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: row.status == CheckStatus.pass ? c.well : statusTint(c, row.status), borderRadius: c.r(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (row.basis.kinds.isNotEmpty)
                Text(
                  s.t('match_by', {'by': row.basis.kinds.map((k) => s.t('basis_$k')).join(' + '), 'c': (row.basis.confidence * 100).round()}),
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: row.status == CheckStatus.pass ? c.tx2 : statusText(c, row.status)),
                ),
              if (row.otherPartNo.isNotEmpty) Text(s.t('match_other_pn', {'pn': row.otherPartNo}), style: TextStyle(fontSize: 12.5, color: c.tx2)),
              for (final r in row.reasons) Text('• ${s.t('reason_$r')}', style: TextStyle(fontSize: 13, height: 1.45, color: statusText(c, row.status))),
              if (row.localNote.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(s.t('local_note_result', {'n': row.localNote}), style: TextStyle(fontSize: 12.5, height: 1.45, color: aiText(c))),
              ],
              if (row.cloudNote.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(s.t('cloud_note', {'n': row.cloudNote}), style: TextStyle(fontSize: 12.5, height: 1.45, color: aiText(c))),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
      if (row.status == CheckStatus.unmatched) ...[
        field(s.t('f_desc'), row.single?.description ?? '', row.merged?.description ?? '', const [], const [], true),
      ],
      for (final f in row.fields)
        if (f.key != 'refs') ...[
          field(fieldLabel(s, f), f.single, f.merged, f.singleSpans, f.mergedSpans, f.equal && !f.incomplete),
          if (f.equivalent) Padding(padding: const EdgeInsets.only(left: 4, bottom: 8), child: Text(s.t('equiv_note'), style: TextStyle(fontSize: 12, color: c.okTx))),
          if (f.key == 'description' && (normalisedParams(f.single).isNotEmpty || normalisedParams(f.merged).isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10),
              child: Text(
                s.t('params_norm', {'a': normalisedParams(f.single).isEmpty ? '—' : normalisedParams(f.single), 'b': normalisedParams(f.merged).isEmpty ? '—' : normalisedParams(f.merged)}),
                style: TextStyle(fontSize: 12, height: 1.5, color: c.tx2),
              ),
            ),
        ],
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
              if (f.mergedValue.isNotEmpty) Text('${s.t('side_merged')}: ${f.mergedValue}', style: TextStyle(fontSize: 12, color: c.tx2)),
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
                ai == null ? state.settings.cloud.modelName : '${ai.model} · ${formatTime(ai.at)} · ${ai.usage.inputTokens + ai.usage.outputTokens} tokens · \$${ai.usage.cost.toStringAsFixed(4)}',
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
