/// Docked side panels: project files / summary and the row inspector.
library;

import 'package:flutter/widgets.dart';
import 'icons.dart';

import '../app_state.dart';
import '../core/models.dart';
import '../l10n/strings.dart';
import 'actions.dart';
import 'theme.dart';
import 'widgets.dart';

class ProjectPanel extends StatelessWidget {
  const ProjectPanel({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final report = state.report;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: DockPanel(
            title: s.t('panel_files'),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                _FileEntry(state: state, kind: InputKind.bom, icon: Ic.treeStructure, title: s.t('btn_bom'), file: state.bom, count: state.bom?.result.items.length),
                _FileEntry(state: state, kind: InputKind.stationA, icon: Ic.squaresFour, title: s.t('btn_station_a'), file: state.stationA, count: state.stationA?.result.items.length),
                _FileEntry(state: state, kind: InputKind.stationB, icon: Ic.gridFour, title: s.t('btn_station_b'), file: state.stationB, count: state.stationB?.result.items.length),
                _FileEntry(state: state, kind: InputKind.coords, icon: Ic.crosshair, title: s.t('btn_coord'), file: state.coords, count: state.coords?.result.items.length),
              ],
            ),
          ),
        ),
        HDivider(),
        Expanded(
          flex: 2,
          child: DockPanel(
            title: s.t('panel_summary'),
            child: report == null
                ? Padding(padding: const EdgeInsets.all(12), child: Text(s.t('empty_check'), style: TextStyle(color: c.textFaint, fontSize: 12)))
                : ListView(
                    padding: const EdgeInsets.all(10),
                    children: [
                      _SummaryBar(report: report),
                      const SizedBox(height: 10),
                      for (final cat in CheckCategory.values)
                        _SummaryLine(
                          color: c.category(cat),
                          label: s.t(switch (cat) {
                            CheckCategory.pass => 'cat_pass',
                            CheckCategory.ng => 'cat_ng',
                            CheckCategory.excluded => 'cat_excluded',
                            CheckCategory.substitute => 'cat_substitute',
                          }),
                          value: report.count(cat),
                          onTap: () => state.setFilter(cat),
                        ),
                      _SummaryLine(color: c.textDim, label: s.t('cat_all'), value: report.rows.length, onTap: () => state.setFilter(null)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _FileEntry extends StatelessWidget {
  const _FileEntry({required this.state, required this.kind, required this.icon, required this.title, required this.file, required this.count});

  final AppState state;
  final InputKind kind;
  final IconData icon;
  final String title;
  final LoadedFile<Object?>? file;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final loaded = file != null;
    final issues = file?.result.issues ?? const [];
    final columns = file?.result.columns ?? const {};
    return Hoverable(
      onTap: () => importFile(context, state, kind),
      builder: (context, hover, _) => Container(
        color: hover ? c.hover : null,
        padding: const EdgeInsets.fromLTRB(10, 7, 4, 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 18, color: loaded ? c.accent : c.textFaint),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5))),
                    if (loaded)
                      Text(s.t('file_items', {'n': count}), style: TextStyle(color: c.textDim, fontSize: 11.5)),
                  ]),
                  Text(
                    file?.name ?? s.t('file_none'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: loaded ? c.textDim : c.textFaint),
                  ),
                  if (columns.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        columns.entries.where((e) => e.key != 'unit').map((e) => e.value).join(' · ') +
                            (columns['unit'] != null ? '  [${columns['unit']}]' : ''),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: c.textFaint),
                      ),
                    ),
                  for (final i in issues.take(3))
                    Text(s.t(i.code, {'row': i.row, 'detail': i.detail}),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: c.substitute)),
                  if (issues.length > 3)
                    Text('+${issues.length - 3}', style: TextStyle(fontSize: 11, color: c.substitute)),
                ],
              ),
            ),
            if (loaded)
              IconBtn(icon: Ic.x, size: 22, tooltip: s.t('file_remove'), onTap: () => state.unload(kind)),
          ],
        ),
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.report});

  final CheckReport report;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final total = report.rows.length;
    if (total == 0) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 8,
        child: Row(children: [
          for (final cat in CheckCategory.values)
            if (report.count(cat) > 0) Expanded(flex: report.count(cat), child: Container(color: c.category(cat))),
        ]),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.color, required this.label, required this.value, required this.onTap});

  final Color color;
  final String label;
  final int value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Hoverable(
      onTap: onTap,
      builder: (context, hover, _) => Container(
        color: hover ? c.hover : null,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(children: [
          Container(width: 8, height: 8, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(fontSize: 12.5, color: c.text))),
          Text('$value', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: c.text)),
        ]),
      ),
    );
  }
}

class InspectorPanel extends StatelessWidget {
  const InspectorPanel({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final row = state.selected;
    return DockPanel(
      title: s.t('panel_inspector'),
      child: row == null
          ? Padding(padding: const EdgeInsets.all(12), child: Text(s.t('inspector_empty'), style: TextStyle(color: c.textFaint, fontSize: 12)))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text(row.partNo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 2),
                Text(row.description, style: TextStyle(color: c.textDim, fontSize: 12.5)),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ResultBadge(
                    text: categoryLabel(s, row.category),
                    color: c.category(row.category),
                    icon: row.category == CheckCategory.pass ? IcBold.checkCircle : IcBold.info,
                  ),
                ),
                const SizedBox(height: 12),
                _Prop(label: s.t('col_bom_qty'), value: row.bomQty == null ? '-' : _fmt(row.bomQty!)),
                _Prop(label: s.t('col_smt_qty'), value: row.smtQty?.toString() ?? '-'),
                _Prop(label: s.t('col_smt_pn'), value: row.smtPartNos.isEmpty ? '-' : row.smtPartNos.join('\n')),
                _Prop(
                    label: s.t('col_side'),
                    value: row.sides.isEmpty ? '-' : (row.sides.toList()..sort((a, b) => a.index - b.index)).map((e) => s.t(e == StationSide.a ? 'side_a' : 'side_b')).join(' / ')),
                _Prop(label: s.t('col_slot'), value: row.slots.isEmpty ? '-' : row.slots.join(', ')),
                const SizedBox(height: 8),
                Text(s.t('col_reason'), style: TextStyle(color: c.textDim, fontSize: 12)),
                const SizedBox(height: 4),
                if (row.reasons.isEmpty) Text('-', style: TextStyle(color: c.textFaint)),
                for (final r in row.reasons)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: r.info ? c.panelAlt : c.ngSoft,
                      border: Border(left: BorderSide(color: r.info ? c.substitute : c.ng, width: 2)),
                    ),
                    child: Text(s.t(r.code, r.args), style: TextStyle(fontSize: 12.5, color: c.text)),
                  ),
              ],
            ),
    );
  }
}

String _fmt(double q) => q == q.roundToDouble() ? q.toInt().toString() : q.toString();

class _Prop extends StatelessWidget {
  const _Prop({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 92, child: Text(label, style: TextStyle(color: c.textDim, fontSize: 12))),
          Expanded(child: Text(value, style: TextStyle(fontSize: 12.5, color: c.text))),
        ],
      ),
    );
  }
}
